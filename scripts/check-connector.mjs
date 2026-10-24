// Author checks compose existing generators and test Owners; no runtime is built.
import {existsSync, readFileSync, statSync} from 'node:fs';
import {isAbsolute, join, relative, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parse} from 'yaml';
import {connectorManifestSelection} from './connector-manifest-selection.mjs';
import {checkBudget, runLocalCheck} from './local-checks-guard.mjs';

export const connectorCheckUsage = 'Usage: node scripts/check-connector.mjs <name> ' +
  '--stage source --test <file.test.mjs|file_test.mbt|file_wbtest.mbt> ' +
  '[--test <file> ...] [--timeout-seconds N]';

export function parseConnectorCheckArguments(args) {
  const [name, ...options] = args;
  if (args.length === 1 && name === '--help') return {help: true};
  const result = {name, tests: []};
  for (let index = 0; index < options.length; index++) {
    const flag = options[index], value = options[++index];
    if (value === undefined || value.startsWith('--')) throw new Error(connectorCheckUsage);
    if (flag === '--test') result.tests.push(value);
    else if (flag === '--stage' && result.stage === undefined) result.stage = value;
    else if (flag === '--timeout-seconds' && result.timeoutSeconds === undefined) result.timeoutSeconds = value;
    else throw new Error(connectorCheckUsage);
  }
  if (result.stage !== 'source') throw new Error('Only the source stage is implemented; installed acceptance remains separate.\n' + connectorCheckUsage);
  if (!result.tests.length || new Set(result.tests).size !== result.tests.length) {
    throw new Error('Select each affected test file once.\n' + connectorCheckUsage);
  }
  return result;
}

export function connectorSourceCheckPlan(root, {name, tests, timeoutSeconds}) {
  // Validate the named contribution before acquiring an execution Owner.
  const [entry] = connectorManifestSelection(root, {names: [name]});
  const selected = tests.map(path => {
    const absolute = resolve(root, path), local = relative(root, absolute);
    if (isAbsolute(path) || local.startsWith('..') || !existsSync(absolute) || !statSync(absolute).isFile()) {
      throw new Error(`Select an existing repository test file: ${path}`);
    }
    const kind = /\.test\.mjs$/u.test(local) ? 'node' : /_(?:wb)?test\.mbt$/u.test(local) ? 'moon' : undefined;
    if (kind === undefined) throw new Error(`Unsupported focused test file: ${path}`);
    return {kind, path: local};
  });
  if (!selected.length || new Set(selected.map(item => item.path)).size !== selected.length) {
    throw new Error('Select each affected test file once.');
  }
  const workflow = parse(readFileSync(join(root, '.github/workflows/ci.yml'), 'utf8'));
  const seconds = checkBudget(timeoutSeconds, workflow.jobs.lint['timeout-minutes']);
  const steps = [{name: 'complete normal connector generation (read-only)',
    command: process.execPath, args: ['scripts/connector-node-bundles.mjs']}];
  for (const {kind, path} of selected) {
    // Reuse the nonzero guard in an owned child, as local-checks.mjs does.
    steps.push({name: `selected ${name} ${kind} test: ${path}`, command: process.execPath,
      args: ['--input-type=module', '-e',
        "import {runFocusedTests} from './scripts/test-execution.mjs'; process.exitCode = runFocusedTests(process.argv[1], process.argv.slice(2), {cwd: process.cwd()});",
        kind, ...(kind === 'moon' ? ['--target', 'js'] : []), path]});
  }
  return {root, heavy: false, timeoutSeconds: seconds, graceSeconds: 5, steps,
    selection: {name, declaredRoles: ['compute', 'node', 'host'].filter(role => entry[role] !== undefined),
      tests: selected, generation: 'complete normal Node and RelA assembly; read-only',
      qualification: 'selected source checks only; no installed or provider acceptance'}};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseConnectorCheckArguments(process.argv.slice(2));
    if (options.help) console.log(connectorCheckUsage);
    else {
      const root = fileURLToPath(new URL('../', import.meta.url));
      const {selection, ...execution} = connectorSourceCheckPlan(root, options);
      console.log(JSON.stringify({connectorSourceCheck: selection}));
      process.exitCode = await runLocalCheck(execution);
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 2;
  }
}
