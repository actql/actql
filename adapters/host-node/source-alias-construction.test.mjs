import assert from 'node:assert/strict';
import test from 'node:test';
import {captureSourceAliasConstruction,
  sourceAliasIdentityConstructionGeometry as identityGeometry,
  sourceAliasDataGeometry} from './source-alias-construction.mjs';
import {splitSourceAliasProfile} from './source-alias-publication.mjs';
import {sourceAliasIdentityRow} from './source-alias-request.mjs';
import {canonicalJson} from './local-account-config.mjs';
import {sourceJsonWireGeometry} from './installed-source-construction-geometry.mjs';

const alias = request => ({name: 'records', sourceRef: 'connector://local/records#view',
  sourceViewContractCid: 'sha256:' + '1'.repeat(64), schemaContractCid: 'sha256:' + '2'.repeat(64), request});
const owned = request => splitSourceAliasProfile({queryAliases: [alias(request)]}).queryAliases;
const sum = quantity => {
  for (const name of ['nodes', 'text', 'wire']) {
    assert.equal(quantity[name], quantity.retained[name] + quantity.workspace[name]);
    assert.ok(quantity[name] >= 0n);
  }
};

test('profile wire facts are observed without native parse or stringify', () => {
  const wire = JSON.stringify({version: 'sample', queryAliases: [alias({x: '\\\"日本語😀'})]});
  const parse = JSON.parse, stringify = JSON.stringify;
  let facts;
  try {
    JSON.parse = JSON.stringify = () => assert.fail('No constructor in observation');
    facts = sourceJsonWireGeometry(wire, true);
  } finally {JSON.parse = parse; JSON.stringify = stringify;}
  assert(facts.nodes > 1n && facts.units > 0n);
});

test('profile wire facts preserve payload whitespace escapes numbers and malformed prefixes', () => {
  const compact = '{"s":" \\t日本語😀 ","n":-1.25e+3,"a":[true,null]}';
  const spaced = ' \t\r\n{\n "s" : " \\t日本語😀 " , "n" : -1.25e+3 , "a": [true , null]}\n';
  const a = sourceJsonWireGeometry(compact, true), b = sourceJsonWireGeometry(spaced, true);
  assert.deepEqual(JSON.parse(spaced), JSON.parse(compact));
  assert.equal(a.nodes, b.nodes); assert.equal(a.units, b.units);
  assert.equal(sourceJsonWireGeometry('\u00a0{}', true).units, 3n);
  for (const wire of ['', ' \t[\n', ' { "x": \r', ' [null,\n', '"unterminated \t\n', '"\\u005']) {
    assert.throws(() => JSON.parse(wire), SyntaxError);
    assert(sourceJsonWireGeometry(wire, true).nodes >= 1n);
  }
});

test('immutable identity DATA scan refuses hooks and mutable descendants before a quote', () => {
  assert.deepEqual(sourceAliasDataGeometry(Object.freeze({a: Object.freeze(['b'])})),
    {nodes: 3n, entries: 2n, units: 2n, weighted: 4n, depth: 2n, jsonBytes: 11n});
  for (const value of [[], Object.freeze([{x: 1}]), Object.freeze(new Proxy({}, {})),
    Object.freeze({get x() {assert.fail('No accessor evaluation');}})]) {
    assert.throws(() => sourceAliasDataGeometry(value), /InvalidSourceAliasConstruction/);
  }
});

test('identity quote includes exact row and existing canonical request hash preimages', () => {
  const aliases = owned({x: '\u0344日本語😀\\"\n'.repeat(100), nested: {z: [null, true, 123]}});
  const quantity = identityGeometry(aliases);
  sum(quantity);
  const exact = JSON.stringify(['actql-installed-query-alias-generation/0.1', aliases.map(sourceAliasIdentityRow)]);
  const canonical = canonicalJson(aliases);
  assert.ok(quantity.bounds.identityWireUnits >= BigInt(exact.length));
  assert.ok(quantity.bounds.canonicalOutputUnits >= BigInt(canonical.length));
  assert.ok(quantity.workspace.wire >= BigInt(Buffer.byteLength(exact) + Buffer.byteLength(canonical)));
  assert.equal(quantity.retained.text, 142n, 'only identity CID text escapes this stage');
  const nested = identityGeometry(owned({x: {x: {x: 'payload'}}}));
  const flat = identityGeometry(owned({x: 'payload'}));
  assert.ok(nested.workspace.text > flat.workspace.text);
});

