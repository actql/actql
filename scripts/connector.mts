#!/usr/bin/env node
import {realpathSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {initRestConnector, writeRestConnector} from './connector-authoring.mjs';
// @ts-expect-error TS7016: The existing pre-emit local check guard is authored JavaScript.
import {durationSeconds, runLocalCheck} from './local-checks-guard.mjs';
import {readRestConformanceInput} from './connector-conformance-input.mjs';
import {isInstalledAuthoringToolkit} from './connector-authoring-toolkit.mjs';

const usage = 'Usage: connector.mjs init <directory> <id> | build|test <connector.json> <output> | conformance <normal-input.json> --timeout-seconds <seconds>';

// Select the existing installed case. The case still owns source,
// archive, Account, installation, public read and original Saved validation.
export function connectorConformancePlan(root: string, args: readonly string[]) {
  if (args.length !== 3 || args[1] !== '--timeout-seconds') throw new Error(usage);
  const timeoutSeconds = durationSeconds(args[2]) as number;
  const input = resolve(args[0]);
  const selected = readRestConformanceInput(input);
  const installed = isInstalledAuthoringToolkit(root);
  const testRunner = installed ? pathToFileURL(join(root, 'scripts/test-execution.mjs')).href
    : './scripts/test-execution.mjs';
  const testFile = 'scripts/fixtures/external-rest/normal-case.test.mjs';
  return {
    root: installed ? dirname(selected.outputRoot) : resolve(root), heavy: true,
    heavyResources: {memoryBytes: 4 * 1024 ** 3, diskBytes: 1024 ** 3, cpuThreads: 1},
    timeoutSeconds, graceSeconds: 5,
    steps: [{name: 'ordinary installed REST conformance and original cold Saved',
      command: process.execPath,
      args: ['--input-type=module', '-e',
        `import {runFocusedTests} from ${JSON.stringify(testRunner)};` +
        "process.exitCode=runFocusedTests('node',process.argv.slice(1),{cwd:process.cwd(),expectedTests:1});",
        installed ? join(root, testFile) : testFile],
      env: {ACTQL_REST_CONFORMANCE_INPUT: input}}],
  };
}

export function connectorCommand(args: readonly string[]) {
  const [command, ...rest] = args;
  if (command === 'init' && rest.length === 2) {
    return {definition: initRestConnector(resolve(rest[0]), rest[1]), runtimeExecuted: false};
  }
  if (['build', 'test'].includes(command) && rest.length === 2) {
    // test is the existing manifest projection/freshness layer only. Normal
    // installed SDK/Host conformance is a distinct actual runtime selection.
    return writeRestConnector({definitionPath: resolve(rest[0]),
      outputRoot: resolve(rest[1]), check: command === 'test',
      installedToolkit: isInstalledAuthoringToolkit(fileURLToPath(new URL('../', import.meta.url)))});
  }
  throw new Error(usage);
}
let invoked = false;
try { invoked = realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url)); }
catch { /* import without a main file */ }
if (invoked) {
  try {
    const [command, ...args] = process.argv.slice(2);
    if (command === 'conformance') {
      process.exitCode = await runLocalCheck(connectorConformancePlan(
        fileURLToPath(new URL('../', import.meta.url)), args));
    } else {
      console.log(JSON.stringify(connectorCommand([command, ...args]), null, 2));
    }
  }
  catch (error) { console.error((error as Error).message); process.exitCode = 1; }
}
