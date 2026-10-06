const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');

const stateDir = path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'SessionRestore');
const pendingPath = path.join(stateDir, 'editor-pending.json');
const claimDir = path.join(stateDir, 'claimed');

function normalize(folder) {
    return path.resolve(folder).replace(/[\\/]+$/, '').toLowerCase();
}

function currentEditor() {
    return vscode.env.appName.toLowerCase().includes('codium') ? 'VSCodium.exe' : 'Code.exe';
}

function readPending() {
    try {
        const text = fs.readFileSync(pendingPath, 'utf8').replace(/^﻿/, '');
        const parsed = JSON.parse(text);
        return Array.isArray(parsed.Sessions) ? parsed.Sessions : [parsed.Sessions].filter(Boolean);
    } catch {
        return [];
    }
}

function claim(sessionId) {
    try {
        fs.mkdirSync(claimDir, { recursive: true });
        fs.closeSync(fs.openSync(path.join(claimDir, sessionId), 'wx'));
        return true;
    } catch {
        return false;
    }
}

function quote(text) {
    return "'" + String(text).replace(/'/g, "''") + "'";
}

function openSession(session) {
    const terminal = vscode.window.createTerminal({
        name: session.Label,
        cwd: session.Cwd,
        shellPath: session.ShellPath || undefined,
    });
    const claude = session.ClaudePath ? '& ' + quote(session.ClaudePath) : 'claude';
    terminal.sendText(`${claude} --resume ${session.SessionId}`);
    terminal.show(true);
}

function activate() {
    const folders = (vscode.workspace.workspaceFolders || []).map((folder) => normalize(folder.uri.fsPath));
    if (folders.length === 0) {
        return;
    }
    const editor = currentEditor();
    for (const session of readPending()) {
        if (session.Editor !== editor || !folders.includes(normalize(session.Cwd))) {
            continue;
        }
        if (claim(session.SessionId)) {
            openSession(session);
        }
    }
}

function deactivate() {}

module.exports = { activate, deactivate };
