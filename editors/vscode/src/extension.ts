/*
	HIGHLY inspired by the wonderful rust-analyzer, and contains modification of code from rust-analyzer vscode extension.
*/

import * as vscode from 'vscode';
import * as path from "path";
import * as os from "os";
import { promises as fs, constants, writeFileSync } from "fs";

var AdmZip = require('adm-zip');

import {
	LanguageClient,
	LanguageClientOptions,
	ServerOptions
} from 'vscode-languageclient/node';

import { log, assert, isValidExecutable } from './util';
import { RunnableCodeLensProvider } from "./run";
import { PersistentState } from './persistent_state';
import { Config } from './config';
import { fetchRelease, download } from './net';
import { isOdinInstalled } from './toolchain';
import { Ctx } from './ctx';
import { runDebugTest, runTest } from './commands';
import { watchOlsConfigFile } from './watch';

const onDidChange: vscode.EventEmitter<void> = new vscode.EventEmitter<void>();

const JSON5 = require('json5')

const defaultConfig = JSON.stringify(
	{
		$schema: "https://raw.githubusercontent.com/DanielGavin/ols/master/misc/ols.schema.json",
		enable_document_symbols: true,
		enable_hover: true,
		enable_snippets: true
	},
	null,
	4,
);

let ctx: Ctx;

let outputChannel: vscode.LogOutputChannel;

export async function activate(context: vscode.ExtensionContext) {

	const config = new Config(context);
	const state = new PersistentState(context.globalState);

	log.setEnabled(true);

	const serverPath = await bootstrap(config, state).catch(err => {
		let message = "bootstrap error. ";

		if (err.code === "EBUSY" || err.code === "ETXTBSY" || err.code === "EPERM") {
			message += "Other vscode windows might be using ols, ";
			message += "you should close them and reload this window to retry. ";
		}

		log.error("Bootstrap error", err);
		throw new Error(message);
	});

	checkForUpdates(config, state, false)


	const workspaceFolder = vscode.workspace.workspaceFolders?.[0];

	if (workspaceFolder === undefined) {
		throw new Error("no folder is opened");
	}

	const codeLensProvider = new RunnableCodeLensProvider(
		onDidChange,
	);

	const disposable = vscode.languages.registerCodeLensProvider(
		{ scheme: "file", language: "odin" },
		codeLensProvider
	);

	context.subscriptions.push(
		vscode.workspace.onDidChangeConfiguration(e => {
			codeLensProvider.updateArgs();
		})
	);

	context.subscriptions.push(disposable);

	if (!serverPath) {
		vscode.window.showErrorMessage("Failed to find ols executable!");
		return;
	}

	let serverOptions: ServerOptions = {
		command: serverPath,
		args: [],
		options: {
			cwd: path.dirname(serverPath),
		},
	};


	outputChannel = vscode.window.createOutputChannel("Odin Language Server", { log: true });


	let clientOptions: LanguageClientOptions = {
		documentSelector: [{ scheme: 'file', language: 'odin' }],
		outputChannel: outputChannel,
	};

	var client = new LanguageClient(
		'ols',
		'Odin Language Server Client',
		serverOptions,
		clientOptions
	);

	ctx = await Ctx.create(config, client, context, serverPath, workspaceFolder.uri.fsPath);

	ctx.registerCommand("runDebugTest", runDebugTest);
	ctx.registerCommand("runTest", runTest);

	const projectConfigPath = path.join(workspaceFolder.uri.fsPath, "ols.json");
	const userConfigPath = path.join(path.dirname(serverPath), "ols.json");

	fs.access(projectConfigPath, constants.F_OK).catch(async (_e1) => {
		fs.access(userConfigPath, constants.F_OK).catch(async (_e2) => {
			if (!config.askCreateOLS) {
				return;
			}

			const userResponse = await vscode.window.showInformationMessage(
				"No ols config file found. Do you wish to create one?",
				"Yes",
				"No",
				"Don't ask again",
			);

			if (userResponse === "Yes") {
				const clarification = await vscode.window.showInformationMessage(
					"should it be specific to this project or to all your odin projects?",
					"This project",
					"All projects",
				);
				if (clarification == "This project") {
					createOrEditProjectConfig();
					parseOlsFile(config, projectConfigPath);
				} else {
					createOrEditUserConfig(serverPath);
					parseOlsFile(config, userConfigPath);
				}
			} else if (userResponse === "Don't ask again") {
				config.updateAskCreateOLS(false);
				return;
			}
		})
	});

	// parse ols file first, so we can pass it to "isOdinInstalled"
	// in order to check if the path to odin was defined in the ols file
	try {
		await parseOlsFile(config, projectConfigPath);
	}
	catch (error) {
		log.error("Failed to parse ols configuration");
	}

	if (!isOdinInstalled(config)) {
		vscode.window.showErrorMessage("Odin cannot be found in your path environment. Please install Odin or add it into your path environment before going any further: [Install](https://odin-lang.org/docs/install/).");
	}

	vscode.commands.registerCommand("ols.start", () => {
		client.start();
	});

	vscode.commands.registerCommand("ols.stop", async () => {
		await client.stop();
	});

	vscode.commands.registerCommand("ols.restart", async () => {
		await client.stop();
		client.start();
	});

	vscode.commands.registerCommand("ols.editProjectConfig", async () => {
		createOrEditProjectConfig();
	});

	vscode.commands.registerCommand("ols.editUserConfig", async () => {
		createOrEditUserConfig(serverPath);
	});

	client.start();

	watchOlsConfigFile(ctx, projectConfigPath);
}

