import * as vscode from 'vscode';

import * as os from "os";
import { Config } from './config';

type DebugConfigProvider = (executable: string) => vscode.DebugConfiguration;

export function getDebugConfiguration(config: Config, program: string): any {

	const knownEngines: Record<string, DebugConfigProvider> = {
        "vadimcn.vscode-lldb": getLldbDebugConfig,
        "ms-vscode.cpptools": getCppvsDebugConfig
    };

	var debugEngine = null;

    if(config.debugEngine !== "") {
        debugEngine = vscode.extensions.getExtension(config.debugEngine);
    } 

    if(debugEngine === null || debugEngine === undefined) {
        for (var engineId in knownEngines) {
            debugEngine = vscode.extensions.getExtension(engineId);
            if (debugEngine) {
                break;
            } 
        }
    }

	if (!debugEngine) {
        vscode.window.showErrorMessage(`Install [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb)`
		+ ` or [MS C++ tools](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools) extension for debugging.`);
        return;
    }

	return knownEngines[debugEngine.id](program);
}

function getLldbDebugConfig(executable: string): vscode.DebugConfiguration {
    return {
        type: "lldb",
        request: "launch",
        name: "test debug",
        program: executable,
        cwd: vscode.workspace.workspaceFolders?.[0].uri.fsPath
    };
}

function getCppvsDebugConfig(executable: string): vscode.DebugConfiguration {
    return {
        type: (os.platform() === "win32") ? "cppvsdbg" : "cppdbg",
        request: "launch",
        name: "test debug",
        program: executable,
        cwd: vscode.workspace.workspaceFolders?.[0].uri.fsPath
    };
}