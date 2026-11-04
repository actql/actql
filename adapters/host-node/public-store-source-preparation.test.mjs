import assert from 'node:assert/strict';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
const selected = name => process.env.ACTQL_TEST_SOURCE_PREPARATION_ROOT === undefined
  ? new URL(name, import.meta.url)
  : pathToFileURL(process.env.ACTQL_TEST_SOURCE_PREPARATION_ROOT + '/adapters/host-node/' + name);
const {installNodePublicSourcePreparation} = await import(selected('public-source-preparation.mjs'));
const {installNodeClientProgramPreparation} = await import(selected('client-program-preparation.mjs'));
const {sourceAliasPublication, sourceAliasPublicationOriginal,
  retireSourceAliasPublicationOriginal} = await import(selected('source-alias-publication.mjs'));

const cid = digit => `sha256:${digit.repeat(64)}`;
const environment = Object.freeze({generation: cid('a')});
const target = () => ({name: 'gcs.objects', targetRef: 'connector://storage/objects',
  installationBindingCid: cid('b'), installationOwnerCid: cid('c')});
const publication = () => ({environmentCid: cid('a'), aliases: [], storeTargets: [target()]});

function ownerDouble() {
  const calls = [], result = Object.freeze({prepared: true});
  const originals = new WeakMap();
  const moon = {
    clientProgramCheckingEnvironmentCid: value => value.generation,
    clientProgramPreparePublicSourceEnvironment: (owner, wire) => {
      calls.push({kind: 'admit', owner, wire});
      const prepared = Object.freeze({}); originals.set(prepared, owner); return prepared;
    },
    clientProgramPublicSourceEnvironmentMatches: (prepared, owner) => originals.get(prepared) === owner,
    clientProgramSourcePublicationValid: (owner, wire) => {
      calls.push({kind: 'legacy-validate', owner, wire}); return true;
    },
    clientProgramPrepareSourceComputationInPublicEnvironment: (...args) => {
      calls.push({kind: 'source', args}); return {pure: result};
    },
    clientProgramSourceComputationPure: value => value.pure,
    clientProgramSourceComputationEffect: value => value.effect,
    clientProgramPrepareEffectComputationInPublicEnvironment: (...args) => {
      calls.push({kind: 'effect', args}); return result;
    },
    clientProgramPreparePublicSourceComputationWithParameters: (...args) => {
      calls.push({kind: 'legacy-source', args}); return {pure: result};
    },
    clientProgramPreparePublishedEffectComputationWithParameters: (...args) => {
      calls.push({kind: 'legacy-effect', args}); return result;
    },
  };
  return {moon, calls, result};
}

// These are JS-to-Common wiring controls. The actual Common original-pair
// validator has separate source-qualified tests; this double grants no Ref.
test('STORE Source metadata reaches its existing owner unchanged and snapshotted', () => {
  const {moon, calls, result} = ownerDouble(), selected = publication();
  const wire = JSON.stringify(selected), evidence = [Object.freeze({original: true})];
  const prepared = installNodePublicSourcePreparation({moon, environment,
    publication: selected, allowEffects: true, effectEvidence: evidence});
  selected.storeTargets[0].targetRef = 'connector://foreign/changed';
  selected.storeTargets.push(target()); evidence.push({foreign: true});
  assert.deepEqual(prepared.prepare({document: 'SELECT 1', format: 'sql',
    declarations: undefined, supplied: undefined}), {kind: 'effect_free', outcome: result});
  assert.equal(prepared.prepareEffect({document: '{}', format: 'json', supplied: '{}'}), result);
  const preparedEnvironment = calls[1].args[3];
  assert.equal(moon.clientProgramPublicSourceEnvironmentMatches(preparedEnvironment, environment), true);
  assert.deepEqual(calls, [
    {kind: 'admit', owner: environment, wire},
    {kind: 'source', args: ['SELECT 1', 'sql', environment, preparedEnvironment, undefined, undefined,
      true, [evidence[0]]]},
    {kind: 'effect', args: ['{}', 'json', environment, preparedEnvironment, '{}', [evidence[0]]]},
  ]);
});

test('STORE Source metadata requires the Common validator even for an unused target', () => {
  for (const absent of [false, true]) {
    const {moon, calls} = ownerDouble();
    if (absent) delete moon.clientProgramPreparePublicSourceEnvironment;
    else moon.clientProgramPreparePublicSourceEnvironment = () => undefined;
    assert.throws(() => installNodePublicSourcePreparation({moon, environment,
      publication: publication()}), {name: 'TypeError', message: 'InvalidPublicSourcePublication'});
    assert.equal(calls.length, 0, 'No lowering or Effect preparation before metadata admission');
  }
});

