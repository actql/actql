import assert from 'node:assert/strict';
import test from 'node:test';
import {aliasRequestGeometry, snapshotAliasRequest, sourceAliasIdentityRow} from './source-alias-request.mjs';
import {splitSourceAliasProfile} from './source-alias-publication.mjs';

const alias = request => ({name: 'inventory', sourceRef: 'connector://source/items#view',
  sourceViewContractCid: 'sha256:' + '1'.repeat(64), schemaContractCid: 'sha256:' + '2'.repeat(64),
  ...(request === undefined ? {} : {request})});

test('optional request preserves absent and explicit empty DATA without adding selectors', () => {
  const [absent, empty] = splitSourceAliasProfile({queryAliases: [alias(), alias({})]}).queryAliases;
  assert.equal(Object.hasOwn(absent, 'request'), false);
  assert.deepEqual(empty.request, {});
  assert.equal(sourceAliasIdentityRow(absent).length, 4);
  assert.equal(sourceAliasIdentityRow(empty).length, 5);
});

test('request snapshot retains exact nested DATA independently of caller mutation', () => {
  const input = {paths: null, glob: null, selector: {names: ['a', 'b'], active: true}};
  const owned = splitSourceAliasProfile({queryAliases: [alias(input)]}).queryAliases[0];
  input.selector.names[0] = 'changed'; input.paths = ['other'];
  assert.deepEqual(owned.request.selector.names, ['a', 'b']);
  assert.equal(owned.request.paths, null);
  assert.ok(Object.isFrozen(owned.request.selector.names));
  assert.deepEqual(snapshotAliasRequest({b: 2, a: 1}), snapshotAliasRequest({a: 1, b: 2}));
});

test('nonobject request roots and executable or cyclic values refuse', () => {
  const cycle = {}; cycle.self = cycle;
  for (const value of [null, [], 1, 'x', true, {x: undefined}, {x: NaN}, {x: -0}, cycle,
    {get x() {assert.fail('getter must not execute');}}, new Proxy({}, {})]) {
    assert.throws(() => snapshotAliasRequest(value), /InvalidPublicSourcePublication/);
  }
});

test('direct reference slots cannot acquire authority through constant request DATA', () => {
  for (const value of [{x: {$param: 'p'}}, {x: {$binding: 1}}]) {
    assert.throws(() => snapshotAliasRequest(value), /InvalidPublicSourcePublication/);
  }
  assert.deepEqual(snapshotAliasRequest({x: {nested: {$param: 'business'}}}),
    {x: {nested: {$param: 'business'}}});
});

test('request identity includes explicit values and preserves prototype-looking DATA keys', () => {
  const request = JSON.parse('{"__proto__":{"a":1},"constructor":"value"}');
  const owned = snapshotAliasRequest(request);
  assert.ok(Object.hasOwn(owned, '__proto__'));
  assert.equal(Object.getPrototypeOf(owned), Object.prototype);
  assert.notDeepEqual(sourceAliasIdentityRow(alias({x: 1})), sourceAliasIdentityRow(alias({x: 2})));
});

test('request scan bounds retained nodes, text, and nesting before snapshot', () => {
  assert.deepEqual(aliasRequestGeometry({paths: null, glob: null}),
    {nodes: 3n, entries: 2n, units: 9n, depth: 1n});
  let value = {};
  for (let i = 0; i < 65; i++) value = {x: value};
  assert.throws(() => snapshotAliasRequest(value), /InvalidPublicSourcePublication/);
  assert.throws(() => snapshotAliasRequest({x: 'x'.repeat(1048577)}), /InvalidPublicSourcePublication/);
});
