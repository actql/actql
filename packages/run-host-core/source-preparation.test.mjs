import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import * as host from './index.mjs';

const environmentWire = readFileSync(new URL('../sdk/fixtures/values.environment.json', import.meta.url), 'utf8').trimEnd();
const evidenceCid = JSON.parse(environmentWire).evidence_bundle_cid;
const environment = () => host.admitEnvironment(environmentWire, evidenceCid, {rela: true});
// The independently pinned empty fixture has no provider aliases or grants.
const publication = JSON.stringify({environmentCid: evidenceCid, aliases: []});
const limits = {maxWireBytes: 65536, maxNodes: 8192, maxDepth: 64};
const scope = 'sha256:' + 'a'.repeat(64);
const intent = (text = 'SELECT 1 AS n', format = 'sql', parameters = null, declarations) =>
  host.prepareSubmittedIntent(JSON.stringify({kind: 'aql', input: {text, format,
    ...(declarations === undefined ? {} : {parameterDeclarations: declarations})}, parameters}), limits);

for (const format of ['sql', 'aql-text']) test(`same-ABI ${format} keeps source identity through compile and request`, () => {
  const original = intent('SELECT 1 AS n', format);
  const selected = host.prepareSourceProgram(original, environment(), publication);
  assert.equal(selected.kind, 'effect_free');
  assert.strictEqual(selected.originalIntent, original);
  const compiled = host.compileTasks(selected.prepared);
  assert.deepEqual(host.taskResultDefinitions(selected.prepared, compiled).map(result => result.name), ['main']);
  const request = host.prepareSourceRequest(selected.prepared, original, scope, format);
  assert.equal(host.requestFields(request).callerInputIntentCid, host.submittedIntentFacts(original).cid);
  assert.equal(host.requestRelation(request, host.prepareTaskRequest(selected.prepared, compiled, scope, format)), 'same_request');
  assert.deepEqual(host.sourceProgramSourceInput(selected.prepared), {document: 'SELECT 1 AS n', format});
  assert.throws(() => host.compileEffect(selected.prepared), /ForeignRunHostHandle/u);
});

test('original source survives saved metadata and fresh local preparation without replacing request identity', () => {
  const original = intent('/*😀*/\r\nSELECT @n AS n', 'sql', {n: 3}, {n: {type: 'number'}});
  const env = environment();
  const selected = host.prepareSourceProgram(original, env, publication);
  const saved = host.sourceProgramOriginals(selected.prepared);
  assert(Object.isFrozen(saved));
  assert.equal(saved.primaryResultRecipe, 'public-main');
  assert.equal(saved.intentWire, host.submittedIntentFacts(original).wire);
  const request = host.prepareSourceRequest(selected.prepared, original, scope, 'saved');
  const restored = host.restoreSourceProgram(JSON.parse(JSON.stringify(saved)), environment());
  const restoredRequest = host.admitSourceRequestFields(restored.prepared, restored.originalIntent, host.requestFields(request));
  assert.equal(host.requestRelation(restoredRequest, request), 'same_request');
  assert.deepEqual(host.privateTaskCompilationWires(host.compileTasks(restored.prepared)),
    host.privateTaskCompilationWires(host.compileTasks(selected.prepared)));
  assert.deepEqual(host.sourceProgramSourceInput(restored.prepared), {
    document: '/*😀*/\r\nSELECT @n AS n', format: 'sql', parametersWire: '{"n":3}',
    parameterDeclarationsWire: '{"n":{"type":"number"}}',
  });
  const material = host.sourceProgramMaterialInput(restored.prepared, environmentWire);
  assert.equal(material.format, 'json');
  assert.notEqual(material.document, '/*😀*/\r\nSELECT @n AS n');
  assert.equal(material.parametersWire, '{"n":3}');
});

test('historical source originals retain answer and cannot stand in for the new main request', () => {
  const env = environment();
  const fresh = host.prepareSourceProgram(intent(), env, publication);
  const {primaryResultRecipe, ...legacyOriginals} = host.sourceProgramOriginals(fresh.prepared);
  assert.equal(primaryResultRecipe, 'public-main');
  const legacy = host.restoreSourceProgram(legacyOriginals, env);
  assert.deepEqual(host.sourceProgramOriginals(legacy.prepared), legacyOriginals);
  assert.deepEqual(host.taskResultDefinitions(legacy.prepared,
    host.compileTasks(legacy.prepared)).map(result => result.name), ['answer']);
  const current = host.prepareSourceRequest(fresh.prepared, fresh.originalIntent, scope, 'same-original');
  assert.throws(() => host.admitSourceRequestFields(legacy.prepared, legacy.originalIntent,
    host.requestFields(current)), {code: 'RunHostRequestRecordRejected'});
  const saved = host.sourceProgramOriginals(fresh.prepared);
  for (const primaryResultRecipe of [null, 'answer', 'other', true]) {
    assert.throws(() => host.restoreSourceProgram({...saved, primaryResultRecipe}, env),
      /InvalidRunHostSourceOriginals/u);
  }
  assert.throws(() => host.restoreSourceProgram({...saved,
    get primaryResultRecipe() {assert.fail('saved recipe accessor must not run');}}, env),
  /InvalidRunHostSourceOriginals/u);
});