test('STORE Source metadata retains original bounds and closed outer shape', () => {
  const {moon, calls} = ownerDouble();
  for (const value of [null, {}, 'targets', Array.from({length: 1025}, target)]) {
    assert.throws(() => installNodePublicSourcePreparation({moon, environment,
      publication: {...publication(), storeTargets: value}}), TypeError);
  }
  assert.throws(() => installNodePublicSourcePreparation({moon, environment,
    publication: {...publication(), guessedTarget: target()}}), TypeError);
  assert.equal(calls.length, 0);
});

test('STORE empty publication preserves absence and does not grant Effects', () => {
  const {moon, calls} = ownerDouble();
  const selected = {...publication(), storeTargets: []};
  const prepared = installNodePublicSourcePreparation({moon, environment, publication: selected});
  assert.throws(() => prepared.prepareEffect({document: '{}', format: 'json'}),
    {code: 'ClientProgramUnsupported'});
  assert.deepEqual(calls, [{kind: 'admit', owner: environment, wire: JSON.stringify(selected)}]);
});

test('STORE metadata coexists with existing UPDATE and table publication through one validator', () => {
  const {moon, calls} = ownerDouble();
  const selected = {...publication(), updateTargets: [target()], tableWrites: []};
  installNodePublicSourcePreparation({moon, environment, publication: selected});
  assert.deepEqual(calls, [{kind: 'admit', owner: environment, wire: JSON.stringify(selected)}]);
});

test('public Environment original admits once across independent queries and JSON Effect preparation', () => {
  const {moon, calls} = ownerDouble();
  const original = sourceAliasPublication(moon, environment, [], [], {storeTargets: [target()]});
  const wire = JSON.stringify(original);
  const prepared = installNodePublicSourcePreparation({moon, environment,
    publication: original, allowEffects: true});
  prepared.prepare({document: 'SELECT 1 AS id', format: 'sql'});
  prepared.prepare({document: 'SELECT 2 AS id', format: 'sql'});
  prepared.prepareEffect({document: '{}', format: 'json'});
  assert.equal(calls.filter(call => call.kind === 'admit').length, 1);
  assert.equal(calls.filter(call => call.kind.startsWith('legacy-')).length, 0);
  assert.equal(calls[0].wire, wire);
  assert.equal(JSON.stringify(original), wire, 'No private preparation in public bytes');
  const queryCalls = calls.filter(call => ['source', 'effect'].includes(call.kind));
  assert.equal(queryCalls.length, 3);
  assert(queryCalls.every(call => call.args[2] === environment &&
    call.args[3] === queryCalls[0].args[3]));
});

test('public Environment association does not follow copied declarations or foreign runtime/Environment', () => {
  const {moon, calls} = ownerDouble();
  const original = sourceAliasPublication(moon, environment);
  const retained = sourceAliasPublicationOriginal(moon, environment, original);
  assert(retained);
  assert.equal(sourceAliasPublicationOriginal({...moon}, environment, original), undefined);
  assert.equal(sourceAliasPublicationOriginal(moon, {...environment}, original), undefined);
  assert.equal(sourceAliasPublicationOriginal(moon, environment, {...original}), undefined);
  assert.equal(sourceAliasPublicationOriginal(undefined, undefined, undefined), undefined);
  retireSourceAliasPublicationOriginal(undefined, undefined, undefined);
  installNodePublicSourcePreparation({moon, environment, publication: {...original}});
  assert.equal(calls.filter(call => call.kind === 'admit').length, 2,
    'A copied declaration receives its own complete admission, not the old association');
  assert.throws(() => installNodePublicSourcePreparation({moon, environment,
    publication: {...original}, getPreparedSourceEnvironment: () => retained.preparedEnvironment}),
  {name: 'TypeError', message: 'InvalidPublicSourcePublication'});
  assert.equal(calls.filter(call => call.kind === 'admit').length, 2,
    'An impossible original pairing refuses without another admission');
});

