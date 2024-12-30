"use strict";

import { runInNewContext } from "vm";
import * as path from "path";

/*
	Modified code from https://github.com/hdevalke/rust-test-lens/
*/

import {
	CancellationToken,
	CodeLens,
	CodeLensProvider,
	Event,
	EventEmitter,
	Range,
	TextDocument,
	DebugConfiguration,
} from "vscode";

/*
	This is not good enough. I think I have to let the language server make the lenses. Also I can't tell when the debug button is pressed, so users can end up pressing the button multiple times.
	
	Would also be neat to see how many tests have failed since last, and also press a button to run all tests in the workspace.
*/

export class RunnableCodeLensProvider implements CodeLensProvider {
	constructor(private _onDidChange: EventEmitter<void>) { }

	public async provideCodeLenses(
		doc: TextDocument,
		token: CancellationToken
	): Promise<CodeLens[]> {

		if (token.isCancellationRequested) {
			return [];
		}

		let lenses: CodeLens[] = this.testMethodLenses(doc);

		return lenses;
	}

	get onDidChangeCodeLenses(): Event<void> {
		return this._onDidChange.event;
	}

	public updateArgs() {

	}

	private testMethodLenses(doc: TextDocument) {
		const text = doc.getText();
		const reTest = /\@\(?test\)?/g;
		const reFnTest = /\s*\w+\s*::\s*proc\s*\s*\(/g;
		const rePackageName = /package\s+\w+/g;

		var testMatch: RegExpExecArray | null = null;

		let lenses: CodeLens[] = [];
		while ((testMatch = reTest.exec(text)) !== null) {

			reFnTest.lastIndex = reTest.lastIndex;
			const fnMatch = reFnTest.exec(text);

			if (fnMatch === null) {
				continue;
			}

			const pkgMatch = rePackageName.exec(text);

			if (pkgMatch === null) {
				continue;
			}

			const fn = fnMatch[0].split(":")[0];
			const pkg = pkgMatch[0].split(" ")[1];

			if (fn && fn[0]) {

				const debugCodelens = this.makeDebugLens(reTest.lastIndex, testMatch[0].length, pkg, fn.trim(), doc);

				if (debugCodelens !== undefined) {
					lenses.push(debugCodelens);
				}

				const runCodelens = this.makeRunLens(reTest.lastIndex, testMatch[0].length, pkg, fn.trim(), doc);

				if (runCodelens !== undefined) {
					lenses.push(runCodelens);
				}

			}

		}

		return lenses;
	}

	private makeDebugLens(index: number, length: number, pkg:string, fn: string, doc: TextDocument) {
		const startIdx = index - length;
		const start = doc.positionAt(startIdx);
		const end = doc.positionAt(index);
		const range = new Range(start, end);
	
		return new CodeLens(range, {
			title: "Debug",
			command: "ols.runDebugTest",
			tooltip: "Debug",
			arguments: [{
				function: fn,
				cwd: path.dirname(doc.uri.fsPath),
				pkg: pkg
			}]
		});
		
	}

	private makeRunLens(index: number, length: number, pkg: string, fn: string, doc: TextDocument): any | undefined {
		const startIdx = index - length;
		const start = doc.positionAt(startIdx);
		const end = doc.positionAt(index);
		const range = new Range(start, end);

		return new CodeLens(range, {
			title: "Run",
			command: "ols.runTest",
			tooltip: "Run",
			arguments: [{
				function: fn,
				cwd: path.dirname(doc.uri.fsPath),
				pkg: pkg
			}]
		});
	}
}
