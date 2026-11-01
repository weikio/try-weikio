#!/usr/bin/env node
// Forwards port 8580 on this machine to the admin UI and the API in the running Try Weik.io container, for a person who
// starts the container with the devcontainer command line. An editor forwards the port by itself. Run it on your machine,
// in the folder you started the container from, and leave it running:
//
//   node .devcontainer/forward-admin-ui.js
'use strict';

const { execFileSync, spawn } = require('node:child_process');
const net = require('node:net');
const path = require('node:path');

const PORT = 8580;

function fail(message) {
    console.error(`error: ${message}`);
    process.exit(1);
}

// A devcontainer labels its container with the folder it was started from.
function containerOf(folder) {
    let lines;
    try {
        lines = execFileSync('docker', ['ps', '--format', '{{.ID}} {{.Label "devcontainer.local_folder"}}'], { encoding: 'utf8' });
    } catch {
        fail('Docker did not answer. Start Docker and run this again.');
    }
    const wanted = folder.toLowerCase();
    for (const line of lines.split('\n')) {
        const space = line.indexOf(' ');
        if (space > 0 && line.slice(space + 1).trim().toLowerCase() === wanted) {
            return line.slice(0, space);
        }
    }
    fail(`No running container was started from ${folder}. Start it with: devcontainer up --workspace-folder .`);
}

const container = containerOf(path.resolve('.'));

const server = net.createServer((connection) => {
    const pipe = spawn('docker', ['exec', '-i', '-u', 'weikio', container, 'socat', 'STDIO', `TCP:127.0.0.1:${PORT}`], {
        stdio: ['pipe', 'pipe', 'ignore'],
    });
    connection.pipe(pipe.stdin);
    pipe.stdout.pipe(connection);
    connection.on('error', () => pipe.kill());
    connection.on('close', () => pipe.kill());
    pipe.stdin.on('error', () => connection.destroy());
    pipe.on('error', () => connection.destroy());
    pipe.on('exit', () => connection.end());
});

server.on('error', (error) => {
    if (error.code === 'EADDRINUSE') {
        fail(`Something else uses port ${PORT} on this machine. Stop it and run this again.`);
    }
    fail(error.message);
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`The admin UI is at http://localhost:${PORT}. Ctrl-C stops forwarding, and the container keeps running.`);
});