test('public Environment lifecycle refuses a retired or replaced Host slot without re-admission', () => {
  const {moon, calls} = ownerDouble();
  const original = sourceAliasPublication(moon, environment);
  const retained = sourceAliasPublicationOriginal(moon, environment, original);
  let slot = retained.preparedEnvironment;
  const closing = new Error('Host closing');
  const prepared = installNodePublicSourcePreparation({moon, environment, publication: original,
    getPreparedSourceEnvironment() {if (slot === undefined) throw closing; return slot;}});
  prepared.prepare({document: 'SELECT 1', format: 'sql'});
  slot = Object.freeze({});
  assert.throws(() => prepared.prepare({document: 'SELECT 2', format: 'sql'}),
    {name: 'TypeError', message: 'InvalidPublicSourcePreparationEnvironment'});
  slot = undefined;
  assert.throws(() => prepared.prepare({document: 'SELECT 3', format: 'sql'}), error => error === closing);
  retireSourceAliasPublicationOriginal({...moon}, environment, original);
  assert.equal(sourceAliasPublicationOriginal(moon, environment, original), retained);
  retireSourceAliasPublicationOriginal(moon, environment, original);
  assert.equal(sourceAliasPublicationOriginal(moon, environment, original), undefined);
  assert.equal(moon.clientProgramPublicSourceEnvironmentMatches(retained.preparedEnvironment, environment), true,
    'Cutting one association does not invalidate another legitimate holder of pure facts');
  assert.equal(calls.filter(call => call.kind === 'admit').length, 1);
  assert.equal(calls.filter(call => call.kind === 'source').length, 1);
});

test('public Environment consumer rejects a foreign prepared original before query preparation', () => {
  const {moon, calls} = ownerDouble();
  moon.clientProgramPublicSourceEnvironmentMatches = () => false;
  assert.throws(() => installNodePublicSourcePreparation({moon, environment, publication: publication()}),
    {name: 'TypeError', message: 'InvalidPublicSourcePublication'});
  assert.equal(calls.filter(call => call.kind === 'admit').length, 1);
  assert.equal(calls.filter(call => ['source', 'effect'].includes(call.kind)).length, 0);
});

test('retiring one public Environment consumer cuts its aliases without invalidating another holder', () => {
  const {moon, calls} = ownerDouble();
  const original = sourceAliasPublication(moon, environment);
  const retained = sourceAliasPublicationOriginal(moon, environment, original);
  let currentReads = 0;
  const selected = installNodePublicSourcePreparation({moon, environment,
    publication: original, allowEffects: true, getPreparedSourceEnvironment() {
      currentReads++; return retained.preparedEnvironment;
    }});
  const sibling = installNodePublicSourcePreparation({moon, environment,
    publication: original, allowEffects: true});
  selected.prepare({document: 'SELECT 1', format: 'sql'});
  const readsBeforeRetire = currentReads;
  selected.retireSourceEnvironment();
  selected.retireSourceEnvironment();
  assert.throws(() => selected.prepare({document: 'SELECT 2', format: 'sql'}),
    {message: 'InvalidPublicSourcePreparationEnvironment'});
  assert.throws(() => selected.prepareEffect({document: '{}', format: 'json'}),
    {message: 'InvalidPublicSourcePreparationEnvironment'});
  assert.equal(currentReads, readsBeforeRetire, 'Retirement does not call the released Host slot');
  assert.equal(calls.filter(call => ['source', 'effect'].includes(call.kind)).length, 1);
  sibling.prepare({document: 'SELECT 3', format: 'sql'});
  assert.equal(calls.filter(call => call.kind === 'admit').length, 1);
  assert.equal(sourceAliasPublicationOriginal(moon, environment, original), retained);
  assert.equal(calls.at(-1).args[3], retained.preparedEnvironment);
});

