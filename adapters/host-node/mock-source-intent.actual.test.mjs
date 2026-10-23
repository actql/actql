import assert from 'node:assert/strict';
import test from 'node:test';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import {pathToFileURL} from 'node:url';
import {parse} from 'acorn';
import {canonicalJson} from '../../packages/sdk/checkpoints.mjs';

assert.ok(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME, 'Select the actual matching Common runtime');
const moon = await import(pathToFileURL(process.env.ACTQL_TEST_PROJECT_COMMON_RUNTIME));
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const operation = tree.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'sourceManagedSubmittedIntentCid');
assert.ok(operation);
const run = compileFunction(source.slice(operation.body.start + 1, operation.body.end - 1),
  ['originals', 'originalSourceInstallation', 'body', 'assertSourceManagedHostPreparation',
    'assertSourceManagedPreparationCurrent', 'canonicalValueJson', 'clientOperationError']);

// Real original intent Owner, literal independent old preimages. The two
// current fences are explicit Root fixtures, not an operational admission.
for (const [name, body, preimage] of [
  ['absent original choices', {kind: 'aql', input: {text: 'SELECT 1 AS n', format: 'sql'}, parameters: null},
    '{"intent":{"input":{"format":"sql","text":"SELECT 1 AS n"},"kind":"aql","parameters":null},"version":"actql-submitted-intent/0.1"}'],
  ['original commit stop', {kind: 'aql', input: {text: 'SELECT 1 AS n', format: 'sql'}, parameters: null, stopBefore: 'commit'},
    '{"intent":{"input":{"format":"sql","text":"SELECT 1 AS n"},"kind":"aql","parameters":null,"stopBefore":"commit"},"version":"actql-submitted-intent/0.1"}'],
  ['exact text and read-only', {kind: 'aql', input: {text: 'SELECT @é AS n\r\n', format: 'sql'}, parameters: {'é': 1.25}, readOnly: true},
    '{"intent":{"input":{"format":"sql","text":"SELECT @é AS n\\r\\n"},"kind":"aql","parameters":{"é":1.25},"readOnly":true},"version":"actql-submitted-intent/0.1"}'],
]) test('actual original Source intent CID preserves ' + name, () => {
  const originals = {installation: {projectRuntime: moon}}, installation = {};
  let checks = 0;
  const expected = 'sha256:' + createHash('sha256').update(preimage, 'utf8').digest('hex');
  const actual = run(originals, installation, body,
    value => {assert.equal(value, originals); checks++;},
    (value, pair) => {assert.equal(value, installation); assert.equal(pair, originals); checks++;},
    canonicalJson, code => Object.assign(new Error(code), {code}));
  assert.equal(actual, expected); assert.equal(checks, 4);
});

test('original Source current refusal precedes every intent body observation', () => {
  let reads = 0;
  const body = new Proxy({}, {get() {reads++;}, ownKeys() {reads++;}});
  const refusal = Object.freeze(new Error('OriginalSourceCurrentRefused'));
  assert.throws(() => run({}, {}, body, () => {}, () => {throw refusal;}, canonicalJson,
    code => new Error(code)), error => error === refusal);
  assert.equal(reads, 0);
});
