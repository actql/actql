import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = name => ast.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === name);
const text = node => source.slice(node.start, node.end);
function visit(node, fn) {
  if (!node || typeof node !== 'object') return;
  fn(node);
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) for (const value of child) visit(value, fn);
    else if (child && typeof child === 'object') visit(child, fn);
  }
}
function normalMode() {
  const entry=declaration('connectEmbeddedLocal').body.body;
  assert.equal(entry.length,1);
  assert.equal(entry[0].type,'ReturnStatement');
  assert.equal(entry[0].argument.callee.name,'openPreparedInstalledHost');
  assert.deepEqual(entry[0].argument.arguments.map(value=>value.name),['options','initialEntry']);
  const values = [];
  visit(declaration('openPreparedInstalledHost').body, node => {
    if (node.type !== 'CallExpression' || node.callee?.object?.name !== 'Object' ||
        node.callee?.property?.name !== 'assign' || node.arguments[0]?.name !== 'originalInstallation') return;
    // Select Local Project initialization, independently of the same helper's
    // Remote initialization and its separate retained-output argument.
    if (!node.arguments[1]?.properties?.some(p=>p.key.name==='project')) return;
    const property = node.arguments[1].properties.find(p => p.key.name === 'retainedRelationOutput');
    if (property) values.push(property.value);
  });
  assert.equal(values.length, 1);
  return new Function('installation', `return ${text(values[0])};`);
}
function requirements(mode) {
  const prepared = {}, control = {}, admission = {}, sequence = {}, calls = [];
  const contracts = {initialControl: control, values: 'values', expression: 'fragment', ordered: 'ordered'};
  const run = {prepared, runtime: undefined, closed: false};
  const moon = {
    clientProgramInstalledManagedRunRequirements() {assert.fail('No raw fallback');},
    clientProgramInstalledManagedRunIssueIsUnsupported: () => false,
    clientProgramPrepareInstalledManagedSourceFreeWithContracts(...args) {
      assert.strictEqual(this, moon);
      calls.push(args);
      return sequence;
    },
    clientProgramPreparedInstalledManagedSourceFreeRequirements(value) {
      assert.strictEqual(value, sequence);
      assert.strictEqual(run.preparedSequences, sequence);
      return [1n, 2n, 3n, 4n, 5n, 6n];
    },
  };
  run.runtime = moon;
  const originals = {installation: {initialControl: control, projectRuntime: moon,
    retainedRelationOutput: mode, computeRuns: new WeakMap([[prepared, run]]),
    managedRunContracts: contracts,
    sequenceContractOriginal: {moon, control, contracts, admission}}};
  const read = new Function('assertSourceManagedHostPreparation', 'originalSourceManagedHostRequest',
    'installedManagedRunContracts', 'prepareInstalledSequenceContractOriginal', 'checked',
    'clientOperationError', 'runtimeIsError', text(declaration('readManagedComputeRunRequirements')) +
      ';return readManagedComputeRunRequirements;')(
    value => assert.strictEqual(value, originals),
    (value, program) => {assert.strictEqual(value, originals); assert.strictEqual(program, prepared);},
    () => contracts, () => originals.installation.sequenceContractOriginal,
    value => value, code => Object.assign(new Error(code), {code}), () => false);
  return {read: () => read(originals, prepared), calls, prepared, admission, run, sequence};
}

test('normal installed output mode is explicit before the same source-free preparation quote', () => {
  const normalize = normalMode();
  for (const [installation, expected] of [[undefined, false], [{}, false],
    [{retainedRelationOutput: false}, false], [{retainedRelationOutput: true}, true]]) {
    const selected = normalize(installation);
    assert.equal(selected, expected);
    const f = requirements(selected);
    assert.deepEqual(f.read(), {planningWork: 1, attempts: 2, holdings: 3,
      transferBytes: 4n, retainedBytes: 5n, executionBytes: 6n});
    assert.deepEqual(f.calls, [[f.prepared, f.admission, 'values', 'fragment', 'ordered', expected]]);
    f.read();
    assert.equal(f.calls.length, 1, 'The existing record retains its one original preparation');
  }
});

test('source-free quote refuses a missing or non-Boolean original mode before construction', () => {
  for (const mode of [undefined, null, 0, 'false', {}]) {
    const f = requirements(mode);
    assert.throws(f.read, {code: 'NodeManagedRunRuntimeUnavailable'});
    assert.deepEqual(f.calls, []);
    assert.equal(f.run.preparedSequences, undefined);
  }
});
