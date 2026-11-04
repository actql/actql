import assert from 'node:assert/strict';
import test from 'node:test';
import {sourceAliasPublication, sourceAliasPublicationOriginal, splitSourceAliasProfile}
  from './source-alias-publication.mjs';
const cid = 'sha256:' + 'a'.repeat(64);
const entry = request => ({name: 'records', sourceRef: 'connector://declared/records',
  sourceViewContractCid: cid, schemaContractCid: cid, request});
function fixture() {
  const environment = {}, calls = [];
  const moon = {clientProgramCheckingEnvironmentCid: () => cid,
    clientProgramPreparePublicSourceEnvironment(owner, wire) {
      calls.push({owner, wire}); return {};
    }};
  return {environment, moon, calls, publish: aliases => sourceAliasPublication(moon, environment, aliases)};
}
test('publication borrows the installed immutable alias and request originals', () => {
  const aliases = splitSourceAliasProfile({queryAliases: [entry({paths: null, nested: {value: 1}})]}).queryAliases;
  const f = fixture(), publication = f.publish(aliases);
  assert.equal(publication.aliases, aliases);
  assert.equal(publication.aliases[0].request, aliases[0].request);
  assert.equal(f.calls[0].owner, f.environment);
  assert.deepEqual(JSON.parse(f.calls[0].wire).aliases, aliases);
  assert.ok(sourceAliasPublicationOriginal(f.moon, f.environment, publication));
  assert.equal(sourceAliasPublicationOriginal(f.moon, {}, publication), undefined);
});
test('manual mutable aliases still become isolated snapshots', () => {
  const input = [entry({nested: {value: 1}})], f = fixture(), publication = f.publish(input);
  input[0].request.nested.value = 2;
  assert.notEqual(publication.aliases, input);
  assert.equal(publication.aliases[0].request.nested.value, 1);
});
test('frozen outer metadata cannot hide mutable or executable request DATA', () => {
  const f = fixture(); let hooks = 0;
  const getter = Object.freeze(Object.defineProperty({}, 'x', {enumerable: true, get() {hooks++; return 1;}}));
  const proxy = new Proxy({}, {get() {hooks++; return 1;}});
  for (const request of [{nested: {value: 1}}, getter, proxy]) {
    const aliases = Object.freeze([Object.freeze(entry(request))]);
    assert.throws(() => f.publish(aliases), /InvalidSourceAliasConstruction|InvalidPublicSourcePublication/);
  }
  assert.equal(hooks, 0);
  assert.equal(f.calls.length, 0);
});

test('selector range borrows the same prepared publication Catalog exactly once', () => {
  const f = fixture(), prepared = Object.freeze({original: true}), calls = [];
  f.moon.clientProgramPreparePublicSourceEnvironment = (environment, wire) => {
    assert.equal(environment, f.environment);f.calls.push({owner: environment, wire});return prepared;
  };
  f.moon.clientProgramCheckSourceSelectorRange = () => assert.fail('No second Catalog');
  f.moon.clientProgramCheckPreparedSourceSelectorRange = (environment, original, registrations) => {
    assert.equal(environment, f.environment);assert.equal(original, prepared);
    assert.deepEqual(registrations, []);calls.push(original);return Object.freeze({original});
  };
  const publication = sourceAliasPublication(f.moon, f.environment, [], [], {
    selectorNamespace: {name: 'registrations', profilePaths: []}, installedSources: []});
  assert.equal(sourceAliasPublicationOriginal(f.moon, f.environment, publication).preparedEnvironment, prepared);
  assert.equal(f.calls.length, 1);assert.deepEqual(calls, [prepared]);
});

test('selector range preserves original refusal and never falls back to a fresh Catalog', () => {
  for (const missing of [false, true]) {
    const f = fixture(), original = new Error('OriginalPreparedCatalogRefusal');let calls = 0;
    f.moon.clientProgramCheckSourceSelectorRange = () => assert.fail('No independent Catalog fallback');
    if (!missing) f.moon.clientProgramCheckPreparedSourceSelectorRange = () => {calls++;throw original;};
    assert.throws(() => sourceAliasPublication(f.moon, f.environment, [], [], {
      selectorNamespace: {name: 'registrations', profilePaths: []}, installedSources: []}),
    missing ? /InvalidSourceSelectorNamespaceInstallation/u : error => error === original);
    assert.equal(f.calls.length, 1);assert.equal(calls, missing ? 0 : 1);
  }
});
