import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {parse} from 'acorn';
import {sourcePreparationPort} from '../../packages/sdk/internal/private-source-preparation.mjs';

const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const functions = tree.body.map(node => node.declaration ?? node);
const open = functions.find(node => node.type === 'FunctionDeclaration' &&
  node.id.name === 'openInstalledHost');
const declarations = [];
function collect(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclarator') declarations.push(node);
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(collect);
    else if (value !== null && typeof value === 'object') collect(value);
  }
}
collect(open.body);
const selected = ['selectedSourcePreparation', 'bindOwnedRequest', 'ingress', 'sourcePreparation', 'port'].map(name => {
  const matches = declarations.filter(node => node.id.name === name);
  assert.equal(matches.length, 1, name);
  const [declaration] = matches;
  return `const ${source.slice(declaration.start, declaration.end)};`;
}).join('\n');
// Execute the actual ingress assembly, not another forwarding implementation.
// Explicit ports below establish identity/routing only, not a Source issuer.
const assemble = compileFunction(`${selected}\nreturn port;`,
  ['preparation', 'observation', 'createNodeInProcessClientHost', 'principalId',
    'hostOperations', 'sourcePreparationPort']);
const connect = functions.find(node => node.type === 'FunctionDeclaration' &&
  node.id.name === 'connectEmbeddedLocal');
const preparation = connect.body.body.flatMap(node => node.declarations ?? [])
  .find(node => node.id.name === 'preparation').init;
const method = preparation.arguments[0].properties.find(node => node.key.name === 'sourcePreparation').value;
const selectOriginal = compileFunction(`return function(){${source.slice(method.body.start + 1,
  method.body.end - 1)}};`, ['mockPreparation', 'sourceManaged', 'originals',
  'assertSourceManagedInstallationCurrent']);

test('unselected ingress retains its existing identity without manufacturing a Source port', () => {
  const ingress = {perform() {assert.fail('NoRequest');}};
  const port = assemble(undefined, undefined, () => ingress, 'actor', {}, sourcePreparationPort);
  assert.equal(port, ingress);
  assert.equal(Object.hasOwn(port, sourcePreparationPort), false);
});

test('selected ingress forwards the same original Source view and unchanged request/receiver', async () => {
  const original = {}, request = {}, signal = {}, response = {};
  let reads = 0, sends = 0;
  const preparation = {sourcePreparation() {assert.equal(this, preparation); reads++; return original;}};
  const ingress = {perform(operation, body, abort) {
    assert.equal(this, ingress); assert.equal(operation, 'submit-intent');
    assert.equal(body, request); assert.equal(abort, signal); sends++; return response;
  }};
  const port = assemble(preparation, undefined, () => ingress, 'actor', {}, sourcePreparationPort);
  assert.equal(Object.isFrozen(port), true);
  assert.equal(port[sourcePreparationPort], original);
  assert.equal(await port.perform('submit-intent', request, signal), response);
  assert.equal(reads, 2); assert.equal(sends, 1);
  assert.equal(Object.hasOwn(request, sourcePreparationPort), false);
});

test('observation wrapping keeps the same Source and does not resend ingress', async () => {
  const original = {}, request = {}, result = {}, order = [];
  const observation = {run(operation, metadata, send) {
    assert.equal(this, observation); assert.equal(operation, 'connect');
    assert.equal(metadata, undefined); order.push('observe'); return send();
  }};
  const ingress = {perform(operation, body, signal) {
    assert.equal(this, ingress); assert.equal(operation, 'connect');
    assert.equal(body, request); assert.equal(signal, undefined); order.push('send'); return result;
  }};
  const port = assemble({sourcePreparation: () => original}, observation,
    () => ingress, 'actor', {}, sourcePreparationPort);
  assert.equal(port[sourcePreparationPort], original);
  assert.equal(await port.perform('connect', request), result);
  assert.deepEqual(order, ['observe', 'send']);
});

test('selected preparation currentness refuses instead of silently producing an unselected port', () => {
  const original = {}, sameFive = {}, marker = {};
  let checks = 0;
  const check = (view, originals) => {
    assert.equal(view, original); assert.equal(originals, sameFive); checks++; throw marker;
  };
  const preparation = {sourcePreparation: selectOriginal({}, original, sameFive, check)};
  assert.throws(() => assemble(preparation, undefined, () => ({perform() {
    assert.fail('NoSend');
  }}), 'actor', {}, sourcePreparationPort), error => error === marker);
  assert.equal(checks, 1);
  assert.equal(selectOriginal(undefined, original, sameFive, check)(), undefined);
  assert.equal(checks, 1);
});
