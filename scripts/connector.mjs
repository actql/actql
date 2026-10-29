#!/usr/bin/env node
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initRestConnector, writeRestConnector} from './connector-authoring.mjs';

export function connectorCommand(args) {
  const [command, ...rest] = args;
  if (command === 'init' && rest.length === 2) {
    return {definition: initRestConnector(resolve(rest[0]), rest[1]), runtimeExecuted: false};
  }
  if (['build', 'test'].includes(command) && rest.length === 2) {
    // test is the existing manifest projection/freshness layer only. Normal
    // installed SDK/Host conformance is a distinct actual runtime selection.
    return writeRestConnector({definitionPath: resolve(rest[0]),
      outputRoot: resolve(rest[1]), check: command === 'test'});
  }
  throw new Error('Usage: connector.mjs init <directory> <id> | build|test <connector.json> <output>');
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(connectorCommand(process.argv.slice(2)), null, 2)); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
