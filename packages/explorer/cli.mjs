#!/usr/bin/env node
import {openLocalExplorer} from './launcher.mjs';

const help = `Usage: actql-explorer --local [--state-dir <directory>]\n\nOpens one existing ActQL Local Host and the built read-only Explorer.\nTo borrow an already connected Client, use @actql/explorer/launcher.\nPaste the printed one-use bootstrap into the page within 60 seconds.\nClosing the viewer does not cancel a Run. No Vite server is required.\n`;
const args = process.argv.slice(2);
let local = false, stateDir;
try {
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) {
    process.stdout.write(help);
  } else {
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--local' && !local) local = true;
      else if (args[i] === '--state-dir' && stateDir === undefined && args[i + 1] &&
          !args[i + 1].startsWith('--')) stateDir = args[++i];
      else throw Error('ExplorerInvalidArguments');
    }
    if (!local) throw Error('ExplorerExplicitHostRequired');
    const gateway = await openLocalExplorer({local: stateDir === undefined ? {} : {stateDir}});
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
