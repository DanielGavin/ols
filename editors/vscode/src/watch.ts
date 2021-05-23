import * as vscode from "vscode";
import { Ctx } from "./ctx";
import { parseOlsFile } from "./extension";
import { log } from "./util";

export function watchOlsConfigFile(ctx: Ctx, olsFile: string) 
{
    var olsWatcher = vscode.workspace.createFileSystemWatcher(olsFile);

    olsWatcher.onDidCreate(async (uri) => {
        log.info("ols.json modified - restarting client");
        await parseOlsFile(ctx.config, uri.fsPath);
        vscode.commands.executeCommand("ols.restart");
    });

    olsWatcher.onDidChange(async (uri) => {
        log.info("ols.json modified - restarting client");
        await parseOlsFile(ctx.config, uri.fsPath);
        vscode.commands.executeCommand("ols.restart");
    });

}
