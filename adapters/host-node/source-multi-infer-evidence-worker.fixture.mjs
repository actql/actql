import assert from 'node:assert/strict';
import {chmod, readFile, readdir, writeFile} from 'node:fs/promises';
import {appendFileSync, closeSync, existsSync, fsyncSync, openSync, readFileSync, writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {generateKeyPairSync, sign} from 'node:crypto';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {inspect} from 'node:util';
import {createCaptureSink} from '../../examples/infer-evaluation/capture-sink.mjs';

import {createServer as httpsServer} from 'node:https';
import {createServer as httpServer} from 'node:http';
import {execFileSync} from 'node:child_process';
import {once} from 'node:events';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';

const runtime = process.env.ACTQL_INFER_EVIDENCE_ACCEPTANCE_INPUTS === undefined ? undefined :
  JSON.parse(await readFile(process.env.ACTQL_INFER_EVIDENCE_ACCEPTANCE_INPUTS, 'utf8'));
const {connect} = runtime === undefined
  ? await (await import('./fixtures/source-node-client.mjs')).prepareSourceNodeClient({assemble: false})
  : await import(runtime.client);
const {openInstalledRemoteHttpHost} = await import(runtime?.httpHost ?? '../../packages/local-node/http-host.mjs');
const {createNodeHostObservability} = await import(runtime?.observation ?? '../../packages/otel-node/index.mjs');
const {providerBindingOriginals} = await import(runtime?.providerFixture ?? '../../scripts/fixtures/model-provider-binding-fixture.mjs');
const {canonical} = await import(runtime?.inferFixture ?? '../../scripts/fixtures/installed-infer-fixture.mjs');
const {program, modelConfiguration, sourceEnvironment, scenarios, instructionsA, expectedColumns} =
  await import(runtime?.sourceInferFixture ?? '../../scripts/fixtures/source-multi-infer-evidence.mjs');
const checked = result => {assert.equal(result.$tag, 1); return result._0;};
const [root, transport, scenarioName = 'unicode', observationMode = 'disabled', phase = 'complete'] = process.argv.slice(2);
assert(root && ['local', 'https'].includes(transport) && scenarios[scenarioName]);
const scenario = scenarios[scenarioName];
const approval = ['stop-second-waiting', 'approve-second', 'stop-first-delegated', 'resume-denied'].includes(phase);
let client, host, server, collector, telemetry, otlpRequests = 0;
try {
  const base = JSON.parse(await readFile(runtime?.environment ?? new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const source = sourceEnvironment(JSON.parse(await readFile(runtime?.sourceEnvironment ?? new URL('./fixtures/query-amount-environment.json', import.meta.url), 'utf8')),
    base.host_policy_profile);
  const database = join(root, 'source.duckdb');
  const {DuckDBInstance} = createRequire(runtime?.duckdbRequire ?? new URL('../connectors/duckdb/node/package.json', import.meta.url))('@duckdb/node-api');
  const initialize = !existsSync(database);
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    if (initialize) await connection.run('CREATE TABLE records(id DOUBLE, amount VARCHAR)');
    for (const row of initialize ? scenario.rows : []) {
      const insert = await connection.prepare('INSERT INTO records VALUES (?, ?)');
      try {insert.bindDouble(1, row.id); insert.bindVarchar(2, row.amount); await insert.run();}
      finally {insert.destroySync();}
    }
  } finally {connection.closeSync(); instance.closeSync();}
  const installed = modelConfiguration(base, scenario);
  const accountConfiguration = canonical({version: 'actql-execution-account-config/0.1', account_id: 'source-evidence-fixture',
    entries: approval ? [
      {entry_id: 'first-infer', outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {any_of: [installed.tasks[0].contract_cid]}, operation: {any_of: ['infer']}, exclusions: []},
      {entry_id: 'second-infer', outcome: 'delegate', principal: {all: true}, connection: {all: true},
        resource: {any_of: [installed.tasks[1].contract_cid]}, operation: {any_of: ['infer']}, exclusions: []},
      {entry_id: 'source', outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['read', 'write']}, exclusions: []},
    ] : [{entry_id: 'allow', outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {all: true}, exclusions: []}]});
  const sourceProfilePath = join(root, 'source-profile.json');
  await writeFile(sourceProfilePath, canonical({version: 'actql-installed-duckdb-source/0.1', database,
    schema: 'main', table: 'records', sourceRef: 'connector://crm/main/r#v',
    acquisitionPlanning: {policy: 'priority', priority: ['nativeQuery', 'broadQuery']},
    checkEnvironmentWire: canonical(source), accountConfigurationWire: accountConfiguration}));
  const keyPath = join(root, 'host-keys.json');
  if (!existsSync(keyPath)) {
    const keys = generateKeyPairSync('ed25519');
    await writeFile(keyPath, JSON.stringify({privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'}),
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}), {mode: 0o600});
  }
  const keys = JSON.parse(await readFile(keyPath, 'utf8'));
  const callPath = join(root, 'provider-calls.jsonl');
  const sourcePath = join(root, 'source-calls.jsonl');
  const readLines = path => existsSync(path) ? readFileSync(path, 'utf8').trim().split('\n').filter(Boolean).map(JSON.parse) : [];
  const observed = [], calls = readLines(callPath);
  let cleanupRefusalInstalled = false;
  const persistProviderResponse = response => {
    const path = join(root, 'provider-responses.jsonl');
    const descriptor = openSync(path, 'a', 0o600);
    try {writeFileSync(descriptor, JSON.stringify(response) + '\n'); fsyncSync(descriptor);}
    finally {closeSync(descriptor);}
  };
  let settlements = 0;
  const destination = 'local:source-multi-infer-evaluator';
  const sink = await createCaptureSink({directory: join(root, 'evidence'), destination,
    maxBytes: 131072, maxPendingBytes: 1048576, retentionMs: 300000,
    authorize: facts => facts.destination === destination});
  if (observationMode === 'sampling-zero') {
    collector = httpServer((request, response) => {otlpRequests++; request.resume(); response.end();}).listen(0, '127.0.0.1');
    await once(collector, 'listening');
    telemetry = createNodeHostObservability({environment: false,
      traces: {endpoint: `http://127.0.0.1:${collector.address().port}/v1/traces`, sampleRate: 0}});
    assert.equal(telemetry.configuration().signals.traces.enabled, true);
    assert.equal(telemetry.configuration().signals.traces.sampleRate, 0);
  } else assert.equal(observationMode, 'disabled');
  const installation = {
    ...(telemetry === undefined ? {} : {observation: telemetry.connection}),
    directory: join(root, 'host'), sourceProfilePath, modelInstallation: installed.installation,
    // Both publications retain the same finite Host policy across processes.
    hostCapacityPolicy: base.host_policy_profile.capacity,
    inferEvidence: {target: ['first_assessment', 'second_assessment'], destination,
      maxBytes: 262144, sink, authorize: binding =>
        JSON.parse(binding.policy.wire).unknown_provenance === true},
    authorization: {accountConfiguration,
      ...(phase === 'resume-denied' ? {decide: view => {
        observed.push({name: 'current_infer_rejected', detail: view.subject});
        return {decision: 'reject', subject: view.subject, authority: 'fixture-reviewer'};
      }} : {}),
      hostKey: {keyId: 'fixture-host', privateKey: keys.privateKey},
      reviewers: [{keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer', principalId: userInfo().username,
        publicKey: keys.publicKey}],
      reviewReaders: [userInfo().username],
      observe(name, detail) {
        observed.push({name, detail});
        if (name === 'acquisition_started') appendFileSync(sourcePath, JSON.stringify({pid: process.pid, detail}) + '\n');
      },
      async faultInjection(name, detail) {
        if (phase === 'resume-cleanup-pending' && name === 'infer_private_holding_commit' &&
            detail.role === 'model_capture_bundle' && calls.length === 4 && !cleanupRefusalInstalled) {
          // Deny physical unlink in this fixture's actual continuation Store.
          // Model settlement uses the separate publication Store, and the
          // already retained inputs remain readable until terminal cleanup.
          await chmod(join(root, 'host/checkpoints/private-store/physical-holdings'), 0o500);
          cleanupRefusalInstalled = true;
        }
        if (['stop-first-saved', 'stop-first-delegated'].includes(phase) && name === 'infer_model_settlement_committed' && ++settlements === 2) {
          writeFileSync(join(root, 'stop.json'), JSON.stringify({pid: process.pid, boundary: name, detail,
            calls, sourceCalls: readLines(sourcePath).length}));
          process.exit(77);
        }
        if (phase === 'stop-second-waiting' && name === 'infer_waiting_checkpoint') {
          const page = await client.checkpoints();
          const summary = page.items.find(item => item.checkpointCid === detail.checkpointCid);
          assert(summary);
          const review = JSON.parse(new TextDecoder().decode((await client.reviewCheckpoint(summary)).bytes));
          assert.equal(calls.length, 2);
          writeFileSync(join(root, 'stop.json'), JSON.stringify({pid: process.pid, boundary: name, detail,
            calls, sourceCalls: readLines(sourcePath).length, summary, review}));
          process.exit(77);
        }
      }},
    registerModelProviders: moon => [{providerId: 'models/packed',
      bindingOriginals: providerBindingOriginals('models/packed', {selector: 'packed-risk-model'}),
      invoke() {assert.fail('unprepared Model dispatch');},
      reconcileResponse({request, inputFrame, entry, callWire, attemptWire, providerBindingCid}) {
        assert.equal(entry.attemptIndex, 1, 'the installed provider has no retry path');
        const input = JSON.parse(inputFrame);
        assert.equal(input.model_call_slot_cid, entry.slotCid);
        const replies = readLines(join(root, 'provider-responses.jsonl'));
        const matches = replies.filter(reply => reply.input.model_call_slot_cid === entry.slotCid);
        assert(matches.length <= 1, 'one original response per owner-issued slot');
        appendFileSync(join(root, 'provider-lookups.jsonl'), JSON.stringify({pid: process.pid,
          entry, attemptWire, callWire, providerBindingCid, found: matches.length === 1}) + '\n');
        if (matches.length === 0) return undefined;
        const original = matches[0];
        assert.deepEqual(original.input, input);
        const reply = {attemptWire, callWire, providerBindingCid,
          response: moon.clientProgramModelResponse(request, original.valueWire,
            original.providerModel, original.providerRequestId, BigInt(original.inputTokens),
            BigInt(original.outputTokens), original.observedAt)};
        if (['resume-foreign-attempt', 'resume-foreign-call'].includes(phase)) {
          // These are authentic materials observed in another executed Run.
          // Change one binding only; retain this Run's actual response body.
          const foreign = JSON.parse(readFileSync(join(root, 'foreign-response-reference.json'), 'utf8'));
          const field = phase === 'resume-foreign-attempt' ? 'attemptWire' : 'callWire';
          assert.notEqual(foreign[field], reply[field]);
          reply[field] = foreign[field];
          writeFileSync(join(root, `${phase}-reply.json`), JSON.stringify({field,
            original: {attemptWire, callWire, providerBindingCid},
            returned: {attemptWire: reply.attemptWire, callWire: reply.callWire, providerBindingCid}}));
        }
        return reply;
      },
      validatePrompt(taskCid, selector, wire) {
        return installed.tasks.some(task => task.contract_cid === taskCid) && selector === 'packed-risk-model' &&
          JSON.parse(wire).format === 'packed-risk/0.1';
      },
      // Two admitted two-call contracts each retain 1000ms. The shared Run
      // covers both complete 66-token/1000ms envelopes without refunding either.
      quantityCapacity: {limits: {tokens: 132n, costUnits: 0n, durationMs: 2000n},
        perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
      observeEgress: () => ({_0: 'public', _1: 'fixture-region', _2: false, _3: false}),
      physicalPreflight: request => {
        const text = JSON.parse(moon.clientProgramModelRequestInput(request, 'text'));
        const input = JSON.parse(moon.clientProgramModelRequestInputFrame(request));
        const task = installed.tasks.find(value => value.contract_cid === input.model_task_contract_cid);
        assert(task);
        const first = task.task_id === 'model-task:first-assessment.v1';
        const instructions = first ? scenario.firstInstructions : scenario.secondInstructions;
        const renderedInput = canonical({instructions, text});
        const contextManifest = canonical({promptTemplateCid: task.prompt_template_cid,
          selectedFields: ['text'], retrievalPolicy: 'none', knownExternalContext: [], providerHiddenContext: 'unknown'});
        return moon.clientProgramModelRequestPreflight(() => ({_0: true,
          _1: checked(moon.clientProgramModelPhysicalEvidencePlan(request, 1000n, 33n, 0n, 500n,
            renderedInput, contextManifest, () => {
            calls.push({slotCid: input.model_call_slot_cid,
              semanticRequestCid: input.semantic_request_cid,
              taskCid: task.contract_cid, key: input.key, instructions, text});
            appendFileSync(callPath, JSON.stringify(calls.at(-1)) + '\n');
            const urgent = first && scenarioName !== 'unicode' &&
              (instructions === instructionsA ? text === 'urgent' : text.toLowerCase() === 'urgent');
            const response = {input, valueWire: canonical({risk: urgent ? 'high' : 'low', reason: text}),
              providerModel: 'packed-risk-model', providerRequestId: `source-evidence-${calls.length}`,
              inputTokens: '1', outputTokens: '2', observedAt: new Date().toISOString()};
            if (phase === 'stop-provider-unknown' && !first) {
              assert.equal(calls.length, 3);
              // The actual provider callback has been entered after durable
              // send-start, but neither side has a definitive original reply.
              writeFileSync(join(root, 'stop.json'), JSON.stringify({pid: process.pid,
                boundary: 'provider_sent_without_response',
                calls, sourceCalls: readLines(sourcePath).length}));
              process.exit(77);
            }
            persistProviderResponse(response);
            if (phase === 'stop-provider-saved' && !first) {
              // This is the actual retained physical invocation, reached only
              // after the common owner committed send-start. The provider has
              // fsynced its reply; no ModelResponse has reached the Host yet.
              assert.equal(calls.length, 3);
              writeFileSync(join(root, 'stop.json'), JSON.stringify({pid: process.pid,
                boundary: 'provider_response_durable', response,
                calls, sourceCalls: readLines(sourcePath).length}));
              process.exit(77);
            }
            return moon.clientProgramModelResponse(request, response.valueWire,
              response.providerModel, response.providerRequestId, 1n, 2n, response.observedAt);
          }))}), () => true);
      },
    }],
  };
  if (transport === 'https') {
    if (!existsSync(join(root, 'host.crt'))) execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'host.key', '-out', 'host.crt', '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], {cwd: root, stdio: 'ignore'});
    const certificate = await readFile(join(root, 'host.crt'));
    setDefaultCACertificates([...getCACertificates('default'), certificate.toString()]);
    host = await openInstalledRemoteHttpHost({...installation, authenticate: header => header === 'Bearer synthetic-evidence' ? userInfo().username : undefined});
    server = httpsServer({key: await readFile(join(root, 'host.key')), cert: certificate}, host.handler).listen(0, '127.0.0.1');
    await once(server, 'listening');
    client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'synthetic-evidence', durability: 'durable'});
  } else client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
  let run;
  if (['resume', 'approve-second', 'resume-provider-saved', 'resume-unknown', 'resume-denied',
    'resume-cleanup-pending', 'resume-cleanup-retry', 'resume-corrupt',
    'resume-foreign-attempt', 'resume-foreign-call'].includes(phase)) {
    const submissionRef = JSON.parse(await readFile(join(root, 'submission-ref.json'), 'utf8'));
    const found = await client.lookupSubmission(submissionRef);
    assert.equal(found.kind, 'ready', inspect(found));
    run = await client.attach(found.admission.ref);
    assert.deepEqual(run.ref, JSON.parse(await readFile(join(root, 'run-ref.json'), 'utf8')));
    if (phase === 'approve-second') {
      const saved = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
      const page = await client.checkpoints();
      const summary = page.items.find(item => item.checkpointCid === saved.summary.checkpointCid);
      assert.deepEqual(summary, saved.summary);
      const review = JSON.parse(new TextDecoder().decode((await client.reviewCheckpoint(summary)).bytes));
      assert.deepEqual(review, saved.review);
      assert.equal(calls.length, 2, 'the second INFER must remain unsent before approval');
      assert.equal((await run.status()).status, 'waiting_checkpoint');
      const resolution = await client.resolveCheckpoints([{checkpoint: summary, decision: 'approved'}],
        {signer: {keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer',
          sign: bytes => sign(null, bytes, keys.privateKey)}});
      assert.equal(resolution.results[0].status, 'committed');
    }
  } else {
    const submissionRef = client.newSubmission({nonce: 'source-two-infers'});
    await writeFile(join(root, 'submission-ref.json'), JSON.stringify(submissionRef));
    run = await client.start(program, {submissionRef}).catch(error => {
      console.error(inspect({error, observed, calls}, {depth: 12})); throw error;
    });
    await writeFile(join(root, 'run-ref.json'), JSON.stringify(run.ref));
  }
  // A public wait may expose durable Waiting before the driver's stop hook.
  // Only the confirmed hook above ends this child; the parent bounds failure.
  if (phase === 'stop-second-waiting') {
    process.once('beforeExit', () => console.error(inspect({observed, calls}, {depth: 8})));
    await new Promise(() => {});
  }
  let terminal = await run.wait();
  // Resolving a Checkpoint publishes Resuming before its background owner
  // returns. Observe that transition through the SDK; it is not completion.
  while (phase === 'approve-second' && ['resuming', 'running'].includes(terminal.status)) {
    await new Promise(resolve => setTimeout(resolve, 20));
    terminal = await run.wait();
  }
  if (['resume-foreign-attempt', 'resume-foreign-call'].includes(phase)) {
    assert.equal(terminal.status, 'needs_reconciliation');
    assert.equal(terminal.result_available, false);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.deepEqual(calls, stopped.calls);
    assert.equal(calls.length, 3, 'a foreign reply cannot admit a response or start the next call');
    assert.equal(readLines(sourcePath).length, 1);
    const reconciliations = [await run.reconcile(), await run.reconcile()];
    assert(reconciliations.every(state => state.status === 'needs_reconciliation' &&
      state.result_available === false && state.run_id === terminal.run_id));
    assert.equal(calls.length, 3);
    await writeFile(join(root, `${phase}.json`), JSON.stringify({pid: process.pid,
      ref: run.ref, terminal, reconciliations, calls, observed, sourceCalls: readLines(sourcePath).length}));
  } else if (phase === 'resume-corrupt') {
    assert.equal(terminal.status, 'needs_reconciliation');
    assert.equal(terminal.result_available, false);
    assert(observed.some(event => event.name === 'model_recovery_failed' &&
      event.detail.code === 'PublicationObjectCorrupt'));
    assert.equal(calls.length, 2);
    assert.equal(readLines(sourcePath).length, 1);
    await writeFile(join(root, 'corrupt-recovery.json'), JSON.stringify({pid: process.pid,
      ref: run.ref, terminal, calls, observed, sourceCalls: readLines(sourcePath).length}));
  } else if (phase === 'resume-denied') {
    await writeFile(join(root, 'denied-run-diagnostic.json'), JSON.stringify({pid: process.pid,
      ref: run.ref, terminal, calls, observed, sourceCalls: readLines(sourcePath).length}));
    // The existing restoration Owner refuses this new authorization without
    // inventing a terminal outcome for the previously interrupted execution.
    assert.equal(terminal.status, 'needs_reconciliation');
    assert.equal(terminal.result_available, false);
    assert(observed.some(event => event.name === 'model_resume_failed' &&
      event.detail.code === 'ExecutionAuthorizationDenied'));
    const rejected = observed.filter(event => event.name === 'current_infer_rejected');
    assert.equal(rejected.length, 1);
    assert.equal(rejected[0].detail.operation, 'infer');
    assert.equal(rejected[0].detail.resource, installed.tasks[1].contract_cid);
    assert.equal(calls.length, 2, 'restoration cannot send after current infer permission is rejected');
    assert.equal(readLines(sourcePath).length, 1);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.deepEqual(calls, stopped.calls);
    await writeFile(join(root, 'denied-recovery.json'), JSON.stringify({pid: process.pid, ref: run.ref,
      terminal, calls, observed, refusalCode: 'ExecutionAuthorizationDenied', sourceCalls: readLines(sourcePath).length}));
  } else if (phase === 'resume-unknown') {
    assert.equal(terminal.status, 'needs_reconciliation');
    assert.equal(terminal.result_available, false);
    assert.equal(calls.length, 4, 'only the remaining formally unsent slot may continue');
    assert.equal(readLines(sourcePath).length, 1);
    const stopped = JSON.parse(await readFile(join(root, 'stop.json'), 'utf8'));
    assert.deepEqual(calls.slice(0, 3), stopped.calls);
    const reconciliations = [await run.reconcile(), await run.reconcile()];
    assert(reconciliations.every(state => state.status === 'needs_reconciliation' &&
      state.result_available === false && state.run_id === terminal.run_id));
    assert.equal(calls.length, 4);
    const subject = {runDefinitionCid: run.ref.runDefinitionCid, authorityScopeCid: run.ref.authorityScopeCid};
    await writeFile(join(root, 'unknown-run.json'), JSON.stringify({subject, pid: process.pid,
      ref: run.ref, terminal, calls, sourceCalls: readLines(sourcePath).length, observed}));
    const manifests = [];
    for (const target of ['first_assessment', 'second_assessment']) {
      const receipt = await sink.lookup(subject, target);
      assert.equal(receipt.manifest.items.length, 2, 'unknown calls remain required inventory entries');
      assert.equal(receipt.manifest.status, target === 'first_assessment' ? 'complete' : 'incomplete');
      manifests.push(receipt);
    }
    const unknown = manifests[1].manifest.items.find(item => item.modelCallSlotCid === stopped.calls[2].slotCid);
    assert.equal(unknown.status, 'incomplete');
    assert.equal(unknown.reason, 'ModelResultUnknown');
    assert.equal(manifests[1].manifest.items.filter(item => item.status === 'complete').length, 1);
    assert.equal(sink.pendingBytes(), 0);
    assert.equal(sink.cleanupPending(), false);
    await telemetry?.close(); telemetry = undefined;
    assert.equal(otlpRequests, 0);
    await writeFile(join(root, 'unknown-recovery.json'), JSON.stringify({subject, manifests,
      pid: process.pid, ref: run.ref, terminal, reconciliations,
      observationMode, otlpRequests, calls, sourceCalls: readLines(sourcePath).length}));
    process.exitCode = 0;
  } else {
  if (terminal.status !== 'succeeded') {
    await writeFile(join(root, 'failed-recovery.json'), JSON.stringify({pid: process.pid,
      phase, ref: run.ref, terminal, observed, calls, sourceCalls: readLines(sourcePath).length}));
    console.error(inspect({terminal, observed, calls}, {depth: 8}));
  }
  assert.equal(terminal.status, 'succeeded');
  const result = run.result('answer');
  const description = await result.describe();
  assert.deepEqual(description.columns, expectedColumns);
  assert.deepEqual(await result.all(), scenario.expected);
  assert.equal(calls.length, 4);
  assert.equal(readLines(sourcePath).length, 1);
  if (scenarioName === 'unicode' && phase === 'complete') {
    const serial = structuredClone(program);
    serial.id = 'unsupported-serial-infer-evidence';
    serial.stages[2].inputs.items.result.stage = 'first';
    serial.stages[2].steps[1].infer.input = {text: {literal: 'downstream'}};
    // The original bound Check discloses this Host's downstream Model-input
    // implementation limit. This is not a complete language-validity verdict.
    await assert.rejects(client.start(serial,
      {submissionRef: client.newSubmission({nonce: 'serial-infer-negative'})}),
      error => error.code === 'SubmissionPreparationFailed' &&
        error.outcome?.problem?.code === 'ClientProgramUnsupported' &&
        error.outcome.problem.classification === 'implementation_limit');
    assert.equal(calls.length, 4, 'the refused downstream INFER must not send');
    assert.equal(observed.filter(item => item.name === 'acquisition_started').length, 1);
  }
  const subject = {runDefinitionCid: run.ref.runDefinitionCid, authorityScopeCid: run.ref.authorityScopeCid};

  const manifests = [];
  for (const target of ['first_assessment', 'second_assessment']) {
    const receipt = await sink.lookup(subject, target);
    assert.equal(receipt.manifest.status, 'complete');
    assert.equal(receipt.manifest.items.length, 2);
    manifests.push(receipt);
  }
  assert.equal(sink.pendingBytes(), 0);
  assert.equal(sink.cleanupPending(), false);
  await telemetry?.close(); telemetry = undefined;
  assert.equal(otlpRequests, 0);
  const originalSourcePolicy = source.contract_registry.find(value => value.kind === 'data_policy').cid;
  await writeFile(join(root, 'recovery.json'), JSON.stringify({subject, manifests, pid: process.pid,
    scenario: scenarioName, observationMode, otlpRequests, originalSourcePolicy,
    modelTaskCids: installed.tasks.map(task => task.contract_cid),
    calls, sourceCalls: readLines(sourcePath).length, terminal, description, ref: run.ref, revision: runtime?.revision}));
  }
  if (['resume-cleanup-pending', 'resume-cleanup-retry'].includes(phase)) {
    await client.close(); client = undefined;
    if (host !== undefined) {await host.close(); host = undefined;}
    const directory = join(root, 'host/checkpoints/attempts');
    const ledgers = [];
    for (const name of await readdir(directory)) {
      if (name.endsWith('.json')) ledgers.push(JSON.parse(await readFile(join(directory, name), 'utf8')));
    }
    const holdings = ledgers.flatMap(ledger => ledger.holdings.filter(item => item.name !== 'invocation_request'));
    assert(holdings.length > 0);
    if (phase === 'resume-cleanup-pending') {
      assert.equal(cleanupRefusalInstalled, true);
      assert(holdings.some(item => item.state === 'retiring' && item.cleanup_error === 'EACCES'));
    } else assert(holdings.every(item => item.state === 'retired'));
    await writeFile(join(root, `${phase}.json`), JSON.stringify({pid: process.pid,
      ref: run.ref, sourceCalls: readLines(sourcePath).length, calls, holdings,
      retainedRequestCount: ledgers.flatMap(ledger => ledger.holdings).filter(item => item.name === 'invocation_request').length}));
  }
} finally {
  await client?.close();
  if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
  await host?.close();
  await telemetry?.close();
  if (collector) await new Promise(resolve => collector.close(resolve));
}
