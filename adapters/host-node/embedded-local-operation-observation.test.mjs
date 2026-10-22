import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';

// Original Host expressions with explicit execution/observation ports. This
// supplies no Account grant, Run claim, Store receipt or physical capacity.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const named = [], resultCaptures = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator' && node.id.name === 'submitEffect') named.push(node.init);
  if (node.type === 'Property' && node.key.name === 'captureResultOperation') resultCaptures.push(node.value);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(ast);
assert.equal(named.length, 1);
const install = compileFunction(`return ${source.slice(named[0].start, named[0].end)};`,
  ['effectRun', 'checkpoints', 'runAcceptance', 'admitEffectDefinition', 'diagnostic',
    'settleHeldRun', 'runIdOf', 'observation']);
const deferred = () => {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
};

for (const failed of [false, true]) {
  test(`initial Effect observation retains settlement after early acceptance (${failed ? 'failure' : 'success'})`, async () => {
    const work = deferred(), holding = deferred(), entered = deferred(), retained = [], diagnostics = [];
    const accepted = {ref: {runDefinitionCid: 'explicit-original'}, durability: 'explicit', revision: 1};
    const primary = new Error('OriginalEffectFailure');
    let starts = 0, settlements = 0;
    const submit = install({checkSupported() {}, start(original) {
      starts++; assert.equal(original, accepted); return work.promise;
    }}, undefined, undefined, async () => accepted,
    (...args) => diagnostics.push(args), async original => {
      assert.equal(original, accepted); settlements++; entered.resolve(); await holding.promise;
    }, () => 'explicit-run', {retainOperation(promise) {retained.push(promise);}});
    try {
      assert.deepEqual(await submit({preparedProgram: {}, requestId: 'explicit-request'}, {}, []), accepted);
      assert.equal(starts, 1);
      assert.equal(retained.length, 1);
      assert.notEqual(retained[0], work.promise);
      let settled = false;
      retained[0].then(() => {settled = true;});
      if (failed) work.reject(primary); else work.resolve({kind: 'started'});
      await entered.promise;
      assert.equal(settled, false);
      holding.resolve(); await retained[0];
      assert.equal(settled, true);
      assert.equal(settlements, 1);
      assert.equal(diagnostics.length, failed ? 1 : 0);
      if (failed) assert.equal(diagnostics[0][0], 'effect_start_failed');
    } finally {
      work.resolve({kind: 'started'}); holding.resolve();
      await work.promise.catch(() => {});
      if (retained.length) await retained[0];
    }
  });
}

test('Result operation capture forwards the same installed optional holder on demand', () => {
  assert.equal(resultCaptures.length, 1);
  const capture = compileFunction(`return ${source.slice(resultCaptures[0].start,
    resultCaptures[0].end)};`, ['observation']);
  assert.equal(capture(undefined), undefined);
  let calls = 0;
  const holder = Object.freeze({run(work) {return work();}, release() {}});
  const original = {captureCurrentOperation() {assert.equal(this, original); calls++; return holder;}};
  const read = capture(original);
  assert.equal(calls, 0);
  assert.equal(read(), holder);
  assert.equal(calls, 1);
});