async function bootstrap(config: Config, state: PersistentState): Promise<string> {
	await fs.mkdir(config.globalStorageUri.fsPath, { recursive: true });

	const path = await bootstrapServer(config, state);

	await removeOldServers(config, state);

	return path;
}

async function bootstrapServer(config: Config, state: PersistentState): Promise<string> {
	const path = await getServer(config, state);
	if (!path) {
		throw new Error(
			"ols is not available. " +
			"Please, ensure its [installed](https://github.com/DanielGavin/ols/#installation)."
		);
	}

	log.info("Using server binary at", path);

	/*
		TODO(add version)
	if (!isValidExecutable(path)) {
		throw new Error(`Failed to execute ${path} --version`);
	}
	*/

	return path;
}

async function removeOldServers(config: Config, state: PersistentState): Promise<void> {
	if (process.platform != "win32") {
		// only on windows, releases are put into their separate folders, so no cleanup needed
		return;
	}
	const releasesFolder = config.globalStorageUri.fsPath;

	// get list of all old releases
	const currentRelease = state.releaseId?.toString() ?? ""
	const releases = (await fs.readdir(releasesFolder, { withFileTypes: true }))
		.filter(dirent => dirent.isDirectory() && dirent.name != currentRelease)
		.map(dirent => dirent.name)

	// try to delete all old releases
	for (const release of releases) {
		try {
			let pathToRemove = path.join(releasesFolder, release)
			if (release[0] !== '_') {
				// windows: rename path first to ensure it is not in use anymore
				const renamedPath = path.join(releasesFolder, '_' + release)
				await fs.rename(pathToRemove, renamedPath)
				pathToRemove = renamedPath
			}
			fs.rm(pathToRemove, { recursive: true, force: true })
		} catch {
			// ignore if the release can't be renamed/removed, probably still in use
			continue;
		}
	}
}

export function createOrEditProjectConfig() {
	const projectConfigPath = vscode.workspace.workspaceFolders![0].uri.fsPath;
	openFileAndCreateIfNotExists("ols.json", projectConfigPath, defaultConfig);
}

export function createOrEditUserConfig(serverPath: string) {
	const userConfigPath = path.dirname(serverPath);
	openFileAndCreateIfNotExists("ols.json", userConfigPath, defaultConfig);
}

function openFileAndCreateIfNotExists(file: string, folder: string, defaultContents: string) {
	const filePath = path.join(folder, file);
	console.log(filePath);

	vscode.workspace.openTextDocument(filePath).then(
		(document) => { vscode.window.showTextDocument(document) },
		() => {
			writeFileSync(filePath, defaultContents);
			vscode.workspace.openTextDocument(filePath).then(
				(document) => { vscode.window.showTextDocument(document) }
			);
		}
	);

}

export async function parseOlsFile(config: Config, file: string) {
	/*
		We have to parse the collections that they have specificed through the json(This will be changed when odin gets it's own builder files)
	*/
	await fs.readFile(file).then(
		(data) => {
			const conf = JSON5.parse(data.toString());
			config.collections = conf.collections;
			if (conf.hasOwnProperty("odin_command")) {
				config.odinCommand = conf.odin_command;
			}

		},
		(error) => {
			console.info("no ols.json found in workspace");
		},
	);
}

function serverPath(config: Config): string | null {
	return config.serverPath;
}

function getPlatform(): string {
	const platforms: { [key: string]: string } = {
		"x64 win32": "x86_64-pc-windows-msvc",
		"x64 linux": "x86_64-unknown-linux-gnu",
		"x64 darwin": "x86_64-darwin",
		"arm64 darwin": "arm64-darwin"
	};

	let platform = platforms[`${process.arch} ${process.platform}`];
	return platform
}

function getDestFolder(config: Config, releaseId: number | undefined): string {
	return path.join(config.globalStorageUri.fsPath, (releaseId ?? 0).toString());
}

function getExt(): string {
	const platform = getPlatform()
	const isWindows = platform.indexOf("-windows-") !== -1;
	const ext = isWindows ? ".exe" : "";

	return ext
}


function getExecutable(config: Config, releaseId: number | undefined): string {
	const platform = getPlatform()
	const ext = getExt()
	return path.join(getDestFolder(config, releaseId), `ols-${platform}${ext}`);
}


