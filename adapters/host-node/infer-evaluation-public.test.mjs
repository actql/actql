import assert from 'node:assert/strict';
import test from 'node:test';
import {mkdtemp, readFile, rm, unlink, writeFile} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {createServer as httpServer} from 'node:http';
import {createServer as httpsServer} from 'node:https';
import {execFileSync} from 'node:child_process';
import {once} from 'node:events';
import {generateKeyPairSync} from 'node:crypto';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {createCaptureSink} from '../../examples/infer-evaluation/capture-sink.mjs';
import {compareInstructions, evaluationValueCid} from '../../examples/infer-evaluation/evaluate.mjs';
import {runEvaluatorProcess} from '../../examples/infer-evaluation/evaluator-process.mjs';
import {checkResolvedEvidence, checkModelCaptureCorrespondence} from '../../examples/infer-evaluation/evidence-reference.mjs';

const runtime = process.env.ACTQL_INFER_EVIDENCE_ACCEPTANCE_INPUTS === undefined ? undefined :
  JSON.parse(await readFile(process.env.ACTQL_INFER_EVIDENCE_ACCEPTANCE_INPUTS, 'utf8'));
const {connect} = runtime === undefined
  ? await (await import('./fixtures/source-node-client.mjs')).prepareSourceNodeClient({assemble: true, includeOtel: true, duckdb: false})
  : await import(runtime.client);
