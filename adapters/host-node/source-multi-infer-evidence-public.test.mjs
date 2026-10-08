import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, mkdir, readFile, rm, unlink, writeFile} from 'node:fs/promises';
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
const {expectedItems, instructionsA, instructionsB, unchangedInstructions} =
  await import(runtime?.sourceInferFixture ?? '../../scripts/fixtures/source-multi-infer-evidence.mjs');
const worker = fileURLToPath(new URL('./source-multi-infer-evidence-worker.fixture.mjs', import.meta.url));
async function executeHost(root, transport, scenario = 'unicode', observationMode = 'disabled') {
  const child = spawn(process.execPath, [worker, root, transport, scenario, observationMode], {stdio: ['ignore', 'pipe', 'pipe']});
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
    assert.deepEqual(exit, {code: 0, signal: null}, output);
    return child.pid;
  } finally {clearTimeout(timer); clearTimeout(hardStop);}
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
    const associations = [], attempts = new Set();
    // Delivery order is deliberately reversed across targets and calls. Slots
    // are matched by their original identities, never the delivery ordinal.
    for (const target of ['second_assessment', 'first_assessment']) {
      const receipt = await sink.lookup(subject, target);
      assert.equal(receipt.manifest.status, 'complete');
      assert.equal(receipt.manifest.items.length, 2);
      for (const item of [...receipt.manifest.items].reverse()) {
        const job = {subject, evidence: {...receipt.manifest, ...item}, caseId: `${target}-${item.modelCallSlotCid}`,
          expected: 'low', role: 'selection', deadline: Date.now() + 10000};
        const reply = await sink.withEvaluatorEvidence({subject, attemptCid: item.attemptCid,
          references: item.references}, async resolvedEvidence => {
          const facts = checkModelCaptureCorrespondence(job, checkResolvedEvidence(job, resolvedEvidence));
          associations.push({target, key: facts.typedInput.key,
            keyContracts: facts.typedInput.key_contracts, text: facts.typedInput.inputs.text});
          attempts.add(item.attemptCid);
          assert.equal(JSON.parse(item.references.typedInput.policy.wire).unknown_provenance, true);
          assert.deepEqual(JSON.parse(item.references.typedInput.policy.wire).source_data_policy_cids,
            [saved.originalSourcePolicy]);
          return runEvaluatorProcess({job, resolvedEvidence, deadline: job.deadline,
            onProcess(pid) {assert.notEqual(pid, process.pid);}});
        });
        assert.equal(reply.score, 1);
      }
    }
    associations.sort((a, b) => a.target.localeCompare(b.target) || a.key[0] - b.key[0]);
    assert.deepEqual(associations, expectedItems);
    assert.equal(attempts.size, 4);
    assert.equal(saved.calls.length, 4);
    assert.equal(sink.pendingBytes(), 0);
    assert.equal(sink.cleanupPending(), false);
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
