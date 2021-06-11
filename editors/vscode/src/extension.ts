/*
    HIGHLY inspired by the wonderful rust-analyzer, and contains modification of code from rust-analyzer vscode extension.
*/

import * as vscode from 'vscode';
import * as path from "path";
import * as os from "os";
import { promises as fs, PathLike, constants, writeFileSync } from "fs";

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
import { getPathForExecutable, isOdinInstalled } from './toolchain';
import { Ctx } from './ctx';
import { runDebugTest, runTest } from './commands';
import { watchOlsConfigFile } from './watch';

const onDidChange: vscode.EventEmitter<void> = new vscode.EventEmitter<void>();

let ctx: Ctx;

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

    let clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'odin' }],
        outputChannel: vscode.window.createOutputChannel("Odin Language Server")
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

    const olsFile = path.join(workspaceFolder.uri.fsPath, "ols.json");
    
    fs.access(olsFile, constants.F_OK).catch(async err => {
        if (err) {

            const userResponse = await vscode.window.showInformationMessage(
                "No ols config file in the workspace root folder. Do you wish to create one?",
                "Yes",
                "No"
            );

            if (userResponse === "Yes") {
                createOlsConfig(ctx);
            }

        }

        parseOlsFile(config, olsFile);
    });

    if(!isOdinInstalled()) {
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

    client.start();

    parseOlsFile(config, olsFile);
    watchOlsConfigFile(ctx, olsFile);
}

async function bootstrap(config: Config, state: PersistentState): Promise<string> {
    await fs.mkdir(config.globalStorageUri.fsPath, { recursive: true });

    const path = await bootstrapServer(config, state);

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

export function createOlsConfig(ctx: Ctx) {
    const odinPath = getPathForExecutable("odin");

    const corePath = path.resolve(path.join(path.dirname(odinPath), "core"));

    const config = {
        collections: [{ name: "core", path: corePath }],
        enable_document_symbols: true,
        enable_semantic_tokens: false,
        enable_hover: true
    };

    const olsPath = vscode.workspace.workspaceFolders![0].uri.fsPath;

    const edit = new vscode.WorkspaceEdit();

    const content = JSON.stringify(config, null, 4);

    writeFileSync(path.join(olsPath, "ols.json"), content);
}

export async function parseOlsFile(config: Config, file: string) {
    /*
        We have to parse the collections that they have specificed through the json(This will be changed when odin gets it's own builder files)
    */
    fs.readFile(file).then((data) => {
        const conf = JSON.parse(data.toString());
        config.collections = conf.collections;
    },
    (rejected) => {
        log.error("failed to read ols file: ", rejected);
    });
} 

function serverPath(config: Config): string | null {
    return config.serverPath;
}

async function getServer(config: Config, state: PersistentState): Promise<string | undefined> {
    const explicitPath = serverPath(config);
    if (explicitPath) {
        if (explicitPath.startsWith("~/")) {
            return os.homedir() + explicitPath.slice("~".length);
        }
        return explicitPath;
    };

    const platforms: { [key: string]: string } = {
        "x64 win32": "x86_64-pc-windows-msvc",
        "x64 linux": "x86_64-unknown-linux-gnu",
        "x64 darwin": "x86_64-darwin",
    };

    let platform = platforms[`${process.arch} ${process.platform}`];

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

    const ext = platform.indexOf("-windows-") !== -1 ? ".exe" : "";
    const destFolder = config.globalStorageUri.fsPath;
    const destExecutable = path.join(destFolder, `ols-${platform}${ext}`);
    
    const exists = await fs.stat(destExecutable).then(() => true, () => false);

    if (!exists) {
        await state.updateReleaseId(0);
    }

    /*
        Temp: right now it doesn't check for versions, since ols has no versioning right now
    */
    
    if (exists && state.lastCheck !== undefined && state.lastCheck + (3 * 60 * 60 * 1000)  > Date.now()) {
        return destExecutable;
    }

    const release = await downloadWithRetryDialog(state, async () => {
        return await fetchRelease("nightly", state.githubToken, config.httpProxy);
    });

    if (release === undefined || release.id === state.releaseId) {
        await state.updateLastCheck(Date.now());
        return destExecutable;
    }

    const userResponse = await vscode.window.showInformationMessage(
        "New version of ols (nightly) is available (requires reload).",
        "Update"
    );

    if (userResponse !== "Update") {
        return destExecutable;
    }

    const artifact = release.assets.find(artifact => artifact.name === `ols-${platform}.zip`);
    assert(!!artifact, `Bad release: ${JSON.stringify(release)}`);
    
    const destZip = path.join(destFolder, `ols-${platform}.zip`);

    await downloadWithRetryDialog(state, async () => {
        await download({
            url: artifact.browser_download_url,
            dest: destZip,
            progressTitle: "Downloading ols",
            mode: 0o755,
            httpProxy: config.httpProxy,
        });
    });

    var zip = new AdmZip(destZip);

    zip.extractAllTo(destFolder, true);

    await state.updateServerVersion(config.package.version);
    await state.updateReleaseId(release.id);
    await state.updateLastCheck(Date.now());
    await vscode.commands.executeCommand("workbench.action.reloadWindow");

    return destExecutable;
}

async function downloadWithRetryDialog<T>(state: PersistentState, downloadFunc: () => Promise<T>): Promise<T> {
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
