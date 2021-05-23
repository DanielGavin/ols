import * as vscode from 'vscode';
import * as lc from 'vscode-languageclient';

import { Ctx, Cmd } from './ctx';
import { execFile, spawnSync } from 'child_process';
import { LanguageClient } from 'vscode-languageclient/node';
import path = require('path');
import { getDebugConfiguration } from './debug';
import { getPathForExecutable } from './toolchain';
import { promises as fs, PathLike, constants, writeFileSync} from "fs";

export function runDebugTest(ctx: Ctx): Cmd {
    return async(debugConfig: any) => {

        const fn = debugConfig.function;
        const cwd = debugConfig.cwd;
        const pkg = path.basename(cwd);

        var args = [];

        args.push("test");
        args.push(cwd);
        args.push(`-test-name:${fn}`);
        args.push("-debug");

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

            vscode.debug.startDebugging(undefined, getDebugConfiguration(ctx.config, executableName)).then(r => console.log("Result", r));
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
        args.push(`-test-name:${fn}`);

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