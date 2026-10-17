// Actual Common codec and SQLite custody. No Provider, Model input, send,
// startup reservation, physical cleanup ACK or numerical supplier is installed.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync, mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {installNodeClientProgramPreparation} from './client-program-preparation.mjs';
import {readInstalledModelExecution} from './installed-model.mjs';
import {openClientRequestJournal} from './client-request-journal.mjs';
import {originalModelRunWire} from './installed-model-originals.mjs';
import {canonical, identity, configuration, program, task} from '../../scripts/fixtures/first-m1-common-materials.mjs';

// A directly supervised selected build may use a separate output directory so
// unrelated retained runtimes are not overwritten. The receipt binds its exact
// Source and bytes; this test choice supplies no operational runtime authority.
const runtimeUrl = process.env.ACTQL_INFER_ORIGINAL_RUNTIME === undefined
  ? new URL('../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url)
  : pathToFileURL(process.env.ACTQL_INFER_ORIGINAL_RUNTIME);
const moon = await import(runtimeUrl.href);

const base = JSON.parse(readFileSync(new URL('../../spec/local-check-environment.json', import.meta.url)));
const profiles = Object.freeze([false, false, true, false, false, false, false]);
const bounds = Object.freeze({maxWireBytes: 1000000, maxNodes: 100000, maxDepth: 64});
const control = runtimeCore(moon).publicationControl;
const cid = value => `sha256:${value.repeat(64)}`;
const policyWire = '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}';

function original(runId = 'saved-infer') {
  const installation = configuration(base);
  const body = JSON.parse(installation.environmentWire);
  const environment = moon.clientProgramCheckEnvironment(installation.environmentWire,
    body.evidence_bundle_cid, ...profiles);
  assert.ok(environment);
  const prepared = installNodeClientProgramPreparation({moon, environment})({
    kind: 'program', input: program, parameters: null});
  const {execution} = readInstalledModelExecution(moon, prepared, installation);
  const graph = checked(moon.clientProgramInstalledInferPlanGraph(prepared, 2, execution));
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer', {
    executionContextCid: cid('a'), hostPolicyCid: cid('b'), expiresAt: '2099-01-01T00:00:00.000Z',
    resultDataPolicy: {kind: 'data_policy', wire: policyWire, cid: identity(JSON.parse(policyWire))},
  }, graph);
  const definition = control.defineCheckedClientCompiledRun(compiled, {namespaceId: 'original', runId,
    createdAt: '2026-10-18T00:00:00.000Z', validUntil: '2099-01-01T00:00:00.000Z'});
  const request = moon.clientProgramRequestIdentity(prepared, cid('c'), 'original-request',
    moon.clientProgramSourceFreeInputIntentCid());
  assert.ok(request);
  const evidence = Object.freeze({prepared: compiled.preparedEvidence.wire,
    authorization: compiled.authorization.wire,
    modelOriginalRunWire: originalModelRunWire(compiled, definition)});
  const ticket = control.captureOriginalClientInferRun(compiled, prepared, definition, environment, undefined);
  const programCid = moon.clientRequestProgramCid(request);
  const materials = control.originalInferRunAdmissionEvidence(ticket, definition, programCid, evidence);
  return {environment, prepared, graph, compiled, definition, request, evidence, ticket, programCid, materials};
}

function journalFixture(t, value = original(), limits) {
  const path = mkdtempSync(join(tmpdir(), 'actql-original-infer-journal-'));
  t.diagnostic(`Fresh original journal custody retained at ${path}`);
  let journal = openClientRequestJournal(path, limits);
  t.after(() => journal.close());
  const options = {namespaceId: 'original', runDefinition: value.definition,
    runAdmissionEvidence: value.evidence, lookupExpiresAt: '2099-01-01T00:00:00.000Z'};
  const ref = {namespaceId: 'original', authorityScopeCid: cid('c'), runDefinitionCid: value.definition.identity};
  return {path, value, options, get journal() {return journal;},
    accept: (ticket = value.ticket) => journal.acceptDefinition(value.request,
      {...options, originalInferRun: ticket}, moon, control),
    lookup: () => journal.lookupRunDefinition(ref, moon, control),
    reopen() {journal.close(); journal = openClientRequestJournal(path, limits);}};
}

function restore(value, materials = value.materials, evidence = value.evidence) {
  return control.admitStoredClientInferRunOriginal(materials, value.definition,
    value.programCid, evidence, profiles, bounds);
}

