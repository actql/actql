import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

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
