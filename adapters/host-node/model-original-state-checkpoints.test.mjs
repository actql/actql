import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {installRemoteCheckpoints} from './client-checkpoints.mjs';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';

// Independent existing admission inputs and resource tuple, not generated
// expected output. The synthetic other Origin fields are intentionally not
// authenticated by this data/custody-only connection.
const source = readFileSync(new URL('../../src/client_infer_host/fixture.generated_wbtest.mbt', import.meta.url), 'utf8');
const input = name => source.match(new RegExp(`let ${name} : String =\\n\\s+#\\|([^\\n]+)`, 'u'))[1];
const resource = JSON.parse(readFileSync(new URL('../../scripts/fixtures/model-original-resource-state-0.1.json', import.meta.url), 'utf8'));
const cid = n => `sha256:${n.repeat(64)}`;
const digest = value => `sha256:${createHash('sha256').update(value).digest('hex')}`;
const identity = value => digest(canonicalText(value));
const limits = {maxWireBytes: 8192, maxNodes: 512, maxDepth: 64};
const keys = generateKeyPairSync('ed25519');
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});

function original(control, runId = 'original') {
  const environment = moon.clientProgramCheckEnvironment(input('infer_fixture_environment'),
    input('infer_fixture_environment_cid'), false, false, true, false, false, false, false);
  const prepared = moon.clientProgramPreparationReady(moon.clientProgramPrepareEffectFreeWithParameters(
    input('infer_fixture_program'), 'json', environment, undefined));
  assert.ok(prepared);
  const task = JSON.parse(input('infer_fixture_environment')).model_task_contracts[0];
  const step = moon.clientProgramSelectedInferStep(prepared);
  const executionBody = {version: 'actql-model-execution-contract/0.1', model_task_contract_cid: task.contract_cid,
    retry_classification_contract_cid: cid('a'), backoff_contract_cid: cid('a'),
    max_attempts_per_slot: 2, max_total_attempts: 4, max_total_cost_units: 0,
    max_total_duration_ms: 1000, max_total_wire_bytes: 133072, max_total_token_reservation: 128,
    media_input_contracts: {}, default_publication: 'outcomes'};
  const executionCid = identity(executionBody);
  const execution = checked(moon.clientProgramReadInferModelExecution(prepared, step,
    canonicalText({...executionBody, self_cid: executionCid}), executionCid));
  const graph = checked(moon.clientProgramInferPlanGraph(prepared, step, execution, cid('b'), cid('c')));
  const data = {version: 'actql-effective-data-policy/0.1', classification: 'unknown',
    source_data_policy_cids: [], source_response_policy_cids: [], unknown_provenance: true};
  const compiled = control.prepareCheckedClientCompiledRun(prepared, 'infer',
    {executionContextCid: cid('d'), hostPolicyCid: cid('d'), expiresAt: '2099-01-01T00:00:00.000Z',
      resultDataPolicy: {kind: 'data_policy', cid: identity(data), wire: canonicalText(data)}}, graph);
  return control.defineCheckedClientCompiledRun(compiled,
    {namespaceId: 'scope', runId, createdAt: '2026-10-02T00:00:00.000Z', validUntil: '2099-01-01T00:00:00.000Z'});
}

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-original-state-checkpoints-'));
  const control = runtimeCore(moon).publicationControl;
  const opened = new Set();
  const open = async () => {
    const port = await installRemoteCheckpoints({root, namespaceId: 'scope',
      authorityScopeCid: cid('3'), ownerPrincipal: 'owner', siteKey: 'local',
      realizationKey: 'source-free-values', environmentCid: cid('4'), contractControl: control,
      authorization: {resumeAfterAnswer: false, accountConfiguration: canonicalText({
        version: 'actql-execution-account-config/0.1', account_id: 'local', entries: []}),
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: 'reviewer', publicKey: pem(keys.publicKey)}],
      hostKey: {keyId: 'host', privateKey: pem(keys.privateKey)}}});
    opened.add(port);
    return port;
  };
  const close = async port => { await port.close(); opened.delete(port); };
  t.after(async () => { for (const port of opened) await close(port); await rm(root, {recursive: true, force: true}); });
  return {root, control, open, close, definition: original(control)};
}

function wireFor(definition, binding, changes = {}) {
  return canonicalText({...resource, ...changes, origin: {...resource.origin,
    run_id: 'original', run_definition_cid: definition.identity, storage_binding_cid: binding.identity,
    ...changes.origin}});
}

