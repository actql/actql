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
  assert.throws(() => host.issueTaskRunMaterials(selected.prepared, compiled, issued.admission, definition,
    {...material, document: material.document.replace('1', '2')}));
});