test('explicit source exports retain their authored names under the public recipe', () => {
  for (const name of ['answer', 'main', 'MiXeD']) {
    const selected = host.prepareSourceProgram(intent(`SELECT 1 AS n |> RESULT ${name}`, 'aql-text'),
      environment(), publication);
    assert.deepEqual(host.taskResultDefinitions(selected.prepared,
      host.compileTasks(selected.prepared)).map(result => result.name), [name]);
  }
});

test('copied, foreign and mismatched source originals cannot replace nominal preparation or intent', () => {
  const original = intent();
  const env = environment();
  const selected = host.prepareSourceProgram(original, env, publication);
  assert.throws(() => host.prepareSourceProgram(original, {...env}, publication), /ForeignRunHostHandle/u);
  assert.throws(() => host.prepareSourceProgram({...original}, env, publication), /ForeignRunHostHandle/u);
  assert.throws(() => host.prepareSourceRequest(selected.prepared, intent(), scope, 'copied'), /ForeignRunHostSourcePreparation/u);
  assert.throws(() => host.sourceProgramOriginals({...selected.prepared}), /ForeignRunHostSourcePreparation/u);
  const saved = host.sourceProgramOriginals(selected.prepared);
  for (const wrong of [{...saved, intentCid: scope}, {...saved, environmentCid: scope},
    {...saved, extra: true}, {...saved, publicationWire: '{}'}]) {
    assert.throws(() => host.restoreSourceProgram(wrong, env));
  }
  assert.throws(() => host.prepareRequest(selected.prepared, scope, 'wrong', scope), /ForeignRunHostSourceIntent/u);
  const current = host.prepareSourceRequest(selected.prepared, original, scope, 'changed');
  const changed = host.prepareSourceProgram(intent('SELECT 2 AS n'), env, publication);
  assert.throws(() => host.admitSourceRequestFields(changed.prepared, changed.originalIntent, host.requestFields(current)),
    {code: 'RunHostRequestRecordRejected'});
  assert.throws(() => host.prepareSourceProgram(original, env,
    JSON.stringify({environmentCid: scope, aliases: []})), {code: 'RunHostSourcePreparationRejected'});
});

