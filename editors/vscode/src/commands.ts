import * as vscode from 'vscode';

import { Ctx, Cmd } from './ctx';
import { execFile } from 'child_process';
import path = require('path');
import { promises as fs } from "fs";
import { getDebugConfiguration } from './debug';
import { getExt } from './extension';

export function runDebugTest(ctx: Ctx): Cmd {
    return async(debugConfig: any) => {
        const workspaceFolder = vscode.workspace.workspaceFolders?.[0].uri.fsPath;

        if(workspaceFolder === undefined) {
            return;
        }

        const fn = debugConfig.function;
        const cwd = debugConfig.cwd;
        const pkg = path.basename(cwd);

        const args : string[] = [];

        args.push("build");
        args.push(cwd);
        args.push("-build-mode:test")
        args.push(`-define:ODIN_TEST_NAMES=${pkg}.${fn}`);
        args.push("-debug");
        const testExectuablePath = path.join(cwd, `${pkg}${getExt()}`);
        args.push(`-out:${testExectuablePath}`)

        for(var i = 0; i < ctx.config.collections.length; i++) {
            const name = ctx.config.collections[i].name;
            const path = ctx.config.collections[i].path;
            if(name === "core" || name === "vendor") {
                continue;
            }
            args.push(`-collection:${name}=${path}`);
        }
     
        const odinBuildTestPromise = new Promise((resolve, reject) => {
            execFile("odin", args, {cwd : workspaceFolder}, (err, stdout, stderr) => {
                if (err) {
                    console.error(stderr);
                    reject(err)
                }

                return resolve({ stdout });
            });
        });

        await odinBuildTestPromise;

        const execExists = await new Promise<boolean>((resolve) => {
            fs.stat(testExectuablePath).then((stats) => {
                resolve(true);
            }).catch(() => resolve(false));
        });

        if (!execExists) {
            throw Error("Expect test executable to be present: " + testExectuablePath);
        }

        vscode.debug
            .startDebugging(cwd, getDebugConfiguration(ctx.config, testExectuablePath)).then(r => console.log("Result", r));
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