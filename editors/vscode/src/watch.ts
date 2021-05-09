import * as vscode from "vscode";

export function watchOlsConfigFile() 
{
    var olsWatcher = vscode.workspace.createFileSystemWatcher("ols.json");

    olsWatcher.onDidCreate((uri) => {

    });



}