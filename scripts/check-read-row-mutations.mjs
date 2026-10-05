// Actual public read fixtures reuse the existing named-assertion mutation guard.
// Import, timeout and unselected-test failures are infrastructure failures.
import {spawnSync} from 'node:child_process';
import {readFileSync, writeFileSync} from 'node:fs';
import {mutationAcceptance} from './check-disclosure-mutations.mjs';

const path = 'packages/sdk/index.mjs';
const acceptance = 'adapters/host-node/client-read-progress.test.mjs';
const shape = ['rows', 'all'].map(operation => ({
  name: `https: ${operation} refuses non-object delivery rows before yielding`,
  assertions: [{id: 'read-row-shape', operator: 'strictEqual'},
    {id: 'read-row-count', operator: 'strictEqual'}],
}));
const syntax = ['rows', 'all'].map(operation => ({
  name: `https: ${operation} classifies malformed JSON as an invalid delivery frame`,
  assertions: [{id: 'read-row-syntax', operator: 'strictEqual'},
    {id: 'read-row-count', operator: 'strictEqual'}],
}));
const mutations = [
  ['non-object frames become successful rows', [
    ["                  if (row === null || typeof row !== 'object' ||\n                      Array.isArray(row)) fail('InvalidResultFrame');", ''],
  ], shape],
  ['malformed JSON loses its typed refusal', [
    ["                  catch { fail('InvalidResultFrame'); }", '                  catch (cause) { throw cause; }'],
  ], syntax],
  ['invalid rows increase the yielded count', [
    ['                  let row;', '                  rowsYielded++;\n                  let row;'],
    ['                  rowsYielded++;\n                  yield row;', '                  yield row;'],
  ], shape],
];
const accepted = tests => {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '60', '--', '--test-name-pattern',
    `^(?:${tests.map(value => value.name).join('|')})$`, acceptance],
  {encoding: 'utf8', timeout: 70000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, tests, acceptance);
};
const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, replacements, tests] of mutations) {
    let source = original;
    for (const [from, to] of replacements) {
      if (source.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
      source = source.replace(from, to);
    }
    writeFileSync(path, source);
    results.push({name, rejected: !accepted(tests)});
  }
} finally {
  writeFileSync(path, original);
}
const restoredAccepted = accepted([...shape, ...syntax]);
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
