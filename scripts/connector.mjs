#!/usr/bin/env node
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {initRestConnector, writeRestConnector} from './connector-authoring.mjs';
import {durationSeconds, runLocalCheck} from './local-checks-guard.mjs';
import {readRestConformanceInput} from './fixtures/external-rest/conformance-input.mjs';

const usage = 'Usage: connector.mjs init <directory> <id> | build|test <connector.json> <output> | conformance <normal-input.json> --timeout-seconds <seconds>';

// Select the existing installed case. The case still owns source,
// archive, Account, installation, public read and original Saved validation.
export function connectorConformancePlan(root, args) {
  if (args.length !== 3 || args[1] !== '--timeout-seconds') throw new Error(usage);
  const timeoutSeconds = durationSeconds(args[2]);
  const input = resolve(args[0]);
  readRestConformanceInput(input);
  return {
    root: resolve(root), heavy: true,
    heavyResources: {memoryBytes: 4 * 1024 ** 3, diskBytes: 1024 ** 3, cpuThreads: 1},
    timeoutSeconds, graceSeconds: 5,
    steps: [{name: 'ordinary installed REST conformance and original cold Saved',
      command: process.execPath,
      args: ['--input-type=module', '-e',
        "import {runFocusedTests} from './scripts/test-execution.mjs';process.exitCode=runFocusedTests('node',process.argv.slice(1),{cwd:process.cwd(),expectedTests:1});",
        'scripts/fixtures/external-rest/normal-case.test.mjs'],
      env: {ACTQL_REST_CONFORMANCE_INPUT: input}}],
  };
}

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
  throw new Error(usage);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const [command, ...args] = process.argv.slice(2);
    if (command === 'conformance') {
      process.exitCode = await runLocalCheck(connectorConformancePlan(
        fileURLToPath(new URL('../', import.meta.url)), args));
    } else {
      console.log(JSON.stringify(connectorCommand([command, ...args]), null, 2));
    }
  }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
