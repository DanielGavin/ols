import * as vscode from 'vscode';
import { log } from "./util";

export class Config {

	readonly extensionId = "danielgavin.ols";
	readonly rootSection = "ols";

	readonly globalStorageUri: vscode.Uri;

	readonly package: {
		version: string;
		releaseTag: string | null;
		enableProposedApi: boolean | undefined;
	} = vscode.extensions.getExtension(this.extensionId)!.packageJSON;

	constructor(ctx: vscode.ExtensionContext) {
		this.globalStorageUri = ctx.globalStorageUri;
	}

	private get cfg(): vscode.WorkspaceConfiguration {
		return vscode.workspace.getConfiguration(this.rootSection);
	}

	get serverPath() {
		return this.get<null | string>("server.path") ?? this.get<null | string>("serverPath");
	}

	get httpProxy() {
		const httpProxy = vscode
			.workspace
			.getConfiguration('http')
			.get<null | string>("proxy")!;

		return httpProxy || process.env["https_proxy"] || process.env["HTTPS_PROXY"];
	}

	private get<T>(path: string): T {
		return this.cfg.get<T>(path)!;
	}

	get askBeforeDownload() { return this.get<boolean>("updates.askBeforeDownload"); }

	get debugEngine() { return this.get<string>("debug.engine"); }

    get askCreateOLS() {  return this.get<boolean>("prompt.AskCreateOLS"); }

	public updateAskCreateOLS(ask: boolean) {
		this.cfg.update("prompt.AskCreateOLS", ask, vscode.ConfigurationTarget.Global);
	}

	collections: any[] = [];
	odinCommand: string = null;
}
