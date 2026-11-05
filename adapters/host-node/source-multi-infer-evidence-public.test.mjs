import assert from 'node:assert/strict';
import test from 'node:test';
import {chmod, mkdtemp, mkdir, readFile, readdir, rm, unlink, writeFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createCaptureSink} from '../../examples/infer-evaluation/capture-sink.mjs';
import {checkResolvedEvidence, checkModelCaptureCorrespondence} from '../../examples/infer-evaluation/evidence-reference.mjs';
import {runEvaluatorProcess} from '../../examples/infer-evaluation/evaluator-process.mjs';
import {compareSourceInstructions, sourceEvaluationCases} from '../../examples/infer-evaluation/compare-source-instructions.mjs';
import {instructionCandidate, evaluationValueCid} from '../../examples/infer-evaluation/evaluate.mjs';

const runtime = process.env.ACTQL_INFER_EVIDENCE_ACCEPTANCE_INPUTS === undefined ? undefined :
  JSON.parse(await readFile(process.env.ACTQL_INFER_EVIDENCE_ACCEPTANCE_INPUTS, 'utf8'));
if (runtime === undefined) await (await import('./fixtures/source-node-client.mjs')).prepareSourceNodeClient({assemble: true, includeOtel: true});
const {expectedItems, expectedInputKeyCids, instructionsA, instructionsB, unchangedInstructions} =
  await import(runtime?.sourceInferFixture ?? '../../scripts/fixtures/source-multi-infer-evidence.mjs');
const worker = fileURLToPath(new URL('./source-multi-infer-evidence-worker.fixture.mjs', import.meta.url));
async function executeHost(root, transport, scenario = 'unicode', observationMode = 'disabled', phase = 'complete', expectedCode = 0) {
  const child = spawn(process.execPath, [worker, root, transport, scenario, observationMode, phase], {stdio: ['ignore', 'pipe', 'pipe']});
  let output = '', bytes = 0, exceeded = false;
  const collect = chunk => {
    bytes += chunk.length;
    if (bytes > 65536) {exceeded = true; child.kill('SIGTERM');}
    else output += chunk.toString();
  };
  child.stdout.on('data', collect); child.stderr.on('data', collect);
  let expired = false;
  const timer = setTimeout(() => {expired = true; child.kill('SIGTERM');}, 90000);
  const hardStop = setTimeout(() => child.kill('SIGKILL'), 95000);
  try {
    const exit = await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', (code, signal) => resolve({code, signal}));
    });
    assert.equal(expired, false, output);
    assert.equal(exceeded, false, output);
    assert.deepEqual(exit, {code: expectedCode, signal: null}, output);
    return child.pid;
  } finally {clearTimeout(timer); clearTimeout(hardStop);}
}

async function evaluateOriginalInventory(sink, saved) {
  const associations = [], attempts = new Set(), evaluatorPids = new Set();
  for (const target of ['second_assessment', 'first_assessment']) {
    const receipt = await sink.lookup(saved.subject, target);
    assert.equal(receipt.manifest.status, 'complete');
    assert.equal(receipt.manifest.items.length, 2);
    for (const item of [...receipt.manifest.items].reverse()) {
      const job = {subject: saved.subject, evidence: {...receipt.manifest, ...item},
        caseId: `${target}-${item.modelCallSlotCid}`, expected: 'low', role: 'selection',
        deadline: Date.now() + 10000};
      const reply = await sink.withEvaluatorEvidence({subject: saved.subject,
        attemptCid: item.attemptCid, references: item.references}, async resolvedEvidence => {
        const facts = checkModelCaptureCorrespondence(job, checkResolvedEvidence(job, resolvedEvidence));
        const sent = saved.calls.filter(call => call.slotCid === item.modelCallSlotCid);
        assert.equal(sent.length, 1);
        assert.deepEqual(sent[0].key, facts.typedInput.key);
        assert.equal(sent[0].taskCid, facts.typedInput.model_task_contract_cid);
        assert.equal(sent[0].semanticRequestCid, facts.typedInput.semantic_request_cid);
        assert.deepEqual(facts.renderedInput, {instructions: sent[0].instructions, text: sent[0].text});
        associations.push({target, key: facts.typedInput.key,
          keyContracts: facts.typedInput.key_contracts, text: facts.typedInput.inputs.text});
        attempts.add(item.attemptCid);
        assert.equal(JSON.parse(item.references.typedInput.policy.wire).unknown_provenance, true);
        assert.deepEqual(JSON.parse(item.references.typedInput.policy.wire).source_data_policy_cids,
          [saved.originalSourcePolicy]);
        return runEvaluatorProcess({job, resolvedEvidence, deadline: job.deadline,
          onProcess(pid) {assert.notEqual(pid, process.pid); evaluatorPids.add(pid);}});
      });
      assert.equal(reply.score, 1);
    }
  }
  associations.sort((a, b) => a.target.localeCompare(b.target) || a.key[0] - b.key[0]);
  assert.deepEqual(associations, expectedItems);
  assert.equal(attempts.size, 4);
  assert.equal(sink.pendingBytes(), 0);
  assert.equal(sink.cleanupPending(), false);
  assert.equal(evaluatorPids.size, 4);
  return {associations, evaluatorPids: [...evaluatorPids]};
}