test('original state Checkpoint facade saves exact Common document separately from Model input', async t => {
  const f = await fixture(t), port = await f.open();
  const binding = await port.observeModelOriginalStorageBinding();
  const wire = wireFor(f.definition, binding);
  const inputReceipt = await port.retainModelInput({runId: 'original', runDefinitionCid: f.definition.identity, bodyWire: '{"input":7}'});
  const receipt = await port.retainOriginalModelState({runDefinition: f.definition, storageBinding: binding, bodyWire: wire});
  assert.equal(receipt.cid, digest(wire));
  assert.equal(receipt.storageBindingCid, binding.identity);
  const document = await port.readOriginalModelState({runDefinition: f.definition, storageBinding: binding, receipt});
  assert.equal(document.wire, wire);
  assert.equal(f.control.modelOriginalResourceOriginField(document, 'run_id'), 'original');
  assert.equal((await port.readModelInput(inputReceipt)).toString(), '{"input":7}');
  assert.equal('restore' in document || 'send' in document || 'ledger' in document, false);
  const ledger = JSON.parse(await readFile(join(f.root, 'checkpoints', 'attempts', 'model-original.json'), 'utf8'));
  assert.deepEqual(ledger.holdings.map(item => item.name), ['captured_input', 'original_model_state']);
});

test('original state refuses foreign nominal contracts handles and every local binding change', async t => {
  const f = await fixture(t), port = await f.open(), other = await f.open();
  const binding = await port.observeModelOriginalStorageBinding(), foreign = await other.observeModelOriginalStorageBinding();
  const wire = wireFor(f.definition, binding);
  for (const handle of [undefined, binding.identity, {...binding}, foreign]) {
    await assert.rejects(port.retainOriginalModelState({runDefinition: f.definition, storageBinding: handle, bodyWire: wire}),
      {code: 'ForeignOriginalModelStorageBinding'});
  }
  for (const definition of [undefined, f.definition.identity, {...f.definition}, original(runtimeCore({...moon}).publicationControl)]) {
    await assert.rejects(port.retainOriginalModelState({runDefinition: definition, storageBinding: binding, bodyWire: wire}), TypeError);
  }
  for (const origin of [{run_id: 'other'}, {run_definition_cid: cid('5')}, {storage_binding_cid: cid('6')}]) {
    await assert.rejects(port.retainOriginalModelState({runDefinition: f.definition, storageBinding: binding,
      bodyWire: wireFor(f.definition, binding, {origin})}), {code: 'OriginalModelStateBindingMismatch'});
  }
  await assert.rejects(port.retainOriginalModelState({runDefinition: f.definition, storageBinding: binding,
    bodyWire: wireFor(f.definition, binding, {resource_state_cid: cid('7')})}));
  const otherRun = original(f.control, 'other');
  await assert.rejects(port.retainOriginalModelState({runDefinition: otherRun, storageBinding: binding, bodyWire: wire}),
    {code: 'OriginalModelStateBindingMismatch'});
  const admitted = f.control.readModelOriginalResourceDocument(wire, limits);
  assert.throws(() => f.control.modelOriginalResourceOriginField({...admitted}, 'run_id'), TypeError);
});

test('original state saved-response loss retries the same holding and restart requires fresh custody', async t => {
  const f = await fixture(t);
  let port = await f.open();
  const binding = await port.observeModelOriginalStorageBinding(), wire = wireFor(f.definition, binding);
  const args = {runDefinition: f.definition, storageBinding: binding, bodyWire: wire};
  // The caller loses the successful return, not a simulated durable commit.
  await assert.rejects((async () => { await port.retainOriginalModelState(args); throw new Error('LostSaveResponse'); })(), /LostSaveResponse/u);
  const receipt = await port.retainOriginalModelState(args);
  await f.close(port);
  await assert.rejects(port.readOriginalModelState({runDefinition: f.definition, storageBinding: binding, receipt}),
    {code: 'OriginalModelStateHostStopped'});
  port = await f.open();
  await assert.rejects(port.readOriginalModelState({runDefinition: f.definition, storageBinding: binding, receipt}),
    {code: 'ForeignOriginalModelStorageBinding'});
  const fresh = await port.observeModelOriginalStorageBinding();
  assert.equal(fresh.identity, binding.identity);
  assert.notEqual(fresh, binding);
  assert.equal((await port.readOriginalModelState({runDefinition: f.definition, storageBinding: fresh, receipt})).wire, wire);
  const ledger = JSON.parse(await readFile(join(f.root, 'checkpoints', 'attempts', 'model-original.json'), 'utf8'));
  assert.equal(ledger.holdings.length, 1, 'the retry retains the original cell');
  await assert.rejects(port.readOriginalModelState({runDefinition: original(f.control, 'other'),
    storageBinding: fresh, receipt}), {code: 'InvalidOriginalModelStateCustody'});
  for (const change of [{cid: cid('1')}, {ownerId: 'model-other'}, {runId: 'other'},
    {runDefinitionCid: cid('2')}, {storageBindingCid: cid('3')}]) {
    await assert.rejects(port.readOriginalModelState({runDefinition: f.definition, storageBinding: fresh, receipt: {...receipt, ...change}}));
  }
});
