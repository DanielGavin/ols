import * as vscode from "vscode";
import * as os from "os";
import * as path from "path";
import * as fs from "fs";

import { execute, log, memoize } from './util';

export function isOdinInstalled(): boolean {
	return getPathForExecutable("odin") !== "";
}

export const getPathForExecutable = memoize(
    // We apply caching to decrease file-system interactions
    (executableName: "odin"): string => {
        {
            const envVar = process.env[executableName.toUpperCase()];
            if (envVar) {
				return envVar;
			}
        }

        const path = lookupInPath(executableName);
        if (path != undefined) {
			return path;
		}

        return "";
    }
);

function lookupInPath(exec: string): string | undefined {
    const paths = process.env.PATH ?? "";

    const candidates = paths.split(path.delimiter).flatMap(dirInPath => {
        const candidate = path.join(dirInPath, exec);
        return os.type() === "Windows_NT"
            ? [candidate, `${candidate}.exe`]
            : [candidate];
    });

    for (var i = 0; i < candidates.length; i += 1) {
        if (isFile(candidates[i])) {
            return candidates[i];
        }
    }

    return undefined;
}

function isFile(suspectPath: string): boolean {
    // It is not mentionned in docs, but `statSync()` throws an error when
    // the path doesn't exist
    try {
        return fs.statSync(suspectPath).isFile();
    } catch {
        return false;
    }
}