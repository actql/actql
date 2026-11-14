import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import {types as nodeTypes} from 'node:util';
import {parse} from 'acorn';

const text = readFileSync(new URL('./installed-host-services.mjs', import.meta.url), 'utf8');
const ast = parse(text, {ecmaVersion: 'latest', sourceType: 'module'});
const node = ast.body.find(node => node.type === 'FunctionDeclaration' && node.id.name === 'prepareModelTaskInput');
assert(node, 'Test the actual existing initialization helper, not a test copy');
function fixture() {
  let live = true, ceiling = 100000, calls = 0;
  const reservations = [], failures = [];
  const material = {phase: 'working', busy: false, inputs: [], providers: []};
  const original = {current() {if (!live) throw lost;}, moon: {
    clientProgramAccumulateModelTaskConstructionCapacity(previous, current) {
      assert.equal(material.busy, true);
      assert(current && Number.isSafeInteger(current.bytes));
      calls++;
      return {bytes: (previous?.bytes ?? 0) + current.bytes};
    },
  }};
  const lost = new Error('OriginalCurrentLost');
  const prepare = runInNewContext('(' + text.slice(node.start, node.end) + ')', {
    nodeTypes, checked: value => value,
    fail(code) {throw Object.assign(new Error(code), {code});},
    requireSynchronousSourceConstruction(_material, value) {assert(!nodeTypes.isPromise(value)); return value;},
    retainSourceFailure(_material, cause) {failures.push(cause);},
    reserveSource(actual, same) {
      assert.strictEqual(actual, original); assert.strictEqual(same, material);
      actual.current();
      assert.equal(material.providers.length, 1, 'Only the one incremental Model slot');
      const bytes = material.providers[0].bytes;
      reservations.push(bytes);
      if (bytes > ceiling) throw limit;
    },
    reconcileSource(actual, same) {
      assert.strictEqual(actual, original); assert.strictEqual(same, material);
      reservations.push(material.providers[0].bytes);
    },
  });
  const limit = new Error('OriginalParentCapacity');
  const attempts = new WeakSet();
  const validate = () => assert.equal(material.phase, 'working');
  return {material, reservations, failures, lost, limit,
    lose() {live = false;}, cap(value) {ceiling = value;}, calls: () => calls,
    invoke(projection) {return prepare(original, material, projection, attempts, validate);}};
}
const projection = project => Object.freeze({capacity: () => ({bytes: 100}),
  retained: () => ({bytes: 3}), project});

test('same initialization prefix retains actual outputs across 129 current metadata constructors', () => {
  const f = fixture(); let projects = 0;
  for (let index = 0; index < 129; index++) {
    const result = Object.freeze({index});
    assert.strictEqual(f.invoke(projection(() => {projects++; return result;})), result);
    assert.equal(f.material.providers[0].bytes, 3 * (index + 1));
  }
  assert.equal(projects, 129);
  assert.equal(f.calls(), 258, 'Two constant-time scalar compositions, no earlier-prefix scan');
  assert.equal(f.material.providers.length, 1);
  assert.equal(f.material.inputs.filter(value => value !== undefined).length, 129);
  assert.equal(f.failures.length, 0);
});

test('same parent refusal precedes the next metadata constructor and retains its peak', () => {
  const f = fixture(); let projects = 0;
  f.invoke(projection(() => ({first: true})));
  f.cap(102);
  const next = projection(() => {projects++; return {};});
  assert.throws(() => f.invoke(next), error => error === f.limit);
  assert.equal(projects, 0);
  assert.equal(f.material.providers[0].bytes, 103);
  assert.strictEqual(f.material.inputs.at(-1), next);
  assert.throws(() => f.invoke(projection(() => assert.fail())), error => error === f.limit);
});

test('current loss after original metadata return keeps actual output and full construction debt', () => {
  const f = fixture(), result = Object.freeze({actual: true});
  const input = projection(() => {f.lose(); return result;});
  assert.throws(() => f.invoke(input), error => error === f.lost);
  assert.equal(f.material.providers[0].bytes, 100);
  assert.strictEqual(f.material.inputs[0], input);
  assert.strictEqual(f.material.inputs[1], result);
  assert.strictEqual(f.failures[0], f.lost);
});
