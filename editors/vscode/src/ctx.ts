import * as vscode from 'vscode';
import * as lc from 'vscode-languageclient/node';

import { Config } from './config';
import { isOdinEditor, OdinEditor } from './util';

//modified from https://github.com/rust-analyzer/rust-analyzer/blob/master/editors/code/src/ctx.ts - 09.05.2021

export class Ctx {
    private constructor(
        readonly config: Config,
        private readonly extCtx: vscode.ExtensionContext,
        readonly client: lc.LanguageClient,
        readonly serverPath: string,
    ) {

    }

    static async create(
        config: Config,
        client: lc.LanguageClient,
        extCtx: vscode.ExtensionContext,
        serverPath: string,
        cwd: string,
    ): Promise<Ctx> {
        const res = new Ctx(config, extCtx, client, serverPath);

        return res;
    }

    get activeOdinEditor(): OdinEditor | undefined {
        const editor = vscode.window.activeTextEditor;
        return editor && isOdinEditor(editor)
            ? editor
            : undefined;
    }

    get visibleOdinEditors(): OdinEditor[] {
        return vscode.window.visibleTextEditors.filter(isOdinEditor);
    }

    registerCommand(name: string, factory: (ctx: Ctx) => Cmd) {
        const fullName = `ols.${name}`;
        const cmd = factory(this);
        const d = vscode.commands.registerCommand(fullName, cmd);
        this.pushCleanup(d);
    }

    get globalState(): vscode.Memento {
        return this.extCtx.globalState;
    }

    get subscriptions(): Disposable[] {
        return this.extCtx.subscriptions;
    }

    isOdinDocument(document: vscode.TextDocument): number {
        return vscode.languages.match({scheme: 'file', language: 'odin'}, document);
    } 

    pushCleanup(d: Disposable) {
        this.extCtx.subscriptions.push(d);
    }
}

export interface Disposable {
    dispose(): void;
}
export type Cmd = (...args: any[]) => unknown;