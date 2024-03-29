import * as vscode from 'vscode';
import { log } from './util';

//modified from https://github.com/rust-analyzer/rust-analyzer/blob/master/editors/code/src/persistent_state.ts - 03.05.2021

export class PersistentState {
    constructor(private readonly globalState: vscode.Memento) {
        const { lastCheck, releaseId, serverVersion } = this;
        log.info("PersistentState:", { lastCheck, releaseId, serverVersion });
    }

    /**
     * Used to check for *nightly* updates once an hour.
     */
    get lastCheck(): number | undefined {
        return this.globalState.get("lastCheck");
    }
    async updateLastCheck(value: number) {
        await this.globalState.update("lastCheck", value);
    }

    /**
     * Release id of the *nightly* extension.
     * Used to check if we should update.
     */
    get releaseId(): number | undefined {
        return this.globalState.get("releaseId");
    }
    async updateReleaseId(value: number) {
        await this.globalState.update("releaseId", value);
    }

    /**
     * Version of the extension that installed the server.
     * Used to check if we need to update the server.
     */
    get serverVersion(): string | undefined {
        return this.globalState.get("serverVersion");
    }
    async updateServerVersion(value: string | undefined) {
        await this.globalState.update("serverVersion", value);
    }

    /**
     * Github authorization token.
     * This is used for API requests against the Github API.
     */
    get githubToken(): string | undefined {
        return this.globalState.get("githubToken");
    }
    async updateGithubToken(value: string | undefined) {
        await this.globalState.update("githubToken", value);
    }
}