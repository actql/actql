// Small same-input preparation probe. Build each checkout before running;
// compilation of runtime bundles and provider I/O are outside these samples.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {loadavg} from 'node:os';
import {readFile} from 'node:fs/promises';
import {Session} from 'node:inspector/promises';
import {resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {performance} from 'node:perf_hooks';
import {canonicalText} from './check-canonical-json.mjs';

const root = resolve(process.argv[2] ?? fileURLToPath(new URL('../',
  import.meta.url)));
const url = path => pathToFileURL(resolve(root, path));
const read = path => readFile(url(path), 'utf8');
const moon = await import(url(
  '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'));
const {runtimeCore} = await import(url('adapters/host-common/runtime-core.mjs'));
const {installNodeClientProgramPreparation} = await import(url(
  'adapters/host-node/client-program-preparation.mjs'));
const {sourceFreeValuesPlan, acquiredTaskRunAdmission} = await import(url(
  'adapters/host-node/local-values-plan.mjs'));
const control = runtimeCore(moon).publicationControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const results = [];
for (const kind of ['values', 'tasks']) {
  const acquired = kind === 'tasks';
  const environmentWire = canonicalText(JSON.parse(await read(acquired
    ? 'adapters/host-node/fixtures/query-amount-environment.json'
    : 'packages/sdk/fixtures/values.environment.json')));
  const environmentCid = JSON.parse(environmentWire).evidence_bundle_cid;
  const environment = moon.clientProgramCheckEnvironment(environmentWire,
    environmentCid, false, false, true, false, false, false, false);
  assert.ok(environment);
  const document = await read(acquired
    ? 'adapters/connectors/duckdb/node/examples/program.json'
    : 'packages/sdk/fixtures/values.json');
  const parameters = acquired ? JSON.parse(await read(
    'adapters/connectors/duckdb/node/examples/parameters.json')) : null;
  const prepare = installNodeClientProgramPreparation({moon, environment});
  const once = () => {
    const preparedProgram = prepare({kind: 'aql',
      input: {text: document, format: 'json'}, parameters});
    return (acquired ? acquiredTaskRunAdmission : sourceFreeValuesPlan)({
      moon, control, preparedProgram, document, format: 'json', parameters,
      environmentWire, environmentCid, authorityScopeCid: cid('a'),
      tenantId: 'local', requestId: 'preparation-probe',
      storeAuthorityCid: cid('c'), now: () => '2026-09-27T00:00:00.000Z',
    });
  };
  for (let warmup = 0; warmup < 5; warmup++) once();
  const milliseconds = [];
  for (let sample = 0; sample < 7; sample++) {
    const start = performance.now();
    once();
    milliseconds.push(performance.now() - start);
  }
  // Collect actual entry calls separately: coverage changes JIT behavior and
  // must not be enabled during the timing samples. Include a portable ABI
  // reached outside the supplied Local runtime, if the checkout still uses it.
  const session = new Session();
  session.connect();
  await session.post('Profiler.enable');
  await session.post('Profiler.startPreciseCoverage',
    {callCount: true, detailed: false});
  const plan = once();
  const {result} = await session.post('Profiler.takePreciseCoverage');
  await session.post('Profiler.stopPreciseCoverage');
  session.disconnect();
  const boundaries = [];
  const localNames = new Map([
    [moon.clientProgramPrepareEffectFreeWithParameters.name, 'prepare'],
    [moon.clientProgramCompileLocalValues.name, 'compile'],
    [moon.clientProgramCompileLocalTasks.name, 'compile'],
  ]);
  for (const script of result) {
    const local = script.url === url(
      '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js').href;
    const portable = script.url === url('packages/run-host-core/index.mjs').href;
    if (!local && !portable) continue;
    for (const fn of script.functions) {
      const operation = local ? localNames.get(fn.functionName)
        : fn.functionName === 'prepare' ? 'prepare'
          : ['compileValues', 'compileTasks'].includes(fn.functionName)
            ? 'compile' : undefined;
      const calls = fn.ranges[0]?.count ?? 0;
      if (operation !== undefined && calls > 0) {
        boundaries.push({runtime: local ? 'local' : 'portable',
          operation, calls});
      }
    }
  }
  const sorted = [...milliseconds].sort((a, b) => a - b);
  results.push({kind, milliseconds, medianMs: sorted[3], boundaries,
    definition: JSON.parse(plan.runDefinition.wire)});
}
console.log(JSON.stringify({
  checkoutSha: execFileSync('git', ['rev-parse', 'HEAD'],
    {cwd: root, encoding: 'utf8'}).trim(),
  node: process.version, loadAverage: loadavg(), samples: results,
}, null, 2));
