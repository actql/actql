import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

// Execute the actual Local observation statement with explicit owner ports.
// These caller tests do not instantiate a full Host or Common runtime.
const source = readFileSync(new URL('./embedded-local.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
const statements = [];
function visit(node) {
  if (node === null || typeof node !== 'object') return;
  if (node.type === 'VariableDeclaration' &&
      node.declarations.some(declaration => declaration.id.name === 'observeRun')) {
    statements.push(source.slice(node.start, node.end));
  }
  for (const child of Object.values(node)) {
    if (Array.isArray(child)) child.forEach(visit);
    else if (child && typeof child === 'object') visit(child);
  }
}
visit(ast);
assert.equal(statements.length, 1);
const names = ['principalId', 'namespaceId', 'authorityScopeCid', 'journal', 'moon',
  'control', 'store', 'inspectAuthorizedRunState', 'stateService', 'checkpoints',
  'dispatchOwner', 'modelResumeFlights', 'issueInstalledUnpublishedRunState', 'now',
  'projectRunObservation', 'clientOperationError'];
const compile = new Function(...names, `${statements[0]}; return observeRun;`);

function fixture({change = false, missing = false, conflict = false} = {}) {
  const ref = Object.freeze({namespaceId: 'namespace', authorityScopeCid: 'scope',
    runDefinitionCid: 'run'});
  const moon = {}, control = {runDefinitionRunId: definition => definition.id};
  const counts = {lookup: 0, probe: 0, publish: 0, store: 0, state: 0};
  let selected;
  const journal = {
    lookupRunDefinition(actual, requestControl, publicationControl) {
      assert.strictEqual(actual, ref); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control);
      counts.lookup++;
      return selected = Object.freeze({ref, revision: counts.lookup,
        runDefinition: Object.freeze({id: 'original-run'})});
    },
    observeRunCancellation(actual, requestControl, publicationControl, original) {
      assert.strictEqual(actual, ref); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control);
      assert.strictEqual(original, selected, 'The probe must receive the actual admitted frame');
      return () => {
        counts.probe++;
        return missing ? undefined : {revision: original.revision +
          (change && counts.probe === 1 ? 1 : 0)};
      };
    },
    publishRunState(original, state, requestControl, publicationControl) {
      assert.strictEqual(original, selected); assert.strictEqual(requestControl, moon);
      assert.strictEqual(publicationControl, control); counts.publish++;
      if (conflict && counts.publish === 1) {
        throw Object.assign(new Error('RunStateObservationChanged'), {code: 'RunStateObservationChanged'});
      }
      return JSON.stringify(state);
    },
  };
  const observe = compile('actor', ref.namespaceId, ref.authorityScopeCid, journal,
    moon, control, {async confirmCommittedIndex(actual) {
      assert.strictEqual(actual, ref); counts.store++; return {};
    }}, async () => {counts.state++; return {status: 'succeeded'};}, {}, undefined,
    {live: () => false}, new Map(), () => assert.fail('No unpublished state'),
    () => assert.fail('No unpublished clock'), () => {},
    code => Object.assign(new Error(code), {code}));
  return {counts, observe, ref, start: () => observe({ref, principalId: 'actor'})};
}

test('Local Run observation reuses its original admission for the post-Store probe', async () => {
  const f = fixture();
  assert.deepEqual(await f.start(), {status: 'succeeded'});
  assert.deepEqual(f.counts, {lookup: 1, probe: 1, publish: 1, store: 1, state: 1});
  await f.start();
  assert.equal(f.counts.lookup, 2, 'A new observation acquires its own current original');
});

test('Local Run observation retries changed control and final publication conflicts', async () => {
  for (const options of [{change: true}, {conflict: true}]) {
    const f = fixture(options);
    assert.deepEqual(await f.start(), {status: 'succeeded'});
    assert.equal(f.counts.lookup, 2); assert.equal(f.counts.probe, 2);
    assert.equal(f.counts.publish, options.change ? 1 : 2);
  }
});

test('Local Run observation preserves missing-row exhaustion and entry denial', async () => {
  const missing = fixture({missing: true});
  await assert.rejects(missing.start, {message: 'RunStateObservationUnstable'});
  assert.equal(missing.counts.lookup, 8); assert.equal(missing.counts.publish, 0);
  const denied = fixture();
  await assert.rejects(() => denied.observe({ref: denied.ref, principalId: 'foreign'}),
    {code: 'RunStateAccessDenied'});
  assert.equal(denied.counts.lookup, 0); assert.equal(denied.counts.store, 0);
});