async function getServer(config: Config, state: PersistentState): Promise<string | undefined> {
	const explicitPath = serverPath(config);
	if (explicitPath) {
		if (explicitPath.startsWith("~/")) {
			return os.homedir() + explicitPath.slice("~".length);
		}
		return explicitPath;
	};

	const platform = getPlatform()
	if (platform === undefined) {
		await vscode.window.showErrorMessage(
			"Unfortunately we don't ship binaries for your platform yet. " +
			"You need to manually clone ols, build it, set the ols.server.path to the executable"
		);
		return undefined;
	}

	/*
	if (platform === "x86_64-unknown-linux-gnu" && isMusl()) {
		platform = "x86_64-unknown-linux-musl";
	}
	*/

	const destExecutable = getExecutable(config, state.releaseId);

	const exists = await fs.stat(destExecutable).then(() => true, () => false);

	if (!exists) {
		await state.updateReleaseId(0);
		await checkForUpdates(config, state, !exists)
	}

	/*
		Temp: right now it doesn't check for versions, since ols has no versioning right now
	*/
	return destExecutable
}

async function checkForUpdates(config: Config, state: PersistentState, required: boolean): Promise<void> {
	const platform = getPlatform()
	const release = await downloadWithRetryDialog(state, required, async () => {
		return await fetchRelease("nightly", state.githubToken, config.httpProxy);
	});

	if (release === undefined || release.id === state.releaseId) {
		await state.updateLastCheck(Date.now());
		return;
	}

	const userResponse = await vscode.window.showInformationMessage(
		"New version of ols (nightly) is available (requires reload).",
		"Update"
	);

	if (userResponse !== "Update") {
		return;
	}

	const artifact = release.assets.find(artifact => artifact.name === `ols-${platform}.zip`);
	assert(!!artifact, `Bad release: ${JSON.stringify(release)}`);

	const zipFolder = config.globalStorageUri.fsPath;
	const destZip = path.join(zipFolder, `ols-${platform}.zip`);

	await downloadWithRetryDialog(state, true, async () => {
		await download({
			url: artifact.browser_download_url,
			dest: destZip,
			progressTitle: "Downloading ols",
			httpProxy: config.httpProxy,
		});
	});

	var zip = new AdmZip(destZip);


	const latestDestFolder = getDestFolder(config, release.id);
	const latestExecutable = getExecutable(config, release.id);

	if (!await fs.stat(latestDestFolder).then(() => true, () => false)) {
		await fs.mkdir(latestDestFolder);
	}

	zip.extractAllTo(latestDestFolder, true);

	const ext = getExt();
	if (ext !== ".exe") {
		fs.chmod(latestExecutable, 0o755);
	}

	const prevFolder = getDestFolder(config, state.releaseId);
	const prevOlsConfig = `${prevFolder}/ols.json`;
	if (await fs.stat(prevOlsConfig).then(() => true, () => false)) {
		await fs.copyFile(prevOlsConfig, `${latestDestFolder}/ols.json`)
	}

	await state.updateServerVersion(config.package.version);
	await state.updateReleaseId(release.id);
	await state.updateLastCheck(Date.now());
	await vscode.commands.executeCommand("workbench.action.reloadWindow");

	return;
}

async function downloadWithRetryDialog<T>(state: PersistentState, required: boolean, downloadFunc: () => Promise<T>): Promise<T> {
	while (true) {
		try {
			return await downloadFunc();
		} catch (e) {
			const selected = await vscode.window.showErrorMessage("Failed to download: " + e.message, {}, {
				title: "Update Github Auth Token",
				updateToken: true,
			}, {
				title: "Retry download",
				retry: true,
			}, {
				title: "Dismiss",
			});

			if (selected?.updateToken) {
				await queryForGithubToken(state);
				continue;
			} else if (selected?.retry) {
				continue;
			} else if (!required) {
				return;
			}
			throw e;
		};
	}
}

async function queryForGithubToken(state: PersistentState): Promise<void> {
	const githubTokenOptions: vscode.InputBoxOptions = {
		value: state.githubToken,
		password: true,
		prompt: `
            This dialog allows to store a Github authorization token.
            The usage of an authorization token will increase the rate
            limit on the use of Github APIs and can thereby prevent getting
            throttled.
            Auth tokens can be created at https://github.com/settings/tokens`,
	};

	const newToken = await vscode.window.showInputBox(githubTokenOptions);
	if (newToken === undefined) {
		// The user aborted the dialog => Do not update the stored token
		return;
	}

	if (newToken === "") {
		log.info("Clearing github token");
		await state.updateGithubToken(undefined);
	} else {
		log.info("Storing new github token");
		await state.updateGithubToken(newToken);
	}
}

export function deactivate(): Thenable<void> {
	return ctx!.client.stop();
}