test('construction captures exact reader/runtime methods and reserves before projection', () => {
  const events = [], token = Object.freeze({opaque: true});
  const moon = {clientProgramInstalledSourceConstructionCapacity(...values) {
    assert.equal(this, moon); events.push(['quote', values]); return {$tag: 1, _0: token};
  }};
  const reader = {prepareNativeInput(projection) {
    assert.equal(this, reader); assert.ok(Object.isFrozen(projection));
    assert.equal(projection.capacity(), token); events.push(['reserve']); return projection.project();
  }};
  const construct = captureSourceAliasConstruction(reader, moon);
  reader.prepareNativeInput = moon.clientProgramInstalledSourceConstructionCapacity = () => assert.fail('Replacement method');
  const quantity = {retained:{nodes:1n,text:2n,wire:0n},workspace:{nodes:3n,text:4n,wire:0n}}, result = Object.freeze({original: true});
  assert.equal(construct(quantity, () => {events.push(['project']); return result;}), result);
  assert.deepEqual(events.map(value => value[0]), ['quote', 'reserve', 'project']);
  assert.deepEqual(events[0][1], [quantity.retained.nodes, quantity.retained.text, quantity.retained.wire,
    quantity.workspace.nodes, quantity.workspace.text, quantity.workspace.wire]);
});

test('funding refusal never enters snapshot and absent owner stays a standalone diagnostic', () => {
  const refusal = new Error('Original reserve refusal');
  const moon = {clientProgramInstalledSourceConstructionCapacity() {return {$tag: 1, _0: {}};}};
  const reader = {prepareNativeInput(projection) {projection.capacity(); throw refusal;}};
  const construct = captureSourceAliasConstruction(reader, moon);
  assert.throws(() => construct({retained:{nodes:1n,text:0n,wire:0n},workspace:{nodes:1n,text:0n,wire:0n}}, () => assert.fail('Unfunded snapshot')), error => error === refusal);
  assert.throws(() => captureSourceAliasConstruction(reader, {}), /InvalidSourceAliasConstruction/);
  const result = Object.freeze({diagnostic: true});
  assert.equal(captureSourceAliasConstruction(undefined, undefined)(undefined, () => result), result);
});

// Real shared identity loader with explicit reader/quote ports. These tests
// establish original-wire ordering and refusal, not Core ledger admission.
async function identityFixture(request, {refuseStage, onReserve} = {}) {
  const {installedSourceIdentity} = await import('./installed-source.mjs');
  const {createInstalledConnectorTable} = await import('./installed-connectors.mjs');
  const profile = {version: 'actql-installed-alias-construction-fixture/0.1', queryAliases: [alias(request)]};
  const wire = JSON.stringify(profile), events = [], refusal = new Error('Original alias reserve refusal');
  let seen, stage = 0;
  const connectorTable = createInstalledConnectorTable([{name: 'alias_fixture', source: {
    profileVersion: profile.version, load: async () => ({
      check: value => value,
      identityParts(value) {events.push('identityParts'); seen = value; return [value];},
      load() {assert.fail('Identity never loads a Source');},
    }),
  }}]);
  const moon = {clientProgramInstalledSourceConstructionCapacity(...values) {
    events.push('quote'); return {$tag: 1, _0: Object.freeze({values})};
  }};
  const reader = {
    readJson() {assert.fail('Profile must not parse before its constructor quote');},
    readText() {events.push('text'); return wire;},
    prepareProfile(text, project) {
      assert.equal(text, wire);
      const construct = project => reader.prepareNativeInput(Object.freeze({
        capacity() {events.push('quote'); return Object.freeze({nativeProfile: true});}, project}));
      return Object.freeze({value: construct(project), construct});
    },
    prepareNativeInput(projection) {
      projection.capacity(); events.push('reserve');
      const index = stage++; onReserve?.(index);
      if (refuseStage === index) throw refusal;
      events.push('project'); return projection.project();
    },
  };
  return {events, refusal, seen: () => seen,
    run: () => installedSourceIdentity('/explicit/alias-profile.json', {connectorTable, configurationReader: reader, moon})};
}

