#!/usr/bin/env node
import {openLocalExplorer} from './launcher.mjs';
import {explorerArguments, explorerLaunchInput} from './cli-input.mjs';

const help = `Usage: actql-explorer --local [--state-dir <directory>]\n       [--program <file> [--format sql|aql|aql-text|program] | --run <reference.json>]\n\nOpens one existing ActQL Local Host and the built read-only Explorer.\nProgram input reads a static Plan only; it never starts a Run.\nRun input reads the saved original Run Plan, with no compile fallback.\nTo borrow an already connected Client, use @actql/explorer/launcher.\nPaste the printed one-use bootstrap into the page within 60 seconds.\nClosing the viewer does not cancel a Run. No Vite server is required.\n`;
const args = process.argv.slice(2);
try {
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
    process.stdout.write(help);
  } else {
    const selected = explorerArguments(args);
    const launchInput = await explorerLaunchInput(selected);
    const gateway = await openLocalExplorer({local: selected.local, launchInput});
    const issued = gateway.issueBootstrap();
    process.stdout.write(`Explorer: ${issued.origin}\nOne-use bootstrap: ${issued.bootstrap}\n`);
    // Explicit operator input can renew presentation; it never renews Host authority.
    process.stdout.write('Press Enter for a new bootstrap; Ctrl+C closes the viewer.\n');
    process.stdin.setEncoding('utf8');
    const renew = () => {
      const next = gateway.issueBootstrap();
      process.stdout.write(`One-use bootstrap: ${next.bootstrap}\n`);
    };
    process.stdin.on('data', renew);
    let closing = false;
    const close = async () => {
      if (closing) return;
      closing = true;
      process.stdin.removeListener('data', renew);
      try {await gateway.close(); process.stdin.destroy();}
      catch {closing = false; process.stderr.write('ExplorerLocalCleanupPending: retry Ctrl+C.\n'); process.exitCode = 1;}
    };
    process.on('SIGINT', close); process.on('SIGTERM', close);
  }
} catch (error) {
  // Do not print caller strings, Host responses, paths, tokens or stack traces.
  const code = ['ExplorerInvalidArguments', 'ExplorerExplicitHostRequired'].includes(error.message)
    ? error.message : 'ExplorerStartupUnavailable';
  process.stderr.write(`${code}\n${help}`); process.exitCode = 1;
}