test('public Environment program factory shares publication facts without caching parameter-bound Programs', async () => {
  const {moon, calls} = ownerDouble(); let ordinal = 0;
  Object.assign(moon, {
    clientProgramPrepareEffectFreeWithParameters() {assert.fail('Request wrapper must not compile again');},
    clientProgramPrepareEffectComputationWithParameters() {assert.fail('No legacy Effect fallback');},
    clientProgramPrepareSourceComputationInPublicEnvironment: (...args) => {
      calls.push({kind: 'source', args}); return {pure: {ready: Object.freeze({ordinal: ++ordinal})}};
    },
    clientProgramPrepareEffectComputationInPublicEnvironment: (...args) => {
      calls.push({kind: 'effect', args}); return {ready: Object.freeze({ordinal: ++ordinal})};
    },
  });
  const original = sourceAliasPublication(moon, environment);
  const published = installNodePublicSourcePreparation({moon, environment,
    publication: original, allowEffects: true});
  const request = {kind: 'aql', input: {text: 'SELECT @id AS id', format: 'sql',
    parameterDeclarations: {id: {type: 'number'}}}, parameters: {id: 1}};
  const secondRequest = {...request, parameters: {id: 2}};
  const firstOriginal = published.prepare({document: request.input.text, format: 'sql',
    declarations: '{"id":{"type":"number"}}', supplied: '{"id":1}'}).outcome.ready;
  const secondOriginal = published.prepare({document: request.input.text, format: 'sql',
    declarations: '{"id":{"type":"number"}}', supplied: '{"id":2}'}).outcome.ready;
  const effectDocument = {
    version: 'actql/0.1', id: 'json-update-original', stages: [{id: 'apply', inputs: {},
      steps: [{values: {schema: {id: {type: 'string', nullable: false},
        name: {type: 'string', nullable: false}}, rows: [{id: 'original-id', name: 'Ada'}]}, as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id', 'name']}},
      effects: {save: {update: {target: 'connector://crm/account', mapping: 'mapping:crm.account.0.v1',
        from: {result: 'rows'}, id: 'id', set: {Name: {field: 'name'}}}}}}],
    results: {updates: {from: {stage: 'apply', result: 'rows'}}}};
  const effectRequest = {kind: 'program', parameters: null, input: effectDocument};
  const effectOriginal = published.prepareEffect({document: JSON.stringify(effectDocument), format: 'json'}).ready;
  // Explicit already-funded originals isolate the current Request wrapper.
  // This port neither parses input nor copies the former compiler recipe.
  const funded = new WeakMap([
    [request, {kind: 'effect_free', prepared: firstOriginal,
      originalInputs: {environment, parameters: '{"id":1}'}}],
    [secondRequest, {kind: 'effect_free', prepared: secondOriginal,
      originalInputs: {environment, parameters: '{"id":2}'}}],
    [effectRequest, {kind: 'effectful', prepared: effectOriginal, originalInputs: {environment}}],
  ]);
  const requests = [];
  const prepare = installNodeClientProgramPreparation({moon, environment, allowEffects: true,
    async getFundedPreparation(selected, owner) {
      assert.strictEqual(owner, environment); assert(funded.has(selected)); requests.push(selected);
      return funded.get(selected);
    }});
  const first = await prepare(request), second = await prepare(secondRequest);
  assert.strictEqual(first, firstOriginal); assert.strictEqual(second, secondOriginal);
  assert.notStrictEqual(first, second);
  assert.equal(prepare.originalInputs(first).parameters, '{"id":1}');
  assert.equal(prepare.originalInputs(second).parameters, '{"id":2}');
  const effect = await prepare(effectRequest);
  assert.strictEqual(effect, effectOriginal); assert.equal(prepare.kindOf(effect), 'effectful');
  assert.deepEqual(requests, [request, secondRequest, effectRequest]);
  assert.equal(calls.filter(call => call.kind === 'admit').length, 1);
  assert.equal(calls.filter(call => call.kind.startsWith('legacy-')).length, 0);
  const entries = calls.filter(call => ['source', 'effect'].includes(call.kind));
  assert.equal(entries.length, 3);
  assert(entries.every(call => call.args[3] === entries[0].args[3]));
  assert.deepEqual(entries.slice(0, 2).map(call => call.args[5]), ['{"id":1}', '{"id":2}']);
  const absentRequest = {kind: 'program', parameters: null, input: effectDocument};
  const absentOriginal = Object.freeze({absent: true}); let absentRequests = 0;
  const withoutPublication = installNodeClientProgramPreparation({moon, environment, allowEffects: true,
    async getFundedPreparation(selected, owner) {
      assert.strictEqual(selected, absentRequest); assert.strictEqual(owner, environment); absentRequests++;
      return {kind: 'effectful', prepared: absentOriginal, originalInputs: {environment}};
    }});
  assert.strictEqual(await withoutPublication(absentRequest), absentOriginal);
  assert.equal(withoutPublication.kindOf(absentOriginal), 'effectful');
  assert.equal(calls.filter(call => call.kind === 'admit').length, 1,
    'The Request wrapper cannot invent a public Environment for an absent publication');
  const beforeRetirement = calls.length, beforeRequests = requests.length;
  prepare.retireReferences(); prepare.retireReferences();
  await assert.rejects(prepare(request), {code: 'ClientProgramPreparationFailure'});
  await assert.rejects(prepare(effectRequest), {code: 'ClientProgramPreparationFailure'});
  assert.equal(calls.length, beforeRetirement); assert.equal(requests.length, beforeRequests,
    'Closed consumers cannot re-enter the released Request port');
  assert.strictEqual(await withoutPublication(absentRequest), absentOriginal);
  assert.equal(absentRequests, 2);
  withoutPublication.retireReferences();
  await assert.rejects(withoutPublication(absentRequest), {code: 'ClientProgramPreparationFailure'});
  assert.equal(absentRequests, 2);
});