test('source material projection is consumed by the existing task Run material Owner', () => {
  const original = intent();
  const selected = host.prepareSourceProgram(original, environment(), publication);
  const compiled = host.compileTasks(selected.prepared);
  // Explicit static policy evidence exercises identity only, not funded dispatch.
  const issued = host.issueAllowedTaskRun(selected.prepared, compiled, {
    executionContextCid: scope, hostPolicyCid: 'sha256:' + 'b'.repeat(64),
    expiresAt: '2099-01-01T00:00:00.000Z',
  });
  const definition = host.issueTaskRunDefinition(selected.prepared, compiled,
    issued.admission, 'source-material', 'source-run',
    '2026-10-19T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const material = host.sourceProgramMaterialInput(selected.prepared, environmentWire);
  const saved = host.issueTaskRunMaterials(selected.prepared, compiled, issued.admission, definition, material);
  assert.equal(typeof saved, 'string');
  const changed = host.prepareSourceProgram(intent('SELECT 2 AS n'), material.environment, publication);
  assert.throws(() => host.issueTaskRunMaterials(selected.prepared, compiled, issued.admission, definition,
    {...material, document: host.sourceProgramMaterialInput(changed.prepared, environmentWire).document}));
});

test('source Effect materials require the same source preparation and independently retained request', () => {
  const wire = readFileSync(new URL('./fixtures/completion-free-update-source.environment.json', import.meta.url), 'utf8').trimEnd();
  const body = JSON.parse(wire);
  const env = host.admitEnvironment(wire, body.evidence_bundle_cid, {rela: true});
  const snapshot = body.schema_snapshots.find(x => x.source_ref === 'connector://crm/main/r#v');
  const published = JSON.stringify({environmentCid: body.evidence_bundle_cid, aliases: [{
    name: 'records', sourceRef: snapshot.source_ref,
    sourceViewContractCid: snapshot.source_view_contract_cid,
    schemaContractCid: snapshot.carrier_schema_contract_cid,
  }]});
  const text = "FROM records |> SELECT id, id AS value |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1` FROM RESULT updates ID id SET (Name = value)";
  const original = intent(text, 'aql-text');
  const selected = host.prepareSourceProgram(original, env, published);
  assert.equal(selected.kind, 'effect');
  const compilation = host.compileEffect(selected.prepared);
  const request = host.prepareEffectRequest(selected.prepared, compilation, scope, 'source-effect');
  assert.equal(host.requestFields(request).callerInputIntentCid, host.submittedIntentFacts(original).cid);
  const allowed = host.issueAllowedEffectRun(selected.prepared, compilation, {
    executionContextCid: scope, hostPolicyCid: 'sha256:' + 'b'.repeat(64), expiresAt: '2099-01-01T00:00:00.000Z',
  });
  const definition = host.issueEffectRunDefinition(allowed, 'source-effect', 'same-effect-run',
    '2026-10-19T00:00:00.000Z', '2098-01-01T00:00:00.000Z');
  const material = host.sourceProgramMaterialInput(selected.prepared, wire);
  const saved = host.issueEffectRunMaterials(allowed, definition, material, request);
  const root = host.privateRunDefinition(definition).cid;
  const fresh = host.restoreSourceProgram(host.sourceProgramOriginals(selected.prepared),
    host.admitEnvironment(wire, body.evidence_bundle_cid, {rela: true}));
  const restoredRequest = host.admitSourceRequestFields(fresh.prepared, fresh.originalIntent, host.requestFields(request));
  const restored = host.admitEffectRunMaterials(saved, root, {rela: true}, undefined, restoredRequest, fresh.prepared);
  assert.deepEqual(host.privateRunDefinition(restored.definition), host.privateRunDefinition(definition));
  assert.deepEqual(host.requestFields(restored.request), host.requestFields(request));
  assert.deepEqual(host.sourceProgramOriginals(restored.prepared), host.sourceProgramOriginals(selected.prepared));
  assert.throws(() => host.admitEffectRunMaterials(saved, root, {rela: true}, undefined, restoredRequest),
    {code: 'RunHostEffectRestorationRejected'});
  assert.throws(() => host.admitEffectRunMaterials(saved, root, {rela: true}, undefined, undefined, fresh.prepared),
    {code: 'RunHostEffectRestorationRejected'});
  const changed = host.prepareSourceProgram(intent(text + ' ', 'aql-text'), env, published);
  assert.throws(() => host.admitEffectRunMaterials(saved, root, {rela: true}, undefined, restoredRequest, changed.prepared),
    {code: 'RunHostEffectRestorationRejected'});
  const readOnly = host.prepareSubmittedIntent(JSON.stringify({kind: 'aql',
    input: {text, format: 'aql-text'}, parameters: null, readOnly: true}), limits);
  assert.throws(() => host.prepareSourceProgram(readOnly, env, published), {code: 'RunHostSourcePreparationRejected'});
});

test('a separate facade namespace cannot supply its valid source handles to this facade', async () => {
  const foreign = await import('./index.mjs?foreign-source-namespace');
  const foreignEnvironment = foreign.admitEnvironment(environmentWire, evidenceCid, {rela: true});
  const foreignIntent = foreign.prepareSubmittedIntent(JSON.stringify({kind: 'aql',
    input: {text: 'SELECT 1 AS n', format: 'sql'}, parameters: null}), limits);
  const foreignPrepared = foreign.prepareSourceProgram(foreignIntent, foreignEnvironment, publication);
  assert.throws(() => host.prepareSourceProgram(foreignIntent, environment(), publication), /ForeignRunHostHandle/u);
  assert.throws(() => host.prepareSourceProgram(intent(), foreignEnvironment, publication), /ForeignRunHostHandle/u);
  assert.throws(() => host.compileTasks(foreignPrepared.prepared), /ForeignRunHostHandle/u);
  assert.throws(() => host.sourceProgramOriginals(foreignPrepared.prepared), /ForeignRunHostSourcePreparation/u);
});

test('prepared Environment preserves new source queries and saved primary recipes', () => {
  const env = environment();
  const retained = host.preparePublishedEnvironment(env, publication);
  assert(Object.isFrozen(retained));
  assert.equal(host.publishedEnvironmentMatches(retained, env, publication), true);
  const original = intent('SELECT @n AS n', 'sql', {n: 3}, {n: {type: 'number'}});
  const fresh = host.prepareSourceProgram(original, env, publication);
  const reused = host.prepareSourceProgram(original, env, publication, retained);
  const compiled = selected => host.compileTasks(selected.prepared);
  assert.deepEqual(host.privateTaskCompilationWires(compiled(reused)),
    host.privateTaskCompilationWires(compiled(fresh)));
  const request = host.prepareSourceRequest(reused.prepared, original, scope, 'prepared-original');
  assert.equal(host.requestRelation(request,
    host.prepareSourceRequest(fresh.prepared, original, scope, 'prepared-original')), 'same_request');
  assert.deepEqual(host.taskResultDefinitions(reused.prepared, compiled(reused)).map(x => x.name), ['main']);
  const saved = host.sourceProgramOriginals(reused.prepared);
  const restored = host.restoreSourceProgram(saved, env, retained);
  assert.deepEqual(host.sourceProgramOriginals(restored.prepared), saved);
  const {primaryResultRecipe, ...historical} = saved;
  assert.equal(primaryResultRecipe, 'public-main');
  const legacy = host.restoreSourceProgram(historical, env, retained);
  assert.deepEqual(host.taskResultDefinitions(legacy.prepared, compiled(legacy)).map(x => x.name), ['answer']);
  assert.deepEqual(host.sourceProgramOriginals(legacy.prepared), historical);
  const changedIntent = intent('SELECT @n + 1 AS n', 'sql', {n: 4}, {n: {type: 'number'}});
  const changed = host.prepareSourceProgram(changedIntent, env, publication, retained);
  assert.notEqual(host.requestFields(host.prepareSourceRequest(changed.prepared, changedIntent,
    scope, 'prepared-original')).callerInputIntentCid, host.requestFields(request).callerInputIntentCid);
});

test('prepared Environment refuses copied, foreign and changed publication originals', async () => {
  const env = environment();
  const retained = host.preparePublishedEnvironment(env, publication);
  assert.equal(host.publishedEnvironmentMatches(retained, environment(), publication), false);
  assert.equal(host.publishedEnvironmentMatches(retained, env, publication + ' '), false);
  assert.throws(() => host.prepareSourceProgram(intent(), env, publication, {...retained}), /ForeignRunHostHandle/u);
  assert.throws(() => host.prepareSourceProgram(intent(), environment(), publication, retained),
    /ForeignRunHostPublishedEnvironment/u);
  assert.throws(() => host.prepareSourceProgram(intent(), env, publication + ' ', retained),
    /ForeignRunHostPublishedEnvironment/u);
  const foreign = await import('./index.mjs?foreign-prepared-environment');
  const foreignEnv = foreign.admitEnvironment(environmentWire, evidenceCid, {rela: true});
  const foreignRetained = foreign.preparePublishedEnvironment(foreignEnv, publication);
  assert.throws(() => host.prepareSourceProgram(intent(), env, publication, foreignRetained),
    /ForeignRunHostHandle/u);
});

test('prepared Environment supplies the same Pure and Effect document preparation owners', () => {
  const pure = readFileSync(new URL('../sdk/fixtures/parameter-values.json', import.meta.url), 'utf8');
  const env = environment();
  const retained = host.preparePublishedEnvironment(env, publication);
  const original = host.prepare(pure, 'json', env, '{"n":3}');
  const selected = host.prepareProgram(pure, 'json', env, '{"n":3}', retained);
  assert.equal(selected.kind, 'effect_free');
  assert.deepEqual(host.privateTaskCompilationWires(host.compileTasks(selected.prepared)),
    host.privateTaskCompilationWires(host.compileTasks(original)));
  assert.throws(() => host.prepare(pure, 'json', env, '{', retained),
    {code: 'RunHostPreparationRejected'});
  const wire = readFileSync(new URL('./fixtures/source-compute-effect.environment.json', import.meta.url), 'utf8').trimEnd();
  const effectEnv = host.admitEnvironment(wire, JSON.parse(wire).evidence_bundle_cid, {rela: true});
  const effectPublication = JSON.stringify({environmentCid: JSON.parse(wire).evidence_bundle_cid, aliases: []});
  const effectRetained = host.preparePublishedEnvironment(effectEnv, effectPublication);
  const document = readFileSync(new URL('./fixtures/source-compute-effect.program.json', import.meta.url), 'utf8');
  const effect = host.prepareProgram(document, 'json', effectEnv, undefined, effectRetained);
  assert.equal(effect.kind, 'effect');
  assert.deepEqual(host.privateEffectCompilationWires(host.compileEffect(effect.prepared)),
    host.privateEffectCompilationWires(host.compileEffect(host.prepareEffect(document, 'json', effectEnv))));
});
