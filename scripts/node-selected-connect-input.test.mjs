import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileFunction} from 'node:vm';
import test from 'node:test';
import {parse} from 'acorn';

// Exact public function statements with explicit dispatch/provider doubles.
// This proves the before-copy connection, not the installed operational root.
const source = readFileSync(new URL('../packages/node/index.mjs', import.meta.url), 'utf8');
const tree = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const declaration = tree.body.map(node => node.declaration ?? node)
  .find(node => node.type === 'FunctionDeclaration' && node.id.name === 'connect');
assert.ok(declaration);
const make = compileFunction('return async function(options,stringOptions){' +
  source.slice(declaration.body.start + 1, declaration.body.end - 1) + '};',
['connectHost', 'ClientError', 'selectedInitialControlHostPreparation',
  'applyInitialControl', 'initialControlPublicDispatch', 'localProvider']);
class ErrorFixture extends Error {
  constructor(code) {super(code); this.code = code;}
}
const unused = () => assert.fail('UnexpectedUnselectedRoute');

test('selected public connect forwards the exact raw input before any facade observation or copy', async () => {
  let observations = 0;
  const raw = new Proxy({}, {get() {observations++;}, ownKeys() {observations++;},
    getOwnPropertyDescriptor() {observations++;}, getPrototypeOf() {observations++;}});
  const client = Object.freeze({originalClient: true}), receiver = {};
  const route = make(unused, ErrorFixture, function(kind, input) {
    assert.equal(this, receiver); assert.equal(kind, 'connect'); assert.equal(input, raw);
    return Promise.resolve(client);
  }, Reflect.apply, receiver, unused);
  assert.equal(await route(raw), client);
  assert.equal(observations, 0);
});

test('selected Local intake refusal does not fall back to copying or a replacement provider', async () => {
  const original = Object.freeze(new Error('OriginalIntakeUnavailable'));
  const raw = new Proxy({}, {get() {assert.fail('NoRawGetter');}, ownKeys() {assert.fail('NoRawCopy');}});
  const route = make(unused, ErrorFixture, () => {throw original;}, Reflect.apply, {}, unused);
  await assert.rejects(route(raw), error => error === original);
});

test('undefined routing result preserves the original Remote selection without loading Local', async () => {
  const raw = {mode: 'remote', endpoint: 'https://host.example/', token: 'fixture'}, client = {};
  let routed = 0, connected = 0;
  const route = make(input => {connected++; assert.equal(input, raw); return client;},
    ErrorFixture, (kind, input) => {
      routed++; assert.equal(kind, 'connect'); assert.equal(input, raw); return undefined;
    }, Reflect.apply, {}, unused);
  assert.equal(await route(raw), client);
  assert.equal(routed, 1); assert.equal(connected, 1);
});

test('connection strings retain the SDK route and do not acquire a Local input scope', async () => {
  const options = {token: 'fixture'}, client = {};
  const route = make((input, supplied) => {
    assert.equal(input, 'actql://host.example/workspace'); assert.equal(supplied, options); return client;
  }, ErrorFixture, unused, Reflect.apply, {}, unused);
  assert.equal(await route('actql://host.example/workspace', options), client);
});

test('existing second-argument rejection precedes selected object routing', async () => {
  const raw = new Proxy({}, {get() {assert.fail('NoRawGetter');}});
  const route = make(unused, ErrorFixture, unused, Reflect.apply, {}, unused);
  await assert.rejects(route(raw, {}), {code: 'InvalidConnectionOptions'});
});
