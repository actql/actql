// Actual installed Source-issued Content -> checked Model physical preparation.
// This is deterministic local I/O, not a paid Model or real GCS acceptance.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {execFile} from 'node:child_process';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {readFile} from 'node:fs/promises';
import {inspect, promisify} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import test from 'node:test';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';
import {scopedModelHolding} from '../../scripts/fixtures/model-custody-fixture.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {createPublicationContractControlFixture} from '../host-common/publication-contract-control.fixture.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {loadPrivateEvidenceKey} from './local-continuation-evidence.mjs';
import {getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {createGeneratedContentFixture} from './fixtures/generated-content.fixture.mjs';
import {openContentCommandHost} from './fixtures/content-command-host.fixture.mjs';
import {canonical, cid, token} from './fixtures/file-listing-source.fixture.mjs';
import {mediaInstallation, generatedContentInferProgram, generatedContentModelProviders}
  from './fixtures/generated-model-installation.fixture.mjs';

const program = () => ({version: 'actql/0.1', id: 'captured-content-model',
  stages: [{id: 'main', inputs: {
    transfers: {connector: 'content-fixture', resource: 'transfers', view: 'records'}},
  // Use the admitted exclusive scan/filter/select acquisition boundary.
  steps: [{from: 'transfers', filter: 'name IS NOT NULL', as: 'scan'},
    {select: ['name', 'content'], as: 'input'},
    {assert_rows: {unique_by: ['name']}, as: 'unique'},
    {infer: {contract: 'model-task:risk-score.v1', key: 'name',
      input: {document: {field: 'content'}}}, as: 'inferred'}],
  results: {answer: {from: 'inferred', fields: ['name', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'answer'}}}});

for (const entrance of ['Local', 'HTTPS']) {
for (const scenario of ['completed', 'approval custody', 'approval resume']) {
test(`public ${entrance} acquired SERIALIZE feeds the same Run's typed Content INFER${scenario === 'completed' ? '' : ': ' + scenario}`, async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'generated-content-infer-', label: 'public acquired SERIALIZE to Model'});
  const original = await createGeneratedContentFixture(t);
  await original.store.commitPhysicalHolding(original.holding, [original.physical.prepared]);
  const {task, installation, hostCapacityPolicy} = await mediaInstallation({requestBytes: 4096, contentBytes: 32});
  // The Content CSV law always quotes text cells; safe headers are unquoted.
  const expected = Buffer.from('name\n"approved.csv"\n');
  const expectedCid = `sha256:${createHash('sha256').update(expected).digest('hex')}`;
  let calls = 0, generations = 0, preparations = 0, host, physicalIssue;
  const keys = generateKeyPairSync('ed25519');
  const registerModelProviders = generatedContentModelProviders({root: scratch.path,
    task, expected, sourceWire: original.description.wire,
    onPrepare: () => preparations++, onSend: () => calls++,
    onFailure: error => { physicalIssue = error; }});
  host = await openContentCommandHost({scratch, generated: original,
    keys, entrance, installEffects: false, modelInstallation: installation,
    registerModelProviders, hostCapacityPolicy,
    modelApprovalRequired: scenario !== 'completed',
    faultInjection: step => { if (step === 'content_workspace_reserved') generations++; }});
  t.after(() => host.close());
  const submitted = generatedContentInferProgram();
  const run = await host.client.startSource(JSON.stringify(submitted), {format: 'json',
    submissionRef: host.client.newSubmission({nonce: 'acquired-serialize-infer'})}).catch(error => {
      t.diagnostic(inspect({error, events: host.events}, {depth: 12})); throw error;
    });
  const state = await run.wait({signal: AbortSignal.timeout(15000)});
  if (scenario !== 'completed') {
    assert.equal(state.status, 'waiting_checkpoint', inspect({state, events: host.events}, {depth: 12}));
    assert.equal(calls, 0, 'no Model send before approval');
    assert.equal(generations, 1);
    assert.equal(host.reads(), 1);
    assert.equal(host.sends(), 0);
    await host.close();
    const {stdout} = await promisify(execFile)(process.execPath,
      [new URL('./fixtures/generated-model-custody.fixture.mjs', import.meta.url).pathname,
        join(scratch.path, 'host'), run.ref.runDefinitionCid], {timeout: 30000, maxBuffer: 262144});
    const {receipt, snapshot, recoveredReferenceWire, recoveredBytes} = JSON.parse(stdout);
    assert.equal(receipt.runDefinitionCid, run.ref.runDefinitionCid);
    const recovery = snapshot.contentGeneration;
    assert.equal(recoveredReferenceWire, recovery.referenceWire,
      'separate process reissues the exact original Ref after physical confirmation');
    assert.equal(recoveredBytes, expected.toString('utf8'));
    const reference = JSON.parse(recovery.referenceWire);
    assert.equal(reference.metadata.content_cid, expectedCid);
    assert.equal(reference.metadata.size_bytes, expected.length);
    assert.deepEqual(recovery.bindings.map(value => value.name),
      ['content_input_artifact', 'content_evidence', 'content_generation']);
    const proofs = Object.fromEntries(recovery.bindings.map(value => [value.name, JSON.parse(value.wire)]));
    assert.equal(proofs.content_generation.run_definition_cid, run.ref.runDefinitionCid);
    assert.equal(proofs.content_generation.content_evidence_cid, proofs.content_evidence.evidence_cid);
    assert.equal(proofs.content_evidence.barrier_input_artifact_cid, proofs.content_input_artifact.input_artifact_cid);
    assert.equal(proofs.content_evidence.content_ref_cid, reference.content_ref_cid);
    assert.equal(proofs.content_generation.content_store_cid, recovery.binding.content_store_cid);
    assert.equal(proofs.content_input_artifact.effective_data_policy_cid, reference.metadata.effective_data_policy_cid);
    assert.equal(proofs.content_evidence.row_count, 1);
    assert.equal(proofs.content_evidence.byte_count, expected.length);
    const scope = JSON.parse(snapshot.callScopeSnapshotWire);
    assert.equal(scope.sources.length, 1, 'original Source closure remains in the same authenticated input');
    assert.equal(snapshot.rows.length, 1);
    assert.deepEqual(JSON.parse(snapshot.rows[0]).content, reference);
    assert.deepEqual(await readFile(join(scratch.path, 'host', 'publication', 'objects',
      expectedCid.slice('sha256:'.length))), expected);
    if (scenario === 'approval resume') {
      host = await openContentCommandHost({scratch, generated: original, keys, entrance,
        modelInstallation: installation, registerModelProviders, hostCapacityPolicy,
        modelApprovalRequired: true, allowSourceRead: false,
        faultInjection: step => { if (step === 'content_workspace_reserved') generations++; }});
      const attached = await host.client.attach(run.ref);
      const checkpoints = (await host.client.checkpoints()).items;
      assert.equal(checkpoints.length, 1);
      const resolved = await host.client.resolveCheckpoints(
        [{checkpoint: checkpoints[0], decision: 'approved'}], {
          signer: {keyId: 'reviewer', reviewerId: 'reviewer',
            authorityScopeCid: run.ref.authorityScopeCid,
            sign: bytes => sign(null, bytes, keys.privateKey)},
        });
      assert.equal(resolved.results[0].status, 'committed');
      const resumeSignal = AbortSignal.timeout(15000);
      let resumed;
      try {
        do {
          resumed = await attached.status({signal: resumeSignal});
          if (!['resuming', 'running', 'waiting_checkpoint'].includes(resumed.status)) break;
          await delay(20, undefined, {signal: resumeSignal});
        } while (true);
      } catch (error) {
        // Preserve the bounded observation failure and original fixture. A
        // later committed index alone cannot prove timely public completion.
        t.diagnostic(inspect({resumed, events: host.events, physicalIssue,
          calls, generations, preparations, error}, {depth: 16}));
        throw error;
      }
      assert.equal(resumed.status, 'succeeded', inspect({resumed, events: host.events,
        physicalIssue, calls, generations, preparations}, {depth: 16}));
      assert.deepEqual(await attached.result('answer').all(),
        [{name: 'out.csv', outcome: 'ok', value: {reason: null, risk: 'high'}}]);
      assert.equal(host.reads(), 0, 'original Source must not be acquired again');
      assert.equal(calls, 1);
      assert.equal(generations, 1, 'the original encoder must not run again');
      assert.equal(host.sends(), 0);
      await host.close();
    }
    // The custody-only phase does not claim approval/resume or unknown-call
    // replay. Host reopen above is not yet a separate-process approval test.
    await original.store.retirePhysicalHolding(original.holding.holding_cid);
    scratch.passed();
    return;
  }
  assert.equal(state.status, 'succeeded', inspect({state, events: host.events,
    physicalIssue, calls, generations, preparations}, {depth: 12}));
  const expectedRows = [{name: 'out.csv', outcome: 'ok', value: {reason: null, risk: 'high'}}];
  assert.deepEqual(await run.result('answer').all(), expectedRows);
  assert.deepEqual(await (await host.client.attach(run.ref)).result('answer').all(), expectedRows);
  assert.equal(calls, 1);
  assert.equal(preparations, 1);
  assert.equal(generations, 1);
  assert.equal(host.reads(), 1);
  assert.equal(host.sends(), 0, 'Model use does not implicitly upload Content');
  await host.close();
  assert.deepEqual(await readFile(join(scratch.path, 'host', 'publication', 'objects',
    expectedCid.slice('sha256:'.length))), expected, 'committed generation outlives temporary Model cleanup');
  await original.store.retirePhysicalHolding(original.holding.holding_cid);
  scratch.passed();
});
}

for (const scenario of ['exact bytes', 'one-short request', 'media byte limit',
  'wrong bytes', 'revoked after preparation', 'cleanup retry']) {
test(`public ${entrance} typed Content INFER: ${scenario}`, async t => {
  const scratch = await createOwnedScratch({parent: new URL('../../_build/', import.meta.url).pathname,
    prefix: 'content-infer-', label: 'public physical typed Content INFER'});
  const generated = await createGeneratedContentFixture(t);
  await generated.store.commitPhysicalHolding(generated.holding, [generated.physical.prepared]);
  const requestBytes = scenario === 'one-short request' ? 1465 : 1466;
  const {task, installation, hostCapacityPolicy} = await mediaInstallation({requestBytes,
    contentBytes: scenario === 'media byte limit' ? 2 : 32});
  assert.equal(Buffer.byteLength(`{"document":${generated.description.wire}}`), 1466);
  let calls = 0;
  let preparations = 0;
  let cleanups = 0;
  let physicalReleased = false;
  const registerModelProviders = moon => [{providerId: 'models/fixture',
    bindingOriginals: providerBindingOriginals('models/fixture', {selector: 'fixture-risk-model'}),
    invoke() { throw new Error('UnpreparedContentProviderCall'); },
    validatePrompt(taskCid, selector, wire) {
      return taskCid === task.contract_cid && selector === task.authored_model_selector &&
        JSON.parse(wire).format === 'fixture-content/0.1';
    },
    quantityCapacity: {limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
      perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
    observeEgress: () => ({_0: 'internal', _1: 'fixture-region', _2: false, _3: false}),
    physicalPreflight(request, ioNotification, rawCaptureBinder, admittedProvider) {
      preparations++;
      const selected = moon.clientProgramModelContentInput(admittedProvider,
        request, 'document', -1);
      if (selected.$tag === 0) {
        return moon.clientProgramModelContentRequestPreflight(() => ({_0: selected, _1: 1}), () => true);
      }
      const input = checked(selected);
      assert.ok(input, 'the actual non-null Source Ref is selected');
      const description = moon.clientProgramModelContentInputDescription(input);
      assert.equal(description._0, generated.description.wire);
      assert.equal(description._1, 'text/csv');
      assert.equal(description._2, 'sha256:984a644ec3b56d32b0404777e1eb73390c4b0742a6a0e183f07861056b6746de');
      assert.equal(description._3, 3n);
      let pending, admission, issue, contentIssue, payload, byteCheck;
      let loaded = false, byteOffset = 0;
      const valueOf = result => {
        if (result.$tag === 0) { contentIssue = result._0; return undefined; }
        return checked(result);
      };
      const progress = (ready, plan, work = 1) => ({
        _0: {$tag: 1, _0: {_0: ready, _1: plan}}, _1: work});
      const refused = () => ({_0: {$tag: 0, _0: contentIssue}, _1: 1});
      return moon.clientProgramModelContentRequestPreflight(quantum => {
        if (pending === undefined) {
          byteCheck = valueOf(moon.clientProgramStartModelContentBytes(input,
            'fixture-region', token('a'), undefined, undefined,
            () => !physicalReleased && generated.store.status().closed === false));
          if (byteCheck === undefined) return refused();
          pending = (async () => {
            const pieces = [];
            await generated.store.consumePhysicalHolding(generated.holding.holding_cid, 0, piece => {
              const bytes = scenario === 'wrong bytes' ? Buffer.from('ix\n') : Buffer.from(piece);
              assert.ok(bytes.length <= 256);
              pieces.push(bytes);
            });
            payload = Buffer.concat(pieces);
            loaded = true;
          })().catch(error => { issue = error; });
          return progress(false, undefined);
        }
        if (issue !== undefined) throw issue;
        if (contentIssue !== undefined) return refused();
        if (!loaded) return progress(false, undefined);
        if (byteOffset < payload.length) {
          const bytes = payload.subarray(byteOffset, byteOffset + Math.min(quantum, 256));
          const work = valueOf(moon.clientProgramUpdateModelContentBytes(byteCheck, bytes));
          if (work === undefined) return refused();
          assert.equal(work, bytes.length);
          byteOffset += bytes.length;
          return progress(false, undefined, work);
        }
        if (admission === undefined) {
          admission = valueOf(moon.clientProgramFinishModelContentBytes(byteCheck));
          return contentIssue === undefined ? progress(false, undefined) : refused();
        }
        const plan = checked(moon.clientProgramModelMediaPhysicalRequestPlan(
          request, BigInt(requestBytes), 33n, 0n, 500n, [admission], () => {
            assert.deepEqual(payload, Buffer.from('id\n'));
            calls++;
            return moon.clientProgramModelResponse(request, '{"reason":null,"risk":"high"}',
              'fixture-risk-model', 'content-request', 1n, 2n, new Date().toISOString());
          }));
        if (scenario === 'revoked after preparation') generated.revoke();
        return progress(true, plan);
      }, () => {
        cleanups++;
        if (pending !== undefined && !loaded && issue === undefined) return false;
        if (scenario === 'cleanup retry' && cleanups === 1) {
          assert.equal(physicalReleased, false);
          assert.deepEqual(payload, Buffer.from('id\n'));
          return false;
        }
        physicalReleased = true;
        payload = undefined;
        return true;
      });
    }}];
  const host = await openContentCommandHost({scratch, generated,
    keys: generateKeyPairSync('ed25519'), entrance,
    modelInstallation: installation, registerModelProviders, hostCapacityPolicy});
  t.after(host.close);
  const check = await host.client.check(program(), {kind: 'program', scope: 'bound_input'});
  assert.equal(check.report.verdict, 'verified', inspect(check, {depth: 8}));
  assert.equal(host.reads(), 0);
  const run = await host.client.start(program()).catch(error => {
    t.diagnostic(inspect({code: error.code, problem: getSubmissionOutcome(error)?.problem,
      events: host.events}, {depth: 10}));
    throw error;
  });
  const final = await run.wait({signal: AbortSignal.timeout(15000)});
  const succeeds = scenario === 'exact bytes' || scenario === 'cleanup retry';
  if (!succeeds) {
    assert.equal(final.status, 'failed', inspect({final, events: host.events}, {depth: 10}));
    assert.equal(final.control.physical_stop, 'confirmed');
    assert.equal(final.result_available, false);
    assert.equal(calls, 0, 'a refused input never invokes the Model');
    assert.equal(preparations, scenario === 'one-short request' ? 0 : 1);
    if (scenario === 'one-short request') {
      assert.ok(host.events.some(event => event.event === 'dispatch_failed' &&
        event.detail.issueTag === 2 && event.detail.nestedIssueTag === 14),
      'the exact one-short envelope fails with Model RequestLimit');
    } else if (scenario === 'revoked after preparation') {
      // This revocation precedes durable fixed-input export. The existing
      // retained-input Owner rejects its admission before Model authorization.
      assert.ok(host.events.some(event => event.event === 'dispatch_failed' &&
        event.detail.issueTag === 3 && event.detail.nestedIssueTag === 6),
      'revoked fixed input fails with RetainedInput Export(Admission), before any send');
    } else {
      assert.ok(host.events.some(event => event.event === 'dispatch_failed' &&
        event.detail.issueTag === 2 && event.detail.nestedIssueTag === 5),
      'physical Content refusal returns to the typed common Model owner');
    }
    assert.equal(host.reads(), 1);
    assert.equal(host.sends(), 0);
    await host.close();
    assert.equal(physicalReleased, scenario === 'wrong bytes' ||
      scenario === 'revoked after preparation');
    await generated.store.retirePhysicalHolding(generated.holding.holding_cid);
    scratch.passed();
    return;
  }
  assert.equal(final.status, 'succeeded', inspect({final, events: host.events,
    calls, preparations, inputWireBytes: Buffer.byteLength(`{"document":${generated.description.wire}}`)}, {depth: 10}));
  assert.deepEqual(await run.result('answer').all(), [
    {name: 'approved.csv', outcome: 'ok', value: {reason: null, risk: 'high'}},
  ]);
  assert.equal(calls, 1);
  assert.equal(preparations, 1);
  assert.equal(host.reads(), 1);
  assert.equal(host.sends(), 0);
  await host.close();
  assert.equal(physicalReleased, true);
  assert.ok(cleanups >= (scenario === 'cleanup retry' ? 2 : 1));
  // Read the actual encrypted private Store after the physical Host is closed.
  // The expected holding preimage comes from the original journal attempt,
  // never the product's holding-key or attachment evidence generator.
  const stateRoot = join(scratch.path, 'host');
  const storeAuthorityCid = `sha256:${createHash('sha256').update(JSON.stringify({
    version: 'actql-local-store-owner/0.1', root: stateRoot,
    principalId: userInfo().username})).digest('hex')}`;
  const key = await loadPrivateEvidenceKey(join(stateRoot, 'checkpoints'));
  const evidenceStore = await openLocalPublicationStore({
    directory: join(stateRoot, 'publication'), storeAuthorityCid,
    capacityBytes: 512 * 1024 * 1024, maxObjectBytes: 1048576,
    maxObjects: 10000, maxContractNodes: 10000, maxContractDepth: 64,
    privateEvidenceKey: key.key,
  }, createPublicationContractControlFixture());
  key.key.fill(0);
  try {
    const saved = {};
    for (const role of ['model_attachment_admission', 'model_slot_capture', 'model_dispatch_authority']) {
      const holdingCid = scopedModelHolding(stateRoot, run.ref.runDefinitionCid, storeAuthorityCid, role);
      const holding = await evidenceStore.inspectPhysicalHolding(holdingCid);
      assert.ok(holding, `${role} survives Model and Host cleanup`);
      saved[role] = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(
        await evidenceStore.readPrivateEvidence(role, holding.manifest_cid, holdingCid)));
      const {self_cid: actualCid, ...body} = saved[role];
      assert.equal(actualCid, cid(body), 'independent canonical preimage matches stored evidence');
      assert.equal(actualCid, holding.manifest_cid);
    }
    const record = saved.model_attachment_admission;
    const captured = saved.model_slot_capture;
    const originalContent = JSON.parse(generated.description.wire);
    assert.deepEqual(record.attachments, [{
      role: 'document', item: -1, content_ref_cid: originalContent.content_ref_cid,
      content_cid: `sha256:${createHash('sha256').update('id\n').digest('hex')}`,
      media_input_cid: installation.dependencyBodies[3].cid,
      policy_cid: originalContent.metadata.effective_data_policy_cid,
      media_type: 'text/csv', size_bytes: 3, classification: 'internal',
      region: 'fixture-region', egress_scope_cid: token('a'), pages: null, frames: null,
      complete: true, transfer_method: 'inline_bytes',
    }]);
    assert.equal(record.slot_cid, captured.slot_cid);
    assert.equal(record.model_task_cid, captured.model_task_cid);
    assert.equal(record.fixed_request_cid, captured.fixed_request_cid);
    assert.equal(record.authority_evidence_cid, saved.model_dispatch_authority.self_cid);
    assert.deepEqual(captured.attachment_admission_cids, [record.self_cid]);
  } finally { await evidenceStore.close(); }
  await generated.store.retirePhysicalHolding(generated.holding.holding_cid);
  scratch.passed();
});
}
}
