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
const lookupSnapshots = ['local', 'https'].map(entrance => ({
  name: `${entrance}: delivery lookup snapshots survive reused owner record containers`,
  assertions: ['snapshot', 'freeze', 'detached'].map(id => ({
    id: `delivery-lookup-${id}`, operator: 'strictEqual',
  })),
}));
const lookupAdmission = ['clone changes a previously valid field', 'reply cannot be cloned']
  .map(fault => ({
    name: `local: delivery lookup rejects ${fault}`,
    assertions: [{id: 'delivery-lookup-admission', operator: 'strictEqual'}],
  }));
const lookupCapture = "            answer = captureResponse(answer);\n" +
  "            if (!validDeliveryAttemptLookup(answer, expected)) fail('InvalidHostAttemptLookup');\n";
const lookupCopy = "            answer = detachResponse(answer);\n" +
  "            if (!validDeliveryAttemptLookup(answer, expected)) fail('InvalidHostAttemptLookup');\n" +
  "            return retainDeliveryExplanation(freezeInput(answer), {";
const observations = phase => ['local', 'https'].map(entrance => ({
  name: `${entrance}: delivery observation explains ${phase} against one published Run`,
  assertions: [{id: 'delivery-observation-classification', operator: 'strictEqual'},
    {id: 'delivery-opening-explanation', operator: 'strictEqual'},
    {id: 'delivery-observation-receipt', operator: 'strictEqual'},
    {id: 'delivery-observation-custody', operator: 'strictEqual'}],
}));
const observationAcceptance = 'adapters/host-node/client-delivery-observation.test.mjs';
const mutations = [
  ['non-object frames become successful rows', [
    ["                  if (row === null || typeof row !== 'object' ||\n                      Array.isArray(row)) fail('InvalidResultFrame');", ''],
  ], shape],
  ['lookup responses retain shared mutable owner records', [
    [lookupCapture + lookupCopy, '            return retainDeliveryExplanation(Object.freeze(answer), {'],
  ], lookupSnapshots],
  ['lookup clone skips preservation and contract revalidation', [
    [lookupCopy, '            answer = structuredClone(answer);\n' +
      '            return retainDeliveryExplanation(freezeInput(answer), {'],
  ], lookupAdmission],
  ['malformed JSON loses its typed refusal', [
    ["                  catch { fail('InvalidResultFrame'); }", '                  catch (cause) { throw cause; }'],
  ], syntax],
  ['invalid rows increase the yielded count', [
    ['                  let row;', '                  rowsYielded++;\n                  let row;'],
    ['                  rowsYielded++;\n                  yield row;', '                  yield row;'],
  ], shape],
  ['absent lookup becomes Host delivery success', [
    ["const observation = answer.kind === 'not_found' ? 'lookup_unresolved'", "const observation = answer.kind === 'not_found' ? 'host_delivery_succeeded'"],
  ], observations('before-commit'), observationAcceptance],
  ['an uncertain opening is described as a confirmed stopped read', [
    ["state === 'opening' ? {observation: 'read_open_unknown'} : undefined", 'undefined'],
  ], observations('after-commit'), observationAcceptance],
  ['confirmed Delivery loses its receipt reference', [
    ['hostReleaseReceiptCid: answer.hostReleaseReceipt.result_delivery_receipt_cid,', ''],
  ], observations('normal'), observationAcceptance],
  ['copied lookup acquires original observation custody', [
    ['const deliveryExplanations = new WeakMap();',
      'const deliveryExplanations = {values: new Map(),\n' +
      '  set(key, value) {this.values.set(JSON.stringify(key), value);},\n' +
      '  get(key) {return this.values.get(JSON.stringify(key));}};'],
  ], observations('after-commit'), observationAcceptance],
];
const accepted = (tests, entry = acceptance) => {
  const result = spawnSync(process.execPath, ['scripts/local-checks.mjs', 'test', 'node',
    '--timeout-seconds', '60', '--', '--test-name-pattern',
    `^(?:${tests.map(value => value.name).join('|')})$`, entry],
  {encoding: 'utf8', timeout: 70000, maxBuffer: 16 * 1024 * 1024});
  return mutationAcceptance(result, tests, entry);
};
const original = readFileSync(path, 'utf8');
const results = [];
try {
  for (const [name, replacements, tests, entry] of mutations) {
    let source = original;
    for (const [from, to] of replacements) {
      if (source.split(from).length !== 2) throw new Error(`Mutation anchor not unique: ${name}`);
      source = source.replace(from, to);
    }
    writeFileSync(path, source);
    results.push({name, rejected: !accepted(tests, entry)});
  }
} finally {
  writeFileSync(path, original);
}
const restoredAccepted = accepted([...shape, ...syntax, ...lookupSnapshots, ...lookupAdmission]) &&
  accepted(['normal', 'before-commit', 'after-commit'].flatMap(observations), observationAcceptance);
console.log(JSON.stringify({mutations: results, restoredAccepted}, null, 2));
if (!restoredAccepted || results.some(result => !result.rejected)) process.exitCode = 1;
