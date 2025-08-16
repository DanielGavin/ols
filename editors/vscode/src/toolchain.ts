import * as os from "os";
import * as path from "path";
import * as fs from "fs";

import { memoize } from './util';
import { Config } from "./config";

export function isOdinInstalled(config: Config): boolean {
	if (config.odinCommand) {
		return true
	}
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

	for (let i = 0; i < candidates.length; i += 1) {
		try {
			const pathToOdin = fs.realpathSync(candidates[i]);
			if (!!pathToOdin) {
				return pathToOdin;
			}
		} catch (realpathError) {
			console.debug("couldn't find odin at", candidates[i], "on account of", realpathError)
		}
	}

	return undefined;
}