test('original Infer codec restores one nominal preparation graph and same complete Run without current defaults', () => {
  const value = original();
  const restored = restore(value);
  assert.notStrictEqual(restored.prepared, value.prepared);
  assert.equal(restored.runDefinition, value.definition);
  assert.equal(originalModelRunWire(restored.compiled, restored.runDefinition), value.evidence.modelOriginalRunWire);
  control.checkClientCompiledRunOwner(restored.compiled, restored.prepared);
  assert.throws(() => control.checkClientCompiledRunOwner(restored.compiled, value.prepared), /Foreign/u);
  assert.deepEqual(control.compiledInferSourceFreeResultPolicy(restored.compiled), value.materials.resultPolicyOriginal);
  const saved = JSON.parse(value.materials.materialsWire);
  const originalEnvironment = JSON.parse(saved.check_environment);
  assert.deepEqual(originalEnvironment.model_task_contracts[0].generation_config, task.generation_config);
  // The reader accepts saved originals only; no installation/default resolver
  // or Provider callback is an argument to this operation.
  assert.equal(moon.clientProgramDefinitionCid(restored.prepared), value.programCid);
});

test('first Infer journal admission refuses copied or other-control tickets and raw evidence', t => {
  const f = journalFixture(t);
  assert.throws(() => f.accept({...f.value.ticket}), {code: 'InvalidClientInferRunOriginal'});
  const foreign = runtimeCore({...moon}).publicationControl;
  assert.throws(() => foreign.originalInferRunAdmissionEvidence(f.value.ticket,
    f.value.definition, f.value.programCid, f.value.evidence), /Foreign/u);
  assert.throws(() => f.journal.acceptDefinition(f.value.request, {...f.options,
    runAdmissionEvidence: {...f.value.evidence, inferRunOriginal: f.value.materials}}, moon, control),
  {code: 'InvalidClientInferRunOriginal'});
  assert.throws(() => f.journal.accept(f.value.request, {...f.options,
    runDefinitionCid: f.value.definition.identity,
    runAdmissionEvidence: {...f.value.evidence, inferRunOriginal: f.value.materials}}, moon),
  {code: 'InvalidClientInferRunOriginal'});
  assert.equal(f.lookup(), undefined);
});

test('saved Infer originals and Result policy commit with the same Run and reopen as immutable DATA only', t => {
  const f = journalFixture(t);
  const accepted = f.accept();
  assert.deepEqual(accepted.runAdmissionEvidence.inferRunOriginal, f.value.materials);
  f.reopen();
  const saved = f.lookup();
  assert.equal(saved.ref.runDefinitionCid, f.value.definition.identity);
  assert.equal(saved.revision, 0);
  assert.equal(saved.physicalStartReserved, false);
  assert.ok(Object.isFrozen(saved.runAdmissionEvidence.inferRunOriginal));
  assert.ok(Object.isFrozen(saved.runAdmissionEvidence.inferRunOriginal.resultPolicyOriginal));
  const restored = restore(f.value, saved.runAdmissionEvidence.inferRunOriginal, saved.runAdmissionEvidence);
  assert.equal(originalModelRunWire(restored.compiled, restored.runDefinition), f.value.evidence.modelOriginalRunWire);
  assert.equal(f.accept().inserted, false);
});

test('saved Infer reader refuses altered original Task materials Run program and admission correspondence', () => {
  const value = original();
  for (const field of ['materialsWire', 'resultPolicyOriginal']) {
    const changed = structuredClone(value.materials);
    if (field === 'materialsWire') {
      const body = JSON.parse(changed.materialsWire);
      body.infer_execution_contract_cid = cid('f');
      changed.materialsWire = canonical(body);
    } else changed.resultPolicyOriginal.cid = cid('f');
    assert.throws(() => restore(value, changed));
  }
  assert.throws(() => control.admitStoredClientInferRunOriginal(value.materials, value.definition,
    cid('f'), value.evidence, profiles, bounds), /Foreign/u);
  assert.throws(() => restore(value, value.materials, {...value.evidence, authorization: '{}'}), /Foreign/u);
  assert.throws(() => control.admitStoredClientInferRunOriginal(value.materials, original('different-run').definition,
    value.programCid, value.evidence, profiles, bounds));
});