test('shared installed identity parses immutable original text only after the same reader reserve', async () => {
  const request = {filter: {name: 'original'}};
  const first = await identityFixture(request, {onReserve() {request.filter.name = 'changed';}});
  const identity = await first.run();
  const second = await identityFixture({filter: {name: 'original'}});
  assert.equal(identity, await second.run());
  assert.deepEqual(first.events, ['text', 'quote', 'reserve', 'project', 'identityParts', 'quote', 'reserve', 'project']);
  assert.equal(first.seen().queryAliases[0].request.filter.name, 'original');
  assert.ok(Object.isFrozen(first.seen().queryAliases[0].request.filter));
});

test('shared installed identity preserves exact profile and identity-stage funding refusals', async () => {
  for (const refuseStage of [0, 1]) {
    const fixture = await identityFixture({name: 'original'}, {refuseStage});
    await assert.rejects(fixture.run(), error => error === fixture.refusal);
    assert.equal(fixture.events.filter(value => value === 'project').length, refuseStage);
    assert.equal(fixture.events.includes('identityParts'), refuseStage === 1);
  }
});

test('aggregate quote borrows original immutable request trees without charging another copy', async () => {
  const {sourceAliasCollectionConstructionGeometry: collectionGeometry,
    sourceAliasBorrowedGeometry} = await import('./source-alias-construction.mjs');
  const small = Object.freeze([Object.freeze({queryAliases: owned({x: 'a'})})]);
  const large = Object.freeze([Object.freeze({queryAliases: owned({x: 'a'.repeat(10000)})})]);
  assert.deepEqual(collectionGeometry(small), collectionGeometry(large));
  const first = collectionGeometry(small);
  const second = collectionGeometry(Object.freeze([...small, ...large]));
  assert.equal(second.bounds.aliasCount, 2n);
  assert.ok(second.nodes > first.nodes);
  assert.equal(second.text, 0n); assert.equal(second.wire, 0n);
  assert.equal(small[0].queryAliases[0].request.x, 'a');
  for (const aliases of [Object.freeze([Object.freeze({...alias({}), get request() {
    assert.fail('Borrowed validation must not invoke getters');
  }})]), Object.freeze([new Proxy({}, {})]), Object.freeze([Object.freeze(alias({x: 1}))])]) {
    assert.throws(() => sourceAliasBorrowedGeometry(aliases), /InvalidSourceAliasConstruction/);
  }
  const source = Object.freeze({get queryAliases() {assert.fail('No inventory getter');}});
  assert.throws(() => collectionGeometry(Object.freeze([source])), /InvalidSourceAliasConstruction/);
});


test('borrowed DATA computes exact UTF8 wire size without serializing a publication', () => {
  const values = [null, true, false, 1e+25, 1e-8, 1.2345, '\b\t\n\f\r\u0000\\"日本語😀'];
  const value = Object.freeze({empty: Object.freeze({}), values: Object.freeze(values)});
  const expected = BigInt(Buffer.byteLength(JSON.stringify(value)));
  const original = JSON.stringify;
  try {
    JSON.stringify = () => assert.fail('No whole DATA serialization for geometry');
    assert.equal(sourceAliasDataGeometry(value).jsonBytes, expected);
  } finally {JSON.stringify = original;}
});


test('immutable borrowed aliases keep the same request nesting bound as mutable snapshots', async () => {
  const {sourceAliasBorrowedGeometry} = await import('./source-alias-construction.mjs');
  let request = Object.freeze({});
  for (let index = 0; index < 65; index++) request = Object.freeze({x: request});
  const aliases = Object.freeze([Object.freeze(alias(request))]);
  assert.throws(() => sourceAliasBorrowedGeometry(aliases), /InvalidPublicSourcePublication/);
});