async function recordInterruptedAcceptance({transport, boundary, root, firstPid, restoredPid, saved, evaluated}) {
  if (runtime === undefined) return;
  assert.equal(saved.revision, runtime.revision);
  await writeFile(join(runtime.evidenceDirectory, `source-recovery-${transport}-${boundary}.json`),
    JSON.stringify({revision: runtime.revision, transport, boundary, root, firstPid, restoredPid,
      ref: saved.ref, status: saved.terminal.status, sourceCalls: saved.sourceCalls,
      providerCalls: saved.calls.length, originalSlots: saved.calls.slice(0, 2).map(call => call.slotCid),
      columns: saved.description.columns,
      restoredItems: evaluated.associations, evaluatorPids: evaluated.evaluatorPids,
      observationMode: saved.observationMode, otlpRequests: saved.otlpRequests, complete: true}, null, 2) + '\n');
}

for (const transport of ['local', 'https']) {
  test(`public ${transport} refuses another original Run's attempt and call during response reconciliation`, {timeout: 180000}, async t => {
    const foreignRoot = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-foreign-response-'));
    t.after(() => t.diagnostic(`Retained authentic foreign response reference: ${foreignRoot}`));
    // A call slot identifies Program/input semantics and can legitimately be
    // shared by different Runs. Use another real input to obtain a distinct
    // call slot as well as a distinct original Run-bound attempt.
    const foreignFirstPid = await executeHost(foreignRoot, transport, 'A', 'disabled', 'stop-provider-saved', 77);
    const foreignRestoredPid = await executeHost(foreignRoot, transport, 'A', 'disabled', 'resume-provider-saved');
    const foreign = JSON.parse((await readFile(join(foreignRoot, 'provider-lookups.jsonl'), 'utf8')).trim());
    assert.equal(foreign.found, true);
    const foreignRef = JSON.parse(await readFile(join(foreignRoot, 'run-ref.json'), 'utf8'));
    const refusals = [];
    for (const field of ['attempt', 'call']) {
      const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-response-binding-'));
      t.after(() => t.diagnostic(`Retained ${field} response binding refusal: ${root}`));
      const firstPid = await executeHost(root, transport, 'unicode', 'disabled', 'stop-provider-saved', 77);
      const originalRef = JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8'));
      assert.notDeepEqual(originalRef, foreignRef);
      const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
      assert.equal(stopped.boundary, 'provider_response_durable');
      assert.equal(stopped.calls.length, 3);
      await writeFile(join(root, 'foreign-response-reference.json'), JSON.stringify(foreign));
      const phase = `resume-foreign-${field}`;
      const restoredPid = await executeHost(root, transport, 'unicode', 'disabled', phase);
      const saved = JSON.parse(await readFile(join(root, `${phase}.json`), 'utf8'));
      assert.deepEqual(saved.ref, originalRef);
      assert.equal(saved.terminal.status, 'needs_reconciliation');
      assert.equal(saved.terminal.result_available, false);
      assert.deepEqual(saved.calls, stopped.calls);
      assert.equal(saved.sourceCalls, 1);
      const reply = JSON.parse(await readFile(join(root, `${phase}-reply.json`), 'utf8'));
      assert.equal(reply.field, `${field}Wire`);
      assert.equal(reply.returned[reply.field], foreign[reply.field]);
      assert.notEqual(reply.original[reply.field], reply.returned[reply.field]);
      for (const name of ['attemptWire', 'callWire', 'providerBindingCid'].filter(name => name !== reply.field)) {
        assert.equal(reply.returned[name], reply.original[name]);
      }
      // A later attach observes the same unresolved Run; it grants neither a
      // new response lookup nor permission to retry the unknown provider call.
      const againPid = await executeHost(root, transport, 'unicode', 'disabled', phase);
      const repeated = JSON.parse(await readFile(join(root, `${phase}.json`), 'utf8'));
      assert.deepEqual(repeated.ref, originalRef);
      assert.deepEqual(repeated.calls, stopped.calls);
      assert.equal(repeated.sourceCalls, 1);
      const lookups = (await readFile(join(root, 'provider-lookups.jsonl'), 'utf8')).trim().split('\n').map(JSON.parse);
      assert.equal(lookups.length, 1);
      assert.equal(lookups[0].pid, restoredPid);
      assert.equal(new Set([foreignFirstPid, foreignRestoredPid, firstPid, restoredPid, againPid]).size, 5);
      refusals.push({field: reply.field, root, firstPid, restoredPid, againPid, ref: originalRef,
        status: repeated.terminal.status, sourceCalls: 1, providerCalls: 3, lookupCount: 1});
    }
    if (runtime !== undefined) await writeFile(join(runtime.evidenceDirectory, `source-recovery-${transport}-foreign-response.json`),
      JSON.stringify({revision: runtime.revision, transport, boundary: 'foreign-response', foreignRoot,
        foreignFirstPid, foreignRestoredPid, foreignRef, refusals, complete: true}, null, 2) + '\n');
  });

  test(`public ${transport} refuses modified original Model input custody after Host process exit`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-corrupt-'));
    t.after(() => t.diagnostic(`Retained modified-custody refusal: ${root}`));
    const firstPid = await executeHost(root, transport, 'unicode', 'disabled', 'stop-first-saved', 77);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.equal(stopped.calls.length, 2);
    const directory = join(root, 'host/checkpoints/attempts');
    const names = (await readdir(directory)).filter(name => name.startsWith('model-') && name.endsWith('.json'));
    assert.equal(names.length, 1);
    const ledger = JSON.parse(await readFile(join(directory, names[0]), 'utf8'));
    const inputs = ledger.holdings.filter(item => item.name === 'captured_input' && item.state === 'held');
    assert.equal(inputs.length, 1);
    const store = join(root, 'host/checkpoints/private-store');
    const holding = JSON.parse(await readFile(join(store, 'physical-holdings', `${inputs[0].holding_cid.slice(7)}.json`), 'utf8'));
    assert.equal(holding.objects.length, 1);
    const object = join(store, 'objects', holding.objects[0].cid.slice(7));
    const original = await readFile(object);
    // Preserve the authentic fixture bytes outside the Store inventory. Do
    // not change any receipt, identity, holding or declared object digest.
    await writeFile(join(root, 'original-model-input-custody.bin'), original, {mode: 0o600});
    const altered = Buffer.from(original); altered[altered.length - 1] ^= 1;
    await writeFile(object, altered);
    const restoredPid = await executeHost(root, transport, 'unicode', 'disabled', 'resume-corrupt');
    assert.notEqual(restoredPid, firstPid);
    const saved = JSON.parse(await readFile(join(root, 'corrupt-recovery.json'), 'utf8'));
    assert.deepEqual(saved.ref, JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8')));
    assert.equal(saved.terminal.status, 'needs_reconciliation');
    assert.equal(saved.terminal.result_available, false);
    assert.deepEqual(saved.calls, stopped.calls);
    assert.equal(saved.sourceCalls, 1);
    if (runtime !== undefined) await writeFile(join(runtime.evidenceDirectory, `source-recovery-${transport}-corrupt.json`),
      JSON.stringify({revision: runtime.revision, transport, boundary: 'modified-custody', root,
        firstPid, restoredPid, ref: saved.ref, status: saved.terminal.status,
        originalPhysicalCid: holding.objects[0].cid, sourceCalls: 1, providerCalls: 2,
        refusalCode: 'PublicationObjectCorrupt', complete: true}, null, 2) + '\n');
  });

  test(`public ${transport} retries failed continuation cleanup after original Run recovery and another process exit`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-cleanup-'));
    const directory = join(root, 'host/checkpoints/private-store/physical-holdings');
    t.after(async () => {
      await chmod(directory, 0o700).catch(() => {});
      t.diagnostic(`Retained cleanup recovery: ${root}`);
    });
    const firstPid = await executeHost(root, transport, 'unicode', 'disabled', 'stop-first-saved', 77);
    const pendingPid = await executeHost(root, transport, 'unicode', 'disabled', 'resume-cleanup-pending', 77);
    assert.notEqual(firstPid, pendingPid);
    const pending = JSON.parse(await readFile(join(root, 'resume-cleanup-pending.json'), 'utf8'));
    assert(pending.holdings.some(item => item.state === 'retiring' && item.cleanup_error === 'EACCES'));
    assert.equal(pending.sourceCalls, 1); assert.equal(pending.calls.length, 4);
    // Removing this test-owned filesystem refusal permits the durable Store
    // deletion Owner to retry after reopening, without any execution replay.
    await chmod(directory, 0o700);
    const retryPid = await executeHost(root, transport, 'unicode', 'disabled', 'resume-cleanup-retry');
    assert.equal(new Set([firstPid, pendingPid, retryPid]).size, 3);
    const recovered = JSON.parse(await readFile(join(root, 'resume-cleanup-retry.json'), 'utf8'));
    assert.deepEqual(recovered.ref, pending.ref);
    assert.deepEqual(recovered.calls, pending.calls);
    assert.equal(recovered.sourceCalls, 1);
    assert(recovered.holdings.every(item => item.state === 'retired'));
    assert.deepEqual(recovered.holdings.map(item => item.holding_cid).sort(), pending.holdings.map(item => item.holding_cid).sort());
    assert.equal(recovered.retainedRequestCount, pending.retainedRequestCount);
    const saved = JSON.parse(await readFile(join(root, 'recovery.json'), 'utf8'));
    assert.equal(saved.terminal.status, 'succeeded');
    const sink = await createCaptureSink({directory: join(root, 'evidence'),
      destination: 'local:source-multi-infer-evaluator', maxBytes: 131072,
      maxPendingBytes: 1048576, retentionMs: 300000, authorize: () => true});
    const evaluated = await evaluateOriginalInventory(sink, saved);
    if (runtime !== undefined) await writeFile(join(runtime.evidenceDirectory, `source-recovery-${transport}-cleanup.json`),
      JSON.stringify({revision: runtime.revision, transport, boundary: 'cleanup-retry', root,
        firstPid, pendingPid, retryPid, ref: recovered.ref, sourceCalls: 1, providerCalls: 4,
        retiredHoldings: recovered.holdings, retainedRequestCount: recovered.retainedRequestCount,
        evaluatorPids: evaluated.evaluatorPids, complete: true}, null, 2) + '\n');
  });

  test(`public ${transport} refuses restored unsent calls after current infer permission is rejected`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-denied-'));
    t.after(() => t.diagnostic(`Retained denied original Run: ${root}`));
    const firstPid = await executeHost(root, transport, 'unicode', 'disabled', 'stop-first-delegated', 77);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.equal(stopped.pid, firstPid);
    assert.equal(stopped.boundary, 'infer_model_settlement_committed');
    assert.equal(stopped.calls.length, 2);
    const restoredPid = await executeHost(root, transport, 'unicode', 'disabled', 'resume-denied');
    assert.notEqual(restoredPid, firstPid);
    const saved = JSON.parse(await readFile(join(root, 'denied-recovery.json'), 'utf8'));
    assert.deepEqual(saved.ref, JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8')));
    assert.equal(saved.terminal.status, 'needs_reconciliation');
    assert.equal(saved.refusalCode, 'ExecutionAuthorizationDenied');
    assert.equal(saved.terminal.result_available, false);
    assert.deepEqual(saved.calls, stopped.calls);
    assert.equal(saved.sourceCalls, 1);
    assert.equal((await readFile(join(root, 'provider-calls.jsonl'), 'utf8')).trim().split('\n').length, 2);
    if (runtime !== undefined) await writeFile(join(runtime.evidenceDirectory, `source-recovery-${transport}-denied.json`),
      JSON.stringify({revision: runtime.revision, transport, boundary: 'infer-rejected', root,
        firstPid, restoredPid, ref: saved.ref, status: saved.terminal.status,
        sourceCalls: 1, providerCalls: 2, refusalCode: saved.refusalCode, complete: true}, null, 2) + '\n');
  });

  test(`public ${transport} keeps an original unknown call and all required Evidence after process exit`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-unknown-'));
    t.after(() => t.diagnostic(`Retained original unknown call: ${root}`));
    const observationMode = transport === 'https' ? 'sampling-zero' : 'disabled';
    const firstPid = await executeHost(root, transport, 'unicode', observationMode, 'stop-provider-unknown', 77);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.equal(stopped.pid, firstPid);
    assert.equal(stopped.boundary, 'provider_sent_without_response');
    assert.equal(stopped.calls.length, 3);
    const restoredPid = await executeHost(root, transport, 'unicode', observationMode, 'resume-unknown');
    assert.notEqual(restoredPid, firstPid);
    const saved = JSON.parse(await readFile(join(root, 'unknown-recovery.json'), 'utf8'));
    assert.deepEqual(saved.ref, JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8')));
    assert.equal(saved.terminal.status, 'needs_reconciliation');
    assert.equal(saved.terminal.result_available, false);
    assert.equal(saved.sourceCalls, 1);
    assert.equal(saved.calls.length, 4);
    assert.equal(saved.observationMode, observationMode);
    assert.equal(saved.otlpRequests, 0);
    assert.deepEqual(saved.calls.slice(0, 3), stopped.calls);
    const second = saved.manifests.find(item => item.target === 'second_assessment').manifest;
    const unknown = second.items.find(item => item.modelCallSlotCid === stopped.calls[2].slotCid);
    assert.equal(unknown.status, 'incomplete');
    assert.equal(unknown.reason, 'ModelResultUnknown');
    assert.equal(unknown.inputKeyCid, expectedInputKeyCids[1]);
    const lookups = (await readFile(join(root, 'provider-lookups.jsonl'), 'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(lookups.length, 1);
    assert.equal(lookups[0].found, false);
    assert.equal(unknown.attemptCid, lookups[0].entry.attemptCid);
    const againPid = await executeHost(root, transport, 'unicode', observationMode, 'resume-unknown');
    assert.notEqual(againPid, restoredPid);
    assert.notEqual(againPid, firstPid);
    const repeated = JSON.parse(await readFile(join(root, 'unknown-recovery.json'), 'utf8'));
    assert.deepEqual(repeated.ref, saved.ref);
    assert.equal(repeated.terminal.status, 'needs_reconciliation');
    assert.equal(repeated.sourceCalls, 1);
    assert.deepEqual(repeated.calls, saved.calls);
    assert.equal(repeated.observationMode, observationMode);
    assert.equal(repeated.otlpRequests, 0);
    const repeatedLookups = (await readFile(join(root, 'provider-lookups.jsonl'), 'utf8')).trim().split('\n').map(JSON.parse);
    // A lookup or repeated public reconciliation is observation-only. The
    // already stopped unknown Run cannot automatically start another owner.
    assert.deepEqual(repeatedLookups, lookups);
    assert.equal(repeated.reconciliations.length, 2);
    assert(repeated.reconciliations.every(state => state.status === 'needs_reconciliation' &&
      state.result_available === false && state.run_id === saved.terminal.run_id));
    const sink = await createCaptureSink({directory: join(root, 'evidence'),
      destination: 'local:source-multi-infer-evaluator', maxBytes: 131072,
      maxPendingBytes: 1048576, retentionMs: 300000, authorize: () => true});
    const associations = [], evaluationPids = new Set();
    for (const receipt of [...saved.manifests].reverse()) {
      assert.equal(JSON.parse(receipt.manifest.policy.wire).unknown_provenance, true);
      for (const item of [...receipt.manifest.items].reverse()) {
        const sent = saved.calls.find(call => call.slotCid === item.modelCallSlotCid);
        assert(sent);
        assert.equal(item.inputKeyCid, expectedInputKeyCids[sent.key[0]]);
        if (item.status !== 'complete') continue;
        const job = {subject: saved.subject, evidence: {...receipt.manifest, ...item},
          caseId: `${receipt.target}-${item.modelCallSlotCid}`, expected: 'low', role: 'selection',
          deadline: Date.now() + 10000};
        const reply = await sink.withEvaluatorEvidence({subject: saved.subject,
          attemptCid: item.attemptCid, references: item.references}, resolvedEvidence => {
          const facts = checkModelCaptureCorrespondence(job, checkResolvedEvidence(job, resolvedEvidence));
          associations.push({target: receipt.target, key: facts.typedInput.key,
            keyContracts: facts.typedInput.key_contracts, text: facts.typedInput.inputs.text});
          return runEvaluatorProcess({job, resolvedEvidence, deadline: job.deadline,
            onProcess(pid) {assert.notEqual(pid, process.pid); evaluationPids.add(pid);}});
        });
        assert.equal(reply.score, 1);
      }
    }
    associations.sort((a, b) => a.target.localeCompare(b.target) || a.key[0] - b.key[0]);
    assert.deepEqual(associations, expectedItems.filter(item => item.target !== 'second_assessment' || item.key[0] !== 1));
    assert.equal(evaluationPids.size, 3);
    // Classification-only negative: the trial is the public Run above. This
    // adapter receives saved metadata and cannot start/retry any ActQL work.
    let trialReads = 0, evaluatorCalls = 0;
    const trial = await compareSourceInstructions({
      candidates: [{id: 'A', target: 'first_assessment', instructions: instructionsA},
        {id: 'B', target: 'first_assessment', instructions: instructionsB}],
      executeTrial: async () => {trialReads++; return {subject: saved.subject};},
      collectEvidence: async () => saved.manifests.flatMap(receipt => receipt.manifest.items.map(item => ({
        target: receipt.target, key: saved.calls.find(call => call.slotCid === item.modelCallSlotCid).key,
        evidence: {...receipt.manifest, ...item}}))),
      evaluate: async () => {evaluatorCalls++; assert.fail('incomplete Trial must not score a shortened batch');}});
    assert.equal(trial.status, 'incomplete');
    assert.equal(trial.reason, 'RequiredEvidenceUnavailable');
    assert.deepEqual(trial.records, []);
    assert.equal(trialReads, 1);
    assert.equal(evaluatorCalls, 0);
    assert.equal(sink.pendingBytes(), 0);
    assert.equal(sink.cleanupPending(), false);
    assert.equal((await readFile(join(root, 'provider-calls.jsonl'), 'utf8')).trim().split('\n').length, 4);
    if (runtime !== undefined) await writeFile(join(runtime.evidenceDirectory, `source-recovery-${transport}-unknown.json`),
      JSON.stringify({revision: runtime.revision, transport, boundary: 'unknown', root,
        firstPid, restoredPid, againPid, ref: saved.ref, status: repeated.terminal.status,
        sourceCalls: 1, providerCalls: 4, unknownAttemptCid: unknown.attemptCid,
        inventoryCount: 4, capturedItems: associations, evaluatorPids: [...evaluationPids],
        observationMode, otlpRequests: repeated.otlpRequests,
        trial: {status: trial.status, reason: trial.reason, records: trial.records}, complete: true}, null, 2) + '\n');
  });

  test(`public ${transport} recovers a provider-saved original response without resending its call`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-provider-recovery-'));
    let complete = false;
    t.after(async () => {
      if (complete && !runtime?.preserveArtifacts && process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') await rm(root, {recursive: true, force: true});
      else t.diagnostic(`Retained provider-saved original response: ${root}`);
    });
    const firstPid = await executeHost(root, transport, 'unicode', 'disabled', 'stop-provider-saved', 77);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.equal(stopped.pid, firstPid);
    assert.equal(stopped.boundary, 'provider_response_durable');
    assert.equal(stopped.sourceCalls, 1);
    assert.equal(stopped.calls.length, 3);
    const replies = (await readFile(join(root, 'provider-responses.jsonl'), 'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(replies.length, 3);
    assert.deepEqual(replies[2], stopped.response);
    assert.equal(replies[2].input.model_call_slot_cid, stopped.calls[2].slotCid);
    assert.equal(replies[2].input.semantic_request_cid, stopped.calls[2].semanticRequestCid);
    const originalRef = JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8'));
    const restoredPid = await executeHost(root, transport, 'unicode', 'disabled', 'resume-provider-saved');
    assert.notEqual(firstPid, restoredPid);
    const saved = JSON.parse(await readFile(join(root, 'recovery.json'), 'utf8'));
    assert.deepEqual(saved.ref, originalRef);
    assert.equal(saved.terminal.status, 'succeeded');
    assert.equal(saved.sourceCalls, 1);
    assert.equal(saved.calls.length, 4);
    assert.deepEqual(saved.calls.slice(0, 3), stopped.calls);
    assert.equal(saved.calls.filter(call => call.slotCid === stopped.calls[2].slotCid).length, 1);
    const sink = await createCaptureSink({directory: join(root, 'evidence'),
      destination: 'local:source-multi-infer-evaluator', maxBytes: 131072,
      maxPendingBytes: 1048576, retentionMs: 300000, authorize: () => true});
    const lookups = (await readFile(join(root, 'provider-lookups.jsonl'), 'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(lookups.length, 1);
    assert.equal(lookups[0].pid, restoredPid);
    assert.equal(lookups[0].found, true);
    assert.equal(lookups[0].entry.slotCid, stopped.calls[2].slotCid);
    const receipt = await sink.lookup(saved.subject, 'second_assessment');
    const recovered = receipt.manifest.items.find(item => item.modelCallSlotCid === stopped.calls[2].slotCid);
    assert(recovered);
    assert.equal(recovered.attemptCid, lookups[0].entry.attemptCid);
    await sink.withEvaluatorEvidence({subject: saved.subject, attemptCid: recovered.attemptCid,
      references: recovered.references}, resolvedEvidence => {
      const values = checkResolvedEvidence({subject: saved.subject,
        evidence: {...receipt.manifest, ...recovered}}, resolvedEvidence);
      const capture = JSON.parse(values.validation.captureBundleWire).captures.find(
        item => item.model_call_slot_cid === stopped.calls[2].slotCid);
      assert.deepEqual(capture.structured_response, JSON.parse(stopped.response.valueWire));
      assert.equal(capture.evidence.provider_request_id, stopped.response.providerRequestId);
      assert.equal(capture.evidence.provider_reported_model_id, stopped.response.providerModel);
      assert.equal(capture.evidence.observed_at, stopped.response.observedAt);
    });
    const evaluated = await evaluateOriginalInventory(sink, saved);
    await recordInterruptedAcceptance({transport, boundary: 'provider-saved', root,
      firstPid, restoredPid, saved, evaluated});
    complete = true;
  });

  test(`public ${transport} restores original approval materials for the second Source-backed INFER`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-approval-'));
    let complete = false;
    t.after(async () => {
      if (complete && !runtime?.preserveArtifacts && process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') await rm(root, {recursive: true, force: true});
      else t.diagnostic(`Retained Model approval Run: ${root}`);
    });
    const firstPid = await executeHost(root, transport, 'unicode', 'disabled', 'stop-second-waiting', 77);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.equal(stopped.pid, firstPid);
    assert.equal(stopped.boundary, 'infer_waiting_checkpoint');
    assert.equal(stopped.calls.length, 2);
    assert.equal(stopped.sourceCalls, 1);
    assert.deepEqual(stopped.calls.map(call => call.instructions), ['Return the original text.', 'Return the original text.']);
    const originalRef = JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8'));
    const restoredPid = await executeHost(root, transport, 'unicode', 'disabled', 'approve-second');
    assert.notEqual(firstPid, restoredPid);
    const saved = JSON.parse(await readFile(join(root, 'recovery.json'), 'utf8'));
    assert.deepEqual(saved.ref, originalRef);
    assert.equal(saved.terminal.status, 'succeeded');
    assert.equal(saved.sourceCalls, 1);
    assert.equal(saved.calls.length, 4);
    assert.deepEqual(saved.calls.slice(0, 2), stopped.calls);
    const sink = await createCaptureSink({directory: join(root, 'evidence'),
      destination: 'local:source-multi-infer-evaluator', maxBytes: 131072,
      maxPendingBytes: 1048576, retentionMs: 300000, authorize: () => true});
    const evaluated = await evaluateOriginalInventory(sink, saved);
    await recordInterruptedAcceptance({transport, boundary: 'second-approval', root,
      firstPid, restoredPid, saved, evaluated});
    complete = true;
  });

  test(`public ${transport} resumes the original two-INFER Run after the first response set is saved`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-recovery-'));
    let complete = false;
    t.after(async () => {
      if (complete && !runtime?.preserveArtifacts && process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') await rm(root, {recursive: true, force: true});
      else t.diagnostic(`Retained interrupted Run: ${root}`);
    });
    const firstPid = await executeHost(root, transport, 'unicode', 'disabled', 'stop-first-saved', 77);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.equal(stopped.pid, firstPid);
    assert.equal(stopped.boundary, 'infer_model_settlement_committed');
    assert.equal(stopped.calls.length, 2);
    assert.equal(stopped.sourceCalls, 1);
    assert.deepEqual(stopped.calls.map(call => call.instructions), ['Return the original text.', 'Return the original text.']);
    const originalRef = JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8'));
    const restoredPid = await executeHost(root, transport, 'unicode', 'disabled', 'resume');
    assert.notEqual(firstPid, restoredPid);
    const restored = JSON.parse(await readFile(join(root, 'recovery.json'), 'utf8'));
    assert.deepEqual(restored.ref, originalRef);
    assert.equal(restored.terminal.status, 'succeeded');
    assert.equal(restored.sourceCalls, 1);
    assert.equal(restored.calls.length, 4);
    assert.deepEqual(restored.calls.slice(0, 2), stopped.calls);
    assert.equal(new Set(restored.calls.map(call => call.slotCid)).size, 4);
    assert.equal(restored.manifests.length, 2);
    assert(restored.manifests.every(receipt => receipt.manifest.status === 'complete' && receipt.manifest.items.length === 2));
    const sink = await createCaptureSink({directory: join(root, 'evidence'),
      destination: 'local:source-multi-infer-evaluator', maxBytes: 131072,
      maxPendingBytes: 1048576, retentionMs: 300000, authorize: () => true});
    const evaluated = await evaluateOriginalInventory(sink, restored);
    assert.equal((await readFile(join(root, 'provider-calls.jsonl'), 'utf8')).trim().split('\n').length, 4);
    assert.equal((await readFile(join(root, 'source-calls.jsonl'), 'utf8')).trim().split('\n').length, 1);
    await recordInterruptedAcceptance({transport, boundary: 'first-saved', root,
      firstPid, restoredPid, saved: restored, evaluated});
    complete = true;
  });
}

for (const transport of ['local', 'https']) {
  test(`public ${transport} restores two Source-backed INFER Evidence inventories after Host process exit`, {timeout: 120000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-multi-infer-evidence-'));
    let complete = false;
    t.after(async () => {
      if (complete && !runtime?.preserveArtifacts) await rm(root, {recursive: true, force: true});
      else console.error(JSON.stringify({retainedSourceMultiInferEvidence: root}));
    });
    const hostPid = await executeHost(root, transport);
    const saved = JSON.parse(await readFile(join(root, 'recovery.json'), 'utf8'));
    assert.equal(saved.pid, hostPid);
    assert.notEqual(hostPid, process.pid);
    assert.equal(saved.sourceCalls, 1);
    assert.equal(saved.calls.length, 4);
    assert.equal(saved.terminal.status, 'succeeded');
    const {subject} = saved;
    const destination = 'local:source-multi-infer-evaluator';
    let readAllowed = true, sendAllowed = true, at = Date.now();
    // This process receives saved references only: it has no Source session,
    // Model provider, execution owner or replay/send callback.
    const sink = await createCaptureSink({directory: join(root, 'evidence'), destination,
      maxBytes: 131072, maxPendingBytes: 1048576, retentionMs: 300000,
      now: () => at,
      authorize: facts => readAllowed && facts.destination === destination &&
        (facts.purpose !== 'external_evaluation' || sendAllowed)});
    // Reuse the same identity and reversed-delivery checks after either
    // completed-Run restoration or interrupted original-Run continuation.
    const {associations} = await evaluateOriginalInventory(sink, saved);
    const receipt = await sink.lookup(subject, 'first_assessment');
    const item = receipt.manifest.items[0];
    const request = {subject, attemptCid: item.attemptCid, references: item.references};
    let evaluatorCalls = 0;
    const forbidden = () => {evaluatorCalls++; assert.fail('unavailable Evidence reached the evaluator');};
    readAllowed = false;
    await assert.rejects(sink.withEvaluatorEvidence(request, forbidden), {code: 'EvidenceReadDenied'});
    readAllowed = true; sendAllowed = false;
    await assert.rejects(sink.withEvaluatorEvidence(request, forbidden), {code: 'EvidenceExternalSendDenied'});
    sendAllowed = true;
    await assert.rejects(sink.withEvaluatorEvidence({...request,
      attemptCid: receipt.manifest.items[1].attemptCid}, forbidden), {code: 'EvidenceSubjectMismatch'});
    await assert.rejects(sink.withEvaluatorEvidence({...request,
      subject: {...subject, runDefinitionCid: 'sha256:' + 'b'.repeat(64)}}, forbidden), {code: 'EvidenceSubjectMismatch'});
    const altered = structuredClone(request);
    altered.references.typedInput.content.cid = 'sha256:' + 'b'.repeat(64);
    await assert.rejects(sink.withEvaluatorEvidence(altered, forbidden), {code: 'InvalidEvidenceReference'});
    const limited = await createCaptureSink({directory: join(root, 'evidence'), destination,
      maxBytes: 131072, maxPendingBytes: 32768, maxRetainedBytes: 1048576,
      retentionMs: 300000, authorize: () => true});
    await assert.rejects(limited.withEvaluatorEvidence(request, forbidden), {code: 'EvaluationBudgetExceeded'});
    assert.equal(limited.pendingBytes(), 0);
    await sink.withEvaluatorEvidence(request, async resolvedEvidence => {
      await assert.rejects(runEvaluatorProcess({job: {subject, evidence: {...receipt.manifest, ...item},
        caseId: 'invalid-evaluator-input', expected: 'unsupported-rubric', role: 'selection'},
        resolvedEvidence, deadline: Date.now() + 10000}), {code: 'EvaluatorInfrastructureFailure'});
    });
    at += 300000;
    await assert.rejects(sink.withEvaluatorEvidence(request, forbidden), {code: 'EvidenceExpired'});
    at -= 300000;
    await unlink(join(root, 'evidence', item.references.typedOutput.evidenceRefCid.slice(7)));
    await assert.rejects(sink.withEvaluatorEvidence(request, forbidden), {code: 'EvidenceOriginalMissing'});
    assert.equal(evaluatorCalls, 0);
    assert.equal(sink.pendingBytes(), 0);
    assert.equal(sink.cleanupPending(), false);
    assert.deepEqual(JSON.parse(await readFile(join(root, 'recovery.json'), 'utf8')), saved);
    if (runtime) await writeFile(join(runtime.evidenceDirectory, `source-evidence-${transport}-disabled.json`),
      JSON.stringify({revision: runtime.revision, transport, root, hostPid,
        sourceCalls: saved.sourceCalls, providerCalls: saved.calls.length, restoredItems: associations,
        refusalChecks: ['read', 'external-send', 'foreign-attempt', 'foreign-run', 'tamper', 'budget', 'expiry', 'missing'],
        runStatus: saved.terminal.status, otlpRequests: saved.otlpRequests, complete: true}, null, 2) + '\n');
  complete = true;
  });
}

for (const transport of ['local', 'https']) {
  test(`public ${transport} compares fresh two-INFER A/B Runs after process exit with real trace sampling zero`, {timeout: 180000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-source-infer-comparison-'));
    let complete = false;
    t.after(async () => {
      if (complete && !runtime?.preserveArtifacts) await rm(root, {recursive: true, force: true});
      else console.error(JSON.stringify({retainedSourceInferComparison: root}));
    });
    const candidates = [{id: 'A', target: 'first_assessment', instructions: instructionsA},
      {id: 'B', target: 'first_assessment', instructions: instructionsB}];
    assert.throws(() => instructionCandidate({...candidates[0], sourcePolicy: 'public'}, 'first_assessment'),
      {code: 'ForbiddenEvaluationEdit'});
    assert.throws(() => instructionCandidate({...candidates[0], target: 'second_assessment'}, 'first_assessment'),
      {code: 'ForbiddenEvaluationEdit'});
    const trials = [], evaluatorPids = new Set();
    const result = await compareSourceInstructions({candidates,
      async executeTrial({candidate, role}) {
        const scenario = role === 'final_test' ? 'final' : candidate.id;
        if (role === 'final_test') assert.equal(candidate.id, 'B', 'freeze the winner before the final input is submitted');
        const trialRoot = join(root, scenario); await mkdir(trialRoot);
        const pid = await executeHost(trialRoot, transport, scenario, 'sampling-zero');
        const saved = JSON.parse(await readFile(join(trialRoot, 'recovery.json'), 'utf8'));
        assert.equal(saved.pid, pid); assert.notEqual(pid, process.pid);
        assert.equal(saved.sourceCalls, 1); assert.equal(saved.calls.length, 4);
        assert.equal(saved.observationMode, 'sampling-zero'); assert.equal(saved.otlpRequests, 0);
        assert.equal(saved.terminal.status, 'succeeded');
        const sink = await createCaptureSink({directory: join(trialRoot, 'evidence'),
          destination: 'local:source-multi-infer-evaluator', maxBytes: 131072,
          maxPendingBytes: 1048576, retentionMs: 300000, authorize: () => true});
        const trial = {subject: saved.subject, sink, saved, candidate, role, trialRoot};
        trials.push(trial); return trial;
      },
      async collectEvidence(trial) {
        const items = [];
        // Independent two-item chunks, delivered in reverse target/call order.
        for (const target of ['second_assessment', 'first_assessment']) {
          const {manifest} = await trial.sink.lookup(trial.subject, target);
          assert.equal(manifest.status, 'complete'); assert.equal(manifest.items.length, 2);
          for (const original of [...manifest.items].reverse()) {
            const evidence = {...manifest, ...original,
              instructionCid: evaluationValueCid(target === 'first_assessment' ? trial.candidate.instructions : unchangedInstructions)};
            const request = {subject: trial.subject, attemptCid: original.attemptCid, references: original.references};
            const facts = await trial.sink.withEvaluatorEvidence(request, async resolved =>
              checkModelCaptureCorrespondence({subject: trial.subject, evidence},
                checkResolvedEvidence({subject: trial.subject, evidence}, resolved)));
            const entries = sourceEvaluationCases[trial.role === 'selection' ? 'selection' : 'final'];
            const entry = entries.find(entry => entry.key === facts.typedInput.key[0]);
            assert(entry); assert.deepEqual(facts.typedInput.key_contracts, [{type: 'number', nullable: false}]);
            assert.equal(facts.typedInput.inputs.text, entry.text);
            const sent = trial.saved.calls.filter(call => call.slotCid === original.modelCallSlotCid);
            assert.equal(sent.length, 1);
            assert.deepEqual(sent[0].key, facts.typedInput.key);
            assert.equal(sent[0].taskCid, facts.typedInput.model_task_contract_cid);
            assert.equal(sent[0].semanticRequestCid, facts.typedInput.semantic_request_cid);
            assert.deepEqual(facts.renderedInput, {instructions: sent[0].instructions, text: sent[0].text});
            items.push({target, key: facts.typedInput.key, evidence});
          }
        }
        return items;
      },
      evaluate: ({trial, item, job}) => trial.sink.withEvaluatorEvidence({subject: trial.subject,
        attemptCid: item.evidence.attemptCid, references: item.evidence.references}, resolvedEvidence =>
        runEvaluatorProcess({job, resolvedEvidence, deadline: job.deadline,
          onProcess(pid) {assert.notEqual(pid, process.pid); evaluatorPids.add(pid);}})),
    });
    assert.equal(result.status, 'scored', JSON.stringify(result));
    assert.equal(result.selectedCandidate, 'B');
    const scores = candidate => result.records.filter(record => record.candidateId === candidate &&
      record.role === 'selection' && record.target === 'first_assessment')
      .sort((a, b) => a.key[0] - b.key[0]).map(record => record.score);
    assert.deepEqual(scores('A'), [0, 1]); assert.deepEqual(scores('B'), [1, 1]);
    assert(result.records.every(record => record.reason.length > 0));
    assert.equal(result.records.filter(record => record.role === 'final_test').length, 4);
    assert(result.records.filter(record => record.role === 'final_test').every(record => record.score === 1));
    assert.equal(result.used.trials, 3); assert.equal(result.used.providerCalls, 12);
    assert.equal(result.used.evaluatorCalls, 12); assert.equal(evaluatorPids.size, 12);
    assert.equal(new Set(trials.map(trial => trial.subject.runDefinitionCid)).size, 3);
    assert.notEqual(trials[0].saved.modelTaskCids[0], trials[1].saved.modelTaskCids[0]);
    assert.equal(trials[0].saved.modelTaskCids[1], trials[1].saved.modelTaskCids[1]);
    assert.equal(trials[0].saved.originalSourcePolicy, trials[1].saved.originalSourcePolicy);
    for (const trial of trials) {
      assert.equal(trial.sink.pendingBytes(), 0); assert.equal(trial.sink.cleanupPending(), false);
      assert.deepEqual(JSON.parse(await readFile(join(trial.trialRoot, 'recovery.json'), 'utf8')), trial.saved);
    }
    if (runtime) await writeFile(join(runtime.evidenceDirectory, `source-comparison-${transport}-sampling-zero.json`),
      JSON.stringify({revision: runtime.revision, transport, root, result, evaluatorPids: [...evaluatorPids],
        runs: trials.map(({saved}) => saved), complete: true}, null, 2) + '\n');
    complete = true;
  });
}