const {openInstalledRemoteHttpHost} = await import(runtime?.httpHost ?? '../../packages/local-node/http-host.mjs');
const {createNodeHostObservability} = await import(runtime?.observation ?? '../../packages/otel-node/index.mjs');
const {program, configuration, canonical, cid} = await import(runtime?.inferFixture ?? '../../scripts/fixtures/installed-infer-fixture.mjs');
const {providerBindingOriginals} = await import(runtime?.providerFixture ?? '../../scripts/fixtures/model-provider-binding-fixture.mjs');
const base = JSON.parse(await readFile(runtime?.environment ?? new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
const target = 'captured';
const candidates = [{id: 'A', target, instructions: 'Classify exact lowercase urgent.'},
  {id: 'B', target, instructions: 'Classify urgency without case sensitivity.'}];
const selectionCases = [{id: 'selection-upper', input: {id: 'a', text: 'URGENT'}, expected: 'high'}];
const finalCases = [{id: 'final-other', input: {id: 'a', text: 'ordinary'}, expected: 'low'}];
const limits = {trials: 3, providerCalls: 3, evaluatorCalls: 3, retainedBytes: 131072,
  deadlineMs: 120000, finalTrials: 1, finalProviderCalls: 1, finalEvaluatorCalls: 1, finalRetainedBytes: 32768};
const initialized = async action => {
  try {return await action();} catch (error) {
    const cause = error.primaryFailure ?? error.cause ?? error;
    throw new Error(`Synthetic Host initialization: ${cause.code ?? cause.message}`, {cause});
  }
};
const checked = result => {assert.equal(result.$tag, 1); return result._0;};

for (const [transport, observationMode] of [['local', 'disabled'], ['https', 'disabled'],
  ['local', 'sampling-zero'], ['https', 'sampling-zero']]) {
  test(`public ${transport} named INFER hands complete Evidence to an independent evaluator with OTel ${observationMode}`, {timeout: 120000}, async t => {
    const root = await mkdtemp(join(tmpdir(), 'actql-o3-public-'));
    let complete = false;
    const resources = [];
    let collector, otlpRequests = 0;
    const initialCertificates = getCACertificates('default');
    t.after(async () => {
      try {
        for (const resource of resources) {
          await resource.client.close();
          if (resource.server) {
            resource.server.closeAllConnections();
            await new Promise(resolve => resource.server.close(resolve));
          }
          await resource.host?.close();
          await resource.telemetry?.close();
        }
        if (collector) await new Promise(resolve => collector.close(resolve));
        if (complete && !runtime?.preserveArtifacts) await rm(root, {recursive: true, force: true});
        else console.error(JSON.stringify({retainedSyntheticEvidence: root}));
      } finally {setDefaultCACertificates(initialCertificates);}
    });
    const contexts = new Map(), runs = new Map(), pids = [];
    const owner = userInfo().username;
    const keys = generateKeyPairSync('ed25519');
    const privateKey = keys.privateKey.export({type: 'pkcs8', format: 'pem'});
    const publicKey = keys.publicKey.export({type: 'spki', format: 'pem'});
    let physicalCalls = 0;
    let certificate;
    if (transport === 'https') {
      execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'host.key',
        '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
      certificate = await readFile(join(root, 'host.crt'));
      setDefaultCACertificates([...initialCertificates, certificate.toString()]);
    }
    if (observationMode === 'sampling-zero') {
      collector = httpServer((request, response) => {
        otlpRequests++; request.resume(); response.end();
      }).listen(0, '127.0.0.1');
      await once(collector, 'listening');
    }
    for (const candidate of [...candidates, {id: 'limited', target, instructions: candidates[0].instructions}]) {
      const installed = configuration(base, {instructions: candidate.instructions});
      let readAllowed = true, sendAllowed = true, at = Date.now();
      const sink = await createCaptureSink({directory: join(root, candidate.id, 'evidence'),
        destination: 'local:independent-evaluator', maxBytes: 65536,
        maxPendingBytes: 1048576, retentionMs: 300000, now: () => at,
        authorize: facts => readAllowed && facts.destination === 'local:independent-evaluator' &&
          (facts.purpose !== 'external_evaluation' || sendAllowed)});
      const submitted = [];
      const telemetry = collector === undefined ? undefined : createNodeHostObservability({environment: false,
        traces: {endpoint: `http://127.0.0.1:${collector.address().port}/v1/traces`, sampleRate: 0}});
      if (telemetry) {
        assert.equal(telemetry.configuration().signals.traces.enabled, true);
        assert.equal(telemetry.configuration().signals.traces.sampleRate, 0);
      }
      const installation = {...(telemetry === undefined ? {} : {observation: telemetry.connection}), directory: join(root, candidate.id, 'host'),
        // Publish and run under this same finite authored policy. The Local
        // default row profile is a different Check Environment identity.
        hostCapacityPolicy: base.host_policy_profile.capacity,
        authorization: {leaseMs: 1000, reviewReaders: [owner],
          hostKey: {keyId: 'evidence-fixture-host', privateKey},
          reviewers: [{keyId: 'evidence-fixture-reviewer', reviewerId: 'evidence-fixture-reviewer',
            principalId: owner, publicKey}], accountConfiguration: canonical({
          version: 'actql-execution-account-config/0.1', account_id: 'evidence-fixture-owner',
          entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true},
            connection: {all: true}, resource: {all: true}, operation: {all: true}, exclusions: []}],
        })}, modelInstallation: installed.installation,
        inferEvidence: {target, destination: 'local:independent-evaluator', maxBytes: candidate.id === 'limited' ? 1 : 65536,
          authorize: binding => readAllowed && binding.policy.kind === 'data_policy' &&
            JSON.parse(binding.policy.wire).unknown_provenance === true, sink},
        registerModelProviders: moon => [{providerId: 'models/packed',
          bindingOriginals: providerBindingOriginals('models/packed', {selector: 'packed-risk-model'}),
          invoke() {assert.fail('unprepared call');},
          validatePrompt(taskCid, selector, wire) {
            return taskCid === installed.taskCid && selector === 'packed-risk-model' &&
              JSON.parse(wire).instructions === candidate.instructions;
          },
          quantityCapacity: {limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
            perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
          observeEgress: () => ({_0: 'public', _1: 'fixture-region', _2: false, _3: false}),
          physicalPreflight: request => {
            const text = JSON.parse(moon.clientProgramModelRequestInput(request, 'text'));
            const renderedInput = canonical({instructions: candidate.instructions, text});
            const contextManifest = canonical({promptTemplateCid: JSON.parse(installed.installation.environmentWire)
              .model_task_contracts[0].prompt_template_cid, selectedFields: ['text'],
              retrievalPolicy: 'none', knownExternalContext: [], providerHiddenContext: 'unknown'});
            return moon.clientProgramModelRequestPreflight(() => ({_0: true,
              _1: checked(moon.clientProgramModelPhysicalEvidencePlan(request, 1000n, 33n, 0n, 500n,
                renderedInput, contextManifest, () => {
                  physicalCalls++;
                  const payload = JSON.parse(renderedInput);
                  submitted.push(payload);
                  assert.deepEqual(Object.keys(payload), ['instructions', 'text']);
                  const urgent = candidate.id === 'A' ? payload.text === 'urgent' : payload.text.toLowerCase() === 'urgent';
                  return moon.clientProgramModelResponse(request, canonical({risk: urgent ? 'high' : 'low', reason: null}),
                    'packed-risk-model', 'independent-fixture-request', 1n, 2n, new Date().toISOString());
                }))}), () => true);
          },
        }]};
      let host, server, client;
      if (transport === 'https') {
        host = await initialized(() => openInstalledRemoteHttpHost({...installation,
          authenticate: header => header === 'Bearer synthetic-evaluator-fixture' ? owner : undefined}));
        server = httpsServer({key: await readFile(join(root, 'host.key')), cert: certificate}, host.handler).listen(0, '127.0.0.1');
        await once(server, 'listening');
        client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
          token: 'synthetic-evaluator-fixture', durability: 'durable'});
      } else client = await initialized(() => connect({mode: 'local', owner: 'local', durability: 'durable', installation}));
      resources.push({client, server, host, telemetry});
      console.log(JSON.stringify({transport, candidate: candidate.id, boundary: 'connected'}));
      contexts.set(candidate.id, {client, sink, installed, submitted, telemetry, hostDirectory: installation.directory,
        denyRead() {readAllowed = false;}, allowRead() {readAllowed = true;},
        denySend() {sendAllowed = false;}, allowSend() {sendAllowed = true;}, expire() {at += 300000;}});
    }
    const experiment = {target, candidates, selectionCases, finalCases, limits,
      async executeTrial(trial) {
        const began = Date.now();
        console.log(JSON.stringify({transport, candidate: trial.candidate.id, caseId: trial.case.id, boundary: 'submit'}));
        const context = contexts.get(trial.candidate.id);
        const source = structuredClone(program);
        source.stages[0].steps[0].values.rows = [trial.case.input];
        const submissionRef = context.client.newSubmission({nonce: trial.trialId});
        const run = await context.client.start(source, {submissionRef});
        assert.equal((await run.wait()).status, 'succeeded');
        t.diagnostic(`${transport} ${trial.candidate.id}/${trial.case.id}: succeeded after ${Date.now() - began}ms`);
        const rows = await run.result('answer').all();
        t.diagnostic(`${transport} ${trial.candidate.id}/${trial.case.id}: Result read after ${Date.now() - began}ms`);
        const risk = trial.candidate.id === 'A' && trial.case.input.text === 'URGENT' ? 'low' :
          trial.case.input.text.toLowerCase() === 'urgent' ? 'high' : 'low';
        assert.deepEqual(rows, [{assessment: {input_key: {id: 'a'}, outcome: 'ok', value: {reason: null, risk}}}]);
        assert.equal((await run.status()).status, 'succeeded');
        const subject = {runDefinitionCid: run.ref.runDefinitionCid, authorityScopeCid: run.ref.authorityScopeCid};
        runs.set(subject.runDefinitionCid, {context, run, trial, subject});
        return subject;
      },
      async readEvidence({subject}) {
        const {context, trial} = runs.get(subject.runDefinitionCid);
        const deadline = Date.now() + 10000;
        let receipt;
        for (;;) {
          try {receipt = await context.sink.lookup(subject, target); break;}
          catch (error) {if (error.code !== 'EvidenceOriginalMissing' || Date.now() >= deadline) throw error;}
          await new Promise(resolve => setTimeout(resolve, 10));
        }
        assert.equal(receipt.manifest.status, 'complete');
        assert.equal(receipt.manifest.modelTaskCid, context.installed.taskCid);
        assert.equal(receipt.manifest.items.length, 1);
        return {...receipt.manifest, ...receipt.manifest.items[0], caseId: trial.case.id, instructionCid: trial.candidate.instructionCid,
          inputCid: evaluationValueCid(trial.case.input)};
      },
      async evaluate(job) {
        const {context, trial} = runs.get(job.subject.runDefinitionCid);
        return context.sink.withEvaluatorEvidence({subject: job.subject, attemptCid: job.evidence.attemptCid,
          references: job.evidence.references}, resolvedEvidence => {
          const originals = checkModelCaptureCorrespondence(job, checkResolvedEvidence(job, resolvedEvidence));
          assert.deepEqual(originals.typedInput.input_contract, {additional_properties: false,
            fields: {text: {nullable: true, type: 'string'}}, nullable: false, type: 'object'});
          assert.deepEqual(originals.typedInput.output_contract, {additional_properties: false,
            fields: {reason: {nullable: true, type: 'string'}, risk: {nullable: false, type: 'string'}},
            nullable: false, type: 'object'});
          assert.deepEqual(originals.typedInput.key, ['a']);
          assert.deepEqual(originals.typedInput.key_contracts, [{nullable: false, type: 'string'}]);
          assert.deepEqual(originals.typedInput.inputs, {text: trial.case.input.text});
          assert.deepEqual(originals.renderedInput, {instructions: trial.candidate.instructions, text: trial.case.input.text});
          assert.deepEqual(originals.contextManifest, {promptTemplateCid: JSON.parse(context.installed.installation.environmentWire)
            .model_task_contracts[0].prompt_template_cid, selectedFields: ['text'], retrievalPolicy: 'none',
            knownExternalContext: [], providerHiddenContext: 'unknown'});
          return runEvaluatorProcess({job, resolvedEvidence,
            deadline: job.deadline, onProcess(pid) {pids.push(pid); assert.notEqual(pid, process.pid);}});
        });
      },
    };
    const result = await compareInstructions(experiment);
    assert.equal(result.status, 'scored', JSON.stringify(result));
    assert.equal(result.selectedCandidate, 'B');
    assert.deepEqual(result.records.map(record => record.score), [0, 1, 1]);
    assert.equal(physicalCalls, 3);
    assert.equal(new Set(pids).size, 3);
    await assert.rejects(compareInstructions({...experiment, candidates: [{...candidates[0], authority: 'forbidden'}, candidates[1]]}),
      {code: 'ForbiddenEvaluationEdit'});
    assert.equal(physicalCalls, 3);
    const exhausted = await compareInstructions({...experiment, limits: {...limits, trials: 1}});
    assert.equal(exhausted.status, 'incomplete');
    assert.equal(exhausted.reason, 'EvaluationBudgetExceeded');
    assert.equal(physicalCalls, 3);
    // A separately declared one-trial counterexample exercises optional
    // capture exhaustion through the same normal public Program, not a retry.
    const limited = contexts.get('limited');
    const limitedRun = await limited.client.start(program, {submissionRef: limited.client.newSubmission({nonce: 'optional-capture-limit'})});
    assert.equal((await limitedRun.wait()).status, 'succeeded');
    assert.deepEqual(await limitedRun.result('answer').all(), [{assessment: {input_key: {id: 'a'}, outcome: 'ok', value: {reason: null, risk: 'high'}}}]);
    const limitedSubject = {runDefinitionCid: limitedRun.ref.runDefinitionCid, authorityScopeCid: limitedRun.ref.authorityScopeCid};
    const limitDeadline = Date.now() + 10000;
    let limitReceipt;
    for (;;) {
      try {limitReceipt = await limited.sink.lookup(limitedSubject, target); break;}
      catch (error) {if (error.code !== 'EvidenceOriginalMissing' || Date.now() >= limitDeadline) throw error;}
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert.equal(limitReceipt.manifest.status, 'incomplete');
    assert.equal(limitReceipt.manifest.reason, 'EvaluationBudgetExceeded');
    assert.equal(physicalCalls, 4);
    let observedRecords = 0;
    for (const context of contexts.values()) {
      if (context.telemetry === undefined) continue;
      const database = new DatabaseSync(join(context.hostDirectory, 'requests', 'client-requests.sqlite3'), {readOnly: true});
      try {observedRecords += database.prepare('SELECT COALESCE(SUM(records), 0) AS n FROM client_observation_runs').get().n;}
      finally {database.close();}
      const drainDeadline = Date.now() + 5000;
      while (context.telemetry.status().projection.queued || context.telemetry.status().projection.active) {
        assert(Date.now() < drainDeadline, 'The configured observation adapter must settle');
        await new Promise(resolve => setTimeout(resolve, 5));
      }
      assert.equal(context.telemetry.status().signals.traces.sent, 0);
    }
    if (observationMode === 'sampling-zero') assert(observedRecords > 0, 'The actual Host observation connection must be active');
    assert.equal(otlpRequests, 0);
    const item = runs.values().next().value;
    const receipt = await item.context.sink.lookup(item.subject, target);
    const request = {subject: item.subject, attemptCid: receipt.manifest.items[0].attemptCid, references: receipt.manifest.items[0].references};
    for (const [change, reset, code] of [
      [() => item.context.denyRead(), () => item.context.allowRead(), 'EvidenceReadDenied'],
      [() => item.context.denySend(), () => item.context.allowSend(), 'EvidenceExternalSendDenied'],
      [() => {}, () => {}, 'EvidenceSubjectMismatch'],
    ]) {
      change();
      const submittedRequest = code === 'EvidenceSubjectMismatch' ? {...request, attemptCid: cid('other-attempt')} : request;
      await assert.rejects(item.context.sink.withEvaluatorEvidence(submittedRequest,
        () => assert.fail('refusal must precede external handoff')), {code});
      reset();
      assert.equal((await item.run.status()).status, 'succeeded');
      assert.equal(physicalCalls, 4);
    }
    await assert.rejects(item.context.sink.withEvaluatorEvidence({...request,
      subject: {...request.subject, runDefinitionCid: cid('other-run')}},
      () => assert.fail('other Run cannot retrieve original content')), {code: 'EvidenceSubjectMismatch'});
    let malformedEvaluatorStarts = 0;
    await assert.rejects(item.context.sink.withEvaluatorEvidence(request, resolvedEvidence =>
      runEvaluatorProcess({job: {subject: item.subject, evidence: {...receipt.manifest, ...receipt.manifest.items[0]},
        caseId: 'invalid-rubric-input', role: 'selection', expected: 'not-a-label'}, resolvedEvidence,
        deadline: Date.now() + 10000, onProcess() {malformedEvaluatorStarts++;}})),
    {code: 'EvaluatorInfrastructureFailure'});
    assert.equal(malformedEvaluatorStarts, 1);
    assert.equal((await item.run.status()).status, 'succeeded');
    assert.equal(physicalCalls, 4);
    await unlink(join(root, 'A', 'evidence', receipt.manifest.items[0].references.typedInput.evidenceRefCid.slice(7)));
    await assert.rejects(item.context.sink.withEvaluatorEvidence(request,
      () => assert.fail('missing original cannot be sent')), {code: 'EvidenceOriginalMissing'});
    assert.equal((await item.run.status()).status, 'succeeded');
    assert.equal(physicalCalls, 4);
    item.context.expire();
    await assert.rejects(item.context.sink.withEvaluatorEvidence(request,
      () => assert.fail('expired capture cannot be sent')), {code: 'EvidenceExpired'});
    assert.equal((await item.run.status()).status, 'succeeded');
    assert.equal(physicalCalls, 4);
    if (runtime?.evidenceDirectory) await writeFile(join(runtime.evidenceDirectory, `evaluation-${transport}-${observationMode}.json`),
      JSON.stringify({revision: runtime.revision, transport, observationMode, result, physicalCalls,
        evaluatorProcessIds: pids, observationRecords: observedRecords, otlpRequests,
        referencesRefused: ['read_revoked', 'external_send_denied', 'other_run', 'other_attempt', 'missing_original', 'expired'],
        programs: [...runs.values()].map(({trial, subject}) => ({subject, caseId: trial.case.id, candidateId: trial.candidate.id})),
        syntheticCustodyDirectory: root}, null, 2) + '\n');
    complete = true;
  });
}
