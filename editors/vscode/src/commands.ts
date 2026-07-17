import * as vscode from 'vscode';

import { Ctx, Cmd } from './ctx';
import { execFile } from 'child_process';
import path = require('path');
import { promises as fs } from "fs";
import { getDebugConfiguration } from './debug';
import { getExt } from './extension';
import { log } from './util';

export function runDebugTest(ctx: Ctx): Cmd {
    return async (debugConfig: any) => {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0].uri.fsPath;

        if (workspaceFolder === undefined) {
            return;
        }

        const fn = debugConfig.function;
        const cwd = debugConfig.cwd;
        const pkg = path.basename(cwd);

        const args: string[] = [];

        const testName = `${pkg}.${fn}`;

        args.push("build");
        args.push(cwd);
        args.push("-build-mode:test")
        args.push(`-define:ODIN_TEST_NAMES=${testName}`);
        args.push("-debug");
        const testExectuablePath = path.join(cwd, `${pkg}${getExt()}`);
        args.push(`-out:${testExectuablePath}`)

        for (var i = 0; i < ctx.config.collections.length; i++) {
            const name = ctx.config.collections[i].name;
            const path = ctx.config.collections[i].path;
            if (name === "core" || name === "vendor") {
                continue;
            }
            args.push(`-collection:${name}=${path}`);
        }

        await vscode.window.withProgress({
            title: `Debugging ${testName}`,
            cancellable: true,
            location: vscode.ProgressLocation.Notification
        }, async (progress, token) => {
            progress.report({ message: `Buidling ${testExectuablePath}` });

            await new Promise((resolve, reject) => {
                const odinProcess = execFile("odin", args, { cwd: workspaceFolder }, (err, stdout, stderr) => {
                    if (err) {
                        log.error("odin build failed:", stderr);
                        return reject(new Error("Failed to build executable"));
                    }

                    log.info(stdout);
                    return resolve(true);
                });

                token.onCancellationRequested(() => {
                    progress.report({ message: "Cancelling build..." });
                    odinProcess.kill();
                    reject(new Error("Debug Cancelled"));
                });
            });

            progress.report({ message: "Checking exectuable is there" });

            const execExists = await new Promise<boolean>((resolve) => {
                fs.stat(testExectuablePath).then((stats) => {
                    resolve(true);
                }).catch(() => resolve(false));
            });

            if (!execExists) {
                throw Error("Expected test executable to be present: " + testExectuablePath);
            }

            progress.report({ message: "Start debugging..." });

            return await vscode.debug
                .startDebugging(cwd, getDebugConfiguration(ctx.config, testExectuablePath)).then(r => console.log("Result", r));
        });
    };
}

export function runTest(ctx: Ctx): Cmd {

    return async(debugConfig: any) => {
        const fn = debugConfig.function;
        const cwd = debugConfig.cwd;
        const pkg = path.basename(cwd);

        var args = [];

        args.push("test");
        args.push(cwd);
        args.push(`-define:ODIN_TEST_NAMES=${pkg}.${fn}`);

        for(var i = 0; i < ctx.config.collections.length; i++) {
            const name = ctx.config.collections[i].name;
            const path = ctx.config.collections[i].path;
            if(name === "core") {
                continue;
            }
            args.push(`-collection:${name}=${path}`);
        }

        const workspaceFolder = vscode.workspace.workspaceFolders?.[0].uri.fsPath;

        if(workspaceFolder === undefined) {
            return;
        }

        var definition = {
            type: "shell",
            command: "run", 
            args: args,
            cwd: workspaceFolder,
        };

        const shellExec = new vscode.ShellExecution("odin", args, { cwd: workspaceFolder});
 
        const target = vscode.workspace.workspaceFolders![0];
        var task = new vscode.Task(definition, target, "Run Test", "odin", shellExec);

        vscode.tasks.executeTask(task);
    };
}