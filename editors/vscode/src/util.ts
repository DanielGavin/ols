import * as lc from "vscode-languageclient/node";
import * as vscode from "vscode";
import { strict as nativeAssert } from "assert";
import { exec, ExecOptions, spawnSync } from "child_process";
import { inspect } from "util";

//modified from https://github.com/rust-analyzer/rust-analyzer/blob/master/editors/code/src/util.ts - 03.05.2021

export function assert(condition: boolean, explanation: string): asserts condition {
    try {
        nativeAssert(condition, explanation);
    } catch (err) {
        log.error(`Assertion failed:`, explanation);
        throw err;
    }
}

export const log = new class {
    private enabled = true;
    private readonly output = vscode.window.createOutputChannel("Odin Language Client");

    setEnabled(yes: boolean): void {
        log.enabled = yes;
    }

    // Hint: the type [T, ...T[]] means a non-empty array
    debug(...msg: [unknown, ...unknown[]]): void {
        if (!log.enabled) {
            return; 
        }
        log.write("DEBUG", ...msg);
    }

    info(...msg: [unknown, ...unknown[]]): void {
        log.write("INFO", ...msg);
    }

    warn(...msg: [unknown, ...unknown[]]): void {
        debugger;
        log.write("WARN", ...msg);
    }

    error(...msg: [unknown, ...unknown[]]): void {
        debugger;
        log.write("ERROR", ...msg);
        log.output.show(true);
    }

    private write(label: string, ...messageParts: unknown[]): void {
        const message = messageParts.map(log.stringify).join(" ");
        const dateTime = new Date().toLocaleString();
        log.output.appendLine(`${label} [${dateTime}]: ${message}`);
    }

    private stringify(val: unknown): string {
        if (typeof val === "string") {
            return val;
        }
        return inspect(val, {
            colors: false,
            depth: 6, // heuristic
        });
    }
};

export async function sendRequestWithRetry<TParam, TRet>(
    client: lc.LanguageClient,
    reqType: lc.RequestType<TParam, TRet, unknown>,
    param: TParam,
    token?: vscode.CancellationToken,
): Promise<TRet> {
    // The sequence is `10 * (2 ** (2 * n))` where n is 1, 2, 3...
    for (const delay of [40, 160, 640, 2560, 10240, null]) {
        try {
            return await (token
                ? client.sendRequest(reqType, param, token)
                : client.sendRequest(reqType, param)
            );
        } catch (error) {
            if (delay === null) {
                log.warn("LSP request timed out", { method: reqType.method, param, error });
                throw error;
            }
            if (error.code === lc.LSPErrorCodes.RequestCancelled) {
                throw error;
            }

            if (error.code !== lc.LSPErrorCodes.ContentModified) {
                log.warn("LSP request failed", { method: reqType.method, param, error });
                throw error;
            }
            await sleep(delay);
        }
    }
    throw 'unreachable';
}

export function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

export type OdinDocument = vscode.TextDocument & { languageId: "odin" };
export type OdinEditor = vscode.TextEditor & { document: OdinDocument };

export function isOdinDocument(document: vscode.TextDocument): document is OdinDocument {
    return document.languageId === 'odin' && document.uri.scheme === 'file';
}

export function isOdinEditor(editor: vscode.TextEditor): editor is OdinEditor {
    return isOdinDocument(editor.document);
}

export function isValidExecutable(path: string): boolean {
    log.debug("Checking availability of a binary at", path);

    const res = spawnSync(path, ["--version"], { encoding: 'utf8' });

    const printOutput = res.error && (res.error as any).code !== 'ENOENT' ? log.warn : log.debug;
    printOutput(path, "--version:", res);

    return res.status === 0;
}

/** Sets ['when'](https://code.visualstudio.com/docs/getstarted/keybindings#_when-clause-contexts) clause contexts */
export function setContextValue(key: string, value: any): Thenable<void> {
    return vscode.commands.executeCommand('setContext', key, value);
}

/**
 * Returns a higher-order function that caches the results of invoking the
 * underlying function.
 */
export function memoize<Ret, TThis, Param extends string>(func: (this: TThis, arg: Param) => Ret) {
    const cache = new Map<string, Ret>();

    return function(this: TThis, arg: Param) {
        const cached = cache.get(arg);
        if (cached) {
            return cached;
        }

        const result = func.call(this, arg);
        cache.set(arg, result);

        return result;
    };
}

/** Awaitable wrapper around `child_process.exec` */
export function execute(command: string, options: ExecOptions): Promise<string> {
    return new Promise((resolve, reject) => {
        exec(command, options, (err, stdout, stderr) => {
            if (err) {
                reject(err);
                return;
            }

            if (stderr) {
                reject(new Error(stderr.toString()));
                return;
            }
 
            resolve(stdout.toString().trimEnd());
        });
    });
}