test('Infer projection refuses a different preparation Environment or supplied Parameter Values', () => {
  const value = original();
  assert.throws(() => control.captureOriginalClientInferRun(value.compiled, original().prepared,
    value.definition, value.environment, undefined), /Foreign/u);
  const other = moon.clientProgramCheckEnvironment(canonical(base), base.evidence_bundle_cid, ...profiles);
  assert.ok(other);
  assert.throws(() => control.captureOriginalClientInferRun(value.compiled, value.prepared,
    value.definition, other, undefined));
  assert.throws(() => control.captureOriginalClientInferRun(value.compiled, value.prepared,
    value.definition, value.environment, '{"unexpected":1}'));
});

test('legacy Infer material absence is not backfilled and changed originals do not replace a saved Run', t => {
  const f = journalFixture(t);
  f.journal.acceptDefinition(f.value.request, f.options, moon, control);
  assert.throws(() => f.accept(), {code: 'ClientRequestInferEvidenceMissing'});
  f.reopen();
  assert.equal(f.lookup().runAdmissionEvidence.inferRunOriginal, undefined);
  const g = journalFixture(t);
  g.accept();
  const different = original('different-original');
  assert.throws(() => g.journal.acceptDefinition(g.value.request, {...g.options,
    runDefinition: different.definition, runAdmissionEvidence: different.evidence,
    originalInferRun: different.ticket}, moon, control), {code: 'ClientRequestInferEvidenceMismatch'});
  assert.deepEqual(g.lookup().runAdmissionEvidence.inferRunOriginal, g.value.materials);
});

test('Infer original copies use the existing aggregate evidence bound before durable acceptance', t => {
  const f = journalFixture(t, original(), {maxRunDefinitionWireBytes: 1024});
  assert.throws(() => f.accept(), {code: 'InvalidClientRunAdmissionEvidence'});
  assert.equal(f.lookup(), undefined);
});

test('Infer material and Run roll back together when original journal custody COMMIT fails', t => {
  const f = journalFixture(t);
  const database = new DatabaseSync(join(f.path, 'client-requests.sqlite3'));
  t.after(() => database.close());
  database.exec(`CREATE TRIGGER reject_infer_custody BEFORE UPDATE ON client_submission_custody
    BEGIN SELECT RAISE(ABORT, 'OriginalInferCustodyFailure'); END`);
  assert.throws(() => f.accept(), {code: 'ClientRequestAcceptanceUnknown'});
  assert.equal(database.prepare('SELECT COUNT(*) AS n FROM client_requests').get().n, 0);
  assert.equal(database.prepare('SELECT issued_count AS n FROM client_submission_custody').get().n, 0);
  // The failed attempt stays failed. No retry or replacement claim is issued.
});

test('another process reads the same Journal original pair after an acceptance reply is discarded', t => {
  const f = journalFixture(t);
  f.accept();
  f.journal.close();
  const module = relative => new URL(relative, import.meta.url).href;
  const code = `import assert from 'node:assert/strict';
    import * as moon from ${JSON.stringify(runtimeUrl.href)};
    import {runtimeCore} from ${JSON.stringify(module('../host-common/runtime-core.mjs'))};
    import {openClientRequestJournal} from ${JSON.stringify(module('./client-request-journal.mjs'))};
    import {originalModelRunWire} from ${JSON.stringify(module('./installed-model-originals.mjs'))};
    const control=runtimeCore(moon).publicationControl;
    const journal=openClientRequestJournal(process.argv[1]);
    try {
      const ref=JSON.parse(process.argv[2]);
      const saved=journal.lookupRunDefinition(ref,moon,control);
      assert.equal(saved.physicalStartReserved,false);
      const restored=control.admitStoredClientInferRunOriginal(saved.runAdmissionEvidence.inferRunOriginal,
        saved.runDefinition,saved.programDefinitionCid,saved.runAdmissionEvidence,
        ${JSON.stringify(profiles)},${JSON.stringify(bounds)});
      assert.equal(originalModelRunWire(restored.compiled,restored.runDefinition),
        saved.runAdmissionEvidence.modelOriginalRunWire);
      control.checkClientCompiledRunOwner(restored.compiled,restored.prepared);
      assert.equal(saved.revision,0);
    } finally {journal.close();}`;
  const result = spawnSync(process.execPath, ['--input-type=module', '-e', code, f.path,
    JSON.stringify({namespaceId: 'original', authorityScopeCid: cid('c'),
      runDefinitionCid: f.value.definition.identity})],
  {encoding: 'utf8', timeout: 30000, maxBuffer: 65536});
  assert.equal(result.error, undefined);
  assert.equal(result.signal, null);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, '');
  f.reopen();
  assert.equal(f.lookup().ref.runDefinitionCid, f.value.definition.identity);
  assert.equal(f.lookup().physicalStartReserved, false);
});
