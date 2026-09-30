import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve, join} from 'node:path';
import {pathToFileURL} from 'node:url';

// Diagnostic application using installed packages. No test compiler, provider,
// or manufactured checker evidence participates in submission.
const installation = process.argv[2];
if (!installation) throw new Error('Usage: node scripts/reproduce-sga-baseline.mjs <packed-installation> [--inherited-order | --graphs-equal | --diff-apply]');
const requireInstalled = createRequire(join(resolve(installation), 'package.json'));
const {connect} = await import(pathToFileURL(requireInstalled.resolve('@actql/node')));
const fixture = new URL('../spec/frontend/fixtures/sga-surface/', import.meta.url);
const equal = process.argv.includes('--graphs-equal');
const inherited = process.argv.includes('--inherited-order');
const diff = process.argv.includes('--diff-apply');
if (Number(equal) + Number(inherited) + Number(diff) > 1) {
  throw new Error('Select one SGA probe');
}
const name = equal ? 'graphs-equal' : diff ? 'diff-apply' : 'reach-subgraph';
let document = await readFile(new URL(`${name}.expected-program.json`, fixture), 'utf8');
const expected = JSON.parse(await readFile(new URL(
  `${name}.expected-results.json`, fixture), 'utf8'));
if (inherited) {
  const program = JSON.parse(document);
  delete program.stages[0].results.edges.order_by;
  document = JSON.stringify(program);
}
const client = await connect({mode: 'local', owner: 'local', durability: 'durable'});
let observedState;
try {
  const run = await client.aql(document, {format: 'json',
    requestId: 'sga-baseline-' + (inherited ? 'inherited' : name)});
  observedState = await run.wait();
  assert.equal(observedState.status, 'succeeded',
    JSON.stringify(observedState));
  for (const [name, result] of Object.entries(expected)) {
    assert.deepEqual(await run.result(name).all(), result.rows);
  }
  console.log('SGA baseline rows passed; schema/runtime surface acceptance remains separate');
} catch (error) {
  let current = error;
  const codes = [];
  while (current && typeof current === 'object') {
    if (current.code) codes.push(current.code);
    current = current.cause;
  }
  console.error(JSON.stringify({codes, requestId: error.requestId ?? null,
    status: observedState?.status ?? null,
    terminalErrorCode: observedState?.terminal_error?.code ?? null}));
  process.exitCode = 1;
} finally {
  client.close();
}
