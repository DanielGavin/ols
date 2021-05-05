/*
    HIGHLY inspired by the wonderful rust-analyzer, and contains modification of code from rust-analyzer vscode extension.
*/

import * as vscode from 'vscode';
import * as path from "path";
import * as os from "os";
import { promises as fs, PathLike, constants } from "fs";
import { execFile } from 'child_process';
import { trace } from 'console';

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
import { getDebugConfiguration } from './debug';
import { isOdinInstalled } from './toolchain';


const onDidChange: vscode.EventEmitter<void> = new vscode.EventEmitter<void>();

let client: LanguageClient;

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

    const olsFile = path.join(workspaceFolder.uri.fsPath, "ols.json");

    fs.access(olsFile, constants.F_OK).catch(err => {
        if (err) {
            vscode.window.showErrorMessage("No ols.json in the workspace root folder. [Config](https://github.com/DanielGavin/ols/#Configuration).");
        }
    });

    if(!isOdinInstalled()) {
        vscode.window.showErrorMessage("Odin cannot be found in your path environment. Please install Odin or add it into your path environment before going any further: [Install](https://odin-lang.org/docs/install/).");
    }

    parseOlsFile(config, olsFile);

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

    client = new LanguageClient(
        'odinLanguageClient',
        'Odin Language Server Client',
        serverOptions,
        clientOptions
    );

    client.start();

    //Move commands to somewhere else(probably do it like rust-analyzer does it)
    vscode.commands.registerCommand("extension.debug", debugConfig => {
        const fn = debugConfig.function;
        const cwd = debugConfig.cwd;
        const pkg = path.basename(cwd);

        var args = [];

        args.push("test");
        args.push(cwd);
        args.push(`-test-name:${fn}`);
        args.push("-debug");

        for(var i = 0; i < config.collections.length; i++) {
            const name = config.collections[i].name;
            const path = config.collections[i].path;
            if(name === "core") {
                continue;
            }
            args.push(`-collection:${name}=${path}`);
        }

        const workspaceFolder = vscode.workspace.workspaceFolders?.[0].uri.fsPath;

        if(workspaceFolder === undefined) {
            return;
        }

        const odinExecution = execFile("odin", args, {cwd : workspaceFolder}, (err, stdout, stderr) => {
            if (err) {
                vscode.window.showErrorMessage(err.message);
            }
        });
 
        const executableName = path.join(workspaceFolder, pkg);

        odinExecution.on("exit", (code) => {

            if(code !== 0) {
                throw Error("Odin test failed!");
            }

            vscode.debug.startDebugging(undefined, getDebugConfiguration(config, executableName)).then(r => console.log("Result", r));
        });

    });

    vscode.commands.registerCommand("extension.run", debugConfig => {
        const fn = debugConfig.function;
        const cwd = debugConfig.cwd;
        const pkg = path.basename(cwd);

        var args = [];

        args.push("test");
        args.push(cwd);
        args.push(`-test-name:${fn}`);

        for(var i = 0; i < config.collections.length; i++) {
            const name = config.collections[i].name;
            const path = config.collections[i].path;
            if(name === "core") {
                continue;
            }
            args.push(`-collection:${name}=${path}`);
        }

        const workspaceFolder = vscode.workspace.workspaceFolders?.[0].uri.fsPath;

        if(workspaceFolder === undefined) {
            return;
        }

        const odinExecution = execFile("odin", args, {cwd : workspaceFolder}, (err, stdout, stderr) => {
            if (err) {
                vscode.window.showErrorMessage(err.message);
            }
        });
 
        odinExecution.stdout?.on("data", (data) => {
            console.log(data);
        });
   
        odinExecution.on("exit", (code) => {
            if(code !== 0) {
                throw Error("Odin test failed!");
            }   
        });

    });


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

async function parseOlsFile(config: Config, file: string) {
    /*
        We have to parse the collections that they have specificed through the json(This will be changed when odin gets it's own builder files)
    */
    fs.readFile(file).then((data) => {
        const conf = JSON.parse(data.toString());
        config.collections = conf.collections;
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
        //"x64 linux": "x86_64-unknown-linux-gnu",
        //"x64 darwin": "x86_64-apple-darwin",
        //"arm64 win32": "aarch64-pc-windows-msvc",
        //"arm64 linux": "aarch64-unknown-linux-gnu",
        //"arm64 darwin": "aarch64-apple-darwin",
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
    return client.stop();
}
