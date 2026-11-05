import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';
import {installModelProviders} from './installed-model.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const nodes = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  nodes.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(ast);
const request = nodes.find(node => node.type === 'VariableDeclarator' && node.id.name === 'requestOf');
const choice = request.init.body.body.find(node => node.type === 'IfStatement' &&
  node.test.left?.object?.name === 'occurrences' && node.alternate?.type === 'ExpressionStatement');
assert.equal(choice.alternate.expression.callee.name, 'prepareInferSelection');
const shared = nodes.find(node => node.type === 'VariableDeclarator' && node.id.name === 'prepareComposedInferSelection');
assert(shared);
const argument = choice.alternate.expression.arguments[1];
const select = new Function('occurrences', 'keyedAcquisition', 'moon', 'preparedProgram',
  `return (${source.slice(argument.start, argument.end)});`);

// Actual authored call expression with explicit opaque stand-ins. These
// controls prove routing only, not Common Model or operational admission.
test('a single composed INFER occurrence retains its original identity after two Sources', () => {
  const occurrence = Object.freeze({}), prepared = Object.freeze({});
  const moon = {clientProgramSerializationOccurrences(value) {
    assert.strictEqual(value, prepared); return [];
  }};
  assert.strictEqual(select([occurrence], undefined, moon, prepared), occurrence);
});

test('the absence of an INFER occurrence stays absent instead of inventing a Model selection', () => {
  const moon = {clientProgramSerializationOccurrences: () => []};
  assert.equal(select([], undefined, moon, {}), undefined);
});

// The original registration snapshot is shared by both authored Task
// selections. This is a caller identity check, not Core quantity admission.
function selectGroup(selections) {
  const prepared = {}, occurrences = selections.map(() => ({})), held = new WeakMap();
  const createShared = Function('inferSelections', 'prepareInferSelection', 'prepareSubmit',
    'return (' + source.slice(shared.init.start, shared.init.end) + ');');
  let selected = 0;
  const prepare = (actual, occurrence, retain = true) => {
    assert.equal(actual, prepared); assert.equal(occurrence, occurrences[selected]);
    const value = selections[selected++];
    if (retain) held.set(prepared, value);
    return value;
  };
  const sharedSelection = createShared(held, prepare, {originalInferRun: () => undefined});
  const choose = Function('occurrences', 'preparedProgram', 'inferSelections',
    'modelCoordinates', 'prepareInferSelection', 'prepareComposedInferSelection', source.slice(choice.start, choice.end));
  choose(occurrences, prepared, held, undefined, prepare, sharedSelection);
  assert.equal(selected, selections.length);
  return held.get(prepared);
}
function installedQuantities() {
  const entry = {providerId: 'models/packed', invoke() {assert.fail('No Model dispatch');},
    validatePrompt: () => true,
    quantityCapacity: {limits: {tokens: 66n, costUnits: 0n, durationMs: 1000n},
      perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}}};
  const moon = {clientProgramInstallModelProvider() {return {};}};
  return installModelProviders(moon, () => [entry]).get('models/packed').quantityCapacity;
}

test('checked Model group retains the SAME installed quantity original without computing another limit', () => {
  const quantityCapacity = installedQuantities();
  assert(Object.isFrozen(quantityCapacity)); assert(Object.isFrozen(quantityCapacity.limits));
  const components = [{graph: {}, quantityCapacity}, {graph: {}, quantityCapacity}];
  const selected = selectGroup(components);
  assert.equal(selected.quantityCapacity, quantityCapacity);
  assert.equal(selected.quantityCapacity.limits, quantityCapacity.limits);
  assert.deepEqual(selected.components, components);
  assert.deepEqual(selected.graph, components.map(component => component.graph));
});

test('group quantity forwarding does not combine distinct equal registrations or fill an absent declaration', () => {
  const quantityCapacity = installedQuantities(), other = installedQuantities();
  assert.notEqual(quantityCapacity, other); assert.deepEqual(quantityCapacity, other);
  for (const quantities of [[quantityCapacity, other], [quantityCapacity, undefined],
    [undefined, quantityCapacity], [undefined, undefined]]) {
    const selected = selectGroup(quantities.map(quantityCapacity => ({graph: {}, quantityCapacity})));
    assert.equal(selected.quantityCapacity, undefined);
  }
});

test('singular Model selection keeps its installed quantity original and selected object unchanged', () => {
  const selection = Object.freeze({graph: {}, quantityCapacity: installedQuantities()});
  assert.equal(selectGroup([selection]), selection);
});
