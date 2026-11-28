import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync, sign} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {access, readdir, readFile, writeFile} from 'node:fs/promises';
import files from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire, syncBuiltinESMExports} from 'node:module';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {setTimeout as pause} from 'node:timers/promises';
import tls from 'node:tls';
import {open} from '@actql/node';
import {createRegisteredSdkProvider} from '@actql/provider-ai-sdk';
import {observeOwnScopedStateFds} from './conformance.mjs';
import {omitFixtureModelPlanBinding, verifyFixtureModelPlanBindingStillAbsent} from './normal-provider-diagnostics.fixture.mjs';

const [phase, caseId, ...extra] = process.argv.slice(2);
const park = phase === caseId, approve = phase === 'approve';
assert(park || approve || phase === 'cold');
assert.deepEqual(extra, []);
assert.equal(process.env.OPENAI_API_KEY, undefined);
const rawDenied = caseId === 'registered-checkpoint-raw-denied';
const changedRoute = caseId === 'registered-checkpoint-changed-route';
const missingBinding = caseId === 'registered-checkpoint-missing-binding';
const leaseExpired = caseId === 'registered-checkpoint-stale-lease';
assert(caseId === 'registered-checkpoint' || rawDenied || changedRoute || missingBinding || leaseExpired);
assert(phase !== 'cold' || caseId === 'registered-checkpoint');
const refused = rawDenied || changedRoute || missingBinding || leaseExpired;
const positiveSend = approve && !refused;
const put = (file, value) => writeFile(file, JSON.stringify(value), {mode: 0o600, flag: 'wx'});
const read = async file => JSON.parse(await readFile(file, 'utf8'));
const sha256 = bytes => 'sha256:' + createHash('sha256').update(bytes).digest('hex');
const cidFormat = /^sha256:[0-9a-f]{64}$/u;

// The installed Usage sink supplies the semantic Raw CID. This diagnostic
// checks the single retained encrypted holding without opening a Raw reader.
async function readRawHolding(manifestCid) {
  const root = '.state/publication';
  const holdings = await readdir(root + '/physical-holdings');
  assert(holdings.length <= 32);
  const candidates = [];
  for (const name of holdings) {
    const holding = await read(root + '/physical-holdings/' + name);
    if (holding.manifest_cid !== manifestCid) continue;
    assert.equal(holding.namespace, 'publication-private');
    assert.match(holding.holding_cid, cidFormat);
    assert.equal(name, holding.holding_cid.slice(7) + '.json');
    candidates.push(holding);
  }
  assert.equal(candidates.length, 1);
  const [raw] = candidates;
  assert.equal(raw.objects.length, 2);
  for (const {cid, byte_count: extent} of raw.objects) {
    assert.match(cid, cidFormat);
    assert(Number.isSafeInteger(extent) && extent > 0 && extent <= 16384);
    const encrypted = await readFile(root + '/objects/' + cid.slice(7));
    assert.equal(encrypted.byteLength, extent);
    assert.equal(sha256(encrypted), cid);
  }
  return raw;
}
const providerId = 'models/http', task = 'model-task:first', selector = 'fixture-selector';
const endpoint = 'https://api.openai.com/v1/chat/completions';
const taskCid = 'sha256:35c61f54ca9853031befb1adb0e5230c14d616d6ba776bdab78a1bd9432177a1';
const provider = new URL(import.meta.resolve('@actql/provider-ai-sdk'));
const adapterVersion = (await read(new URL('package.json', provider))).version;
const sdkModule = createRequire(provider).resolve('@ai-sdk/openai');
const sdkVersion = (await read(resolve(sdkModule, '../../package.json'))).version;
assert.equal(sdkVersion, '4.0.91');
const image = async (path, file, packageName, version) => Object.freeze({path, packageName, version,
  cid: sha256(await readFile(file))});
const adapter = await image('_internal/openai-chat.mjs', new URL('_internal/openai-chat.mjs', provider),
  '@actql/provider-ai-sdk', adapterVersion);
const lock = await image('npm-shrinkwrap.json', new URL('npm-shrinkwrap.json', provider),
  adapter.packageName, adapter.version);
const sdk = await image('dist/index.js', sdkModule, '@ai-sdk/openai', sdkVersion);
const resolvedModel = approve && changedRoute ? 'replacement-chat' : 'fixture-chat';
const routes = Object.freeze([Object.freeze({selector, modelId: resolvedModel, apiMode: 'chat_completions', endpoint,
  structuredCapability: Object.freeze({operation: 'structured_generate', adapter: 'supported', model: 'supported'}),
  providerOptions: Object.freeze({store: false, strictJsonSchema: true}),
  credential: Object.freeze({reference: 'OPENAI_API_KEY', header: 'authorization'})})]);
const modelSdkRegistrations = Object.freeze([Object.freeze({providerId, defaultSelector: selector, routes,
  adapter, lock, sdk: Object.freeze({...sdk, exportName: 'createOpenAI'})})]);
if (park) {
  await put('actql.config.json', {version: 'actql-config/0.1', model_tasks: './model-tasks.json'});
  await put('model-tasks.json', {version: 'actql-model-tasks/0.1', tasks: {[task]: './task.json'},
    providers: {[providerId]: {type: 'openai', api_key_env: 'OPENAI_API_KEY'}}, default_provider: providerId});
  await put('task.json', {task, instructions: 'Return the exact boolean.',
    input: {text: 'string'}, output: {answer: 'boolean'}, limits: {max_items: 2, max_output_tokens: 100}});
  const pair = generateKeyPairSync('ed25519');
  await writeFile('operator-private.fixture', pair.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600, flag: 'wx'});
  await writeFile('operator-public.fixture', pair.publicKey.export({type: 'spki', format: 'pem'}), {mode: 0o600, flag: 'wx'});
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048', '-keyout', 'project.key', '-out', 'project.crt',
    '-days', '1', '-subj', '/CN=api.openai.com', '-addext', 'subjectAltName=DNS:api.openai.com'], {stdio: 'ignore'});
}
const secret = 'registered-checkpoint-synthetic-key';
let tlsAttempts = 0, posts = 0, credentialReads = 0, peerConnections = 0;
let peer;
const originalEnv = process.env, originalConnect = tls.connect;
const journalPath = '.state/checkpoints/journal/checkpoint-journal.sqlite3';
let claimAtParkedCommit, advancedTime, terminalCause, firstClose = 'unobserved';
let approval, scopedStateFd0, typedResult, usageEvidence;
const usageCounts = {authorize: 0, capture: 0, record: 0};
const realRename = files.rename, realNow = Date.now;
const readClaim = (database, runId) => database.prepare(
  'SELECT generation, lease_expires_ms FROM resume_intents WHERE run_id = ?').get(runId);
let stoppedRunId;
try {
  process.env = new Proxy(originalEnv, {get(target, key, receiver) {
    if (key === 'OPENAI_API_KEY') credentialReads++;
    return Reflect.get(target, key, receiver);
  }});
  if (positiveSend) {
    const cert = await readFile('project.crt');
    tls.setDefaultCACertificates([...tls.getCACertificates('default'), cert.toString('utf8')]);
    peer = createServer({cert, key: await readFile('project.key')}, async (request, response) => {
      posts++;
      assert.equal(request.headers.host, 'api.openai.com');
      assert.equal(request.socket.servername, 'api.openai.com');
      assert.equal(request.headers.authorization, 'Bearer ' + secret);
      assert.equal(request.url, '/v1/chat/completions');
      let body = '';
      for await (const chunk of request) { body += chunk; assert(body.length <= 32768); }
      const parsed = JSON.parse(body);
      assert.equal(parsed.model, 'fixture-chat');
      assert.equal(parsed.store, false);
      assert.deepEqual(JSON.parse(parsed.messages[1].content), {text: 'first'});
      response.setHeader('content-type', 'application/json');
      response.end(JSON.stringify({id: 'original-registered-checkpoint', object: 'chat.completion', created: 1,
        model: 'fixture-chat', choices: [{index: 0, message: {role: 'assistant', content: '{"answer":true}'},
          finish_reason: 'stop'}], usage: {prompt_tokens: 2, completion_tokens: 3, total_tokens: 5}}));
    });
    peer.on('connection', () => {peerConnections++;});
    peer.listen(0, '127.0.0.1');
    await new Promise(resolve => peer.once('listening', resolve));
  }
  tls.connect = (options, ...args) => {
    assert(positiveSend);
    assert.equal(++tlsAttempts, 1);
    assert.equal(options.host, 'api.openai.com');
    assert.equal(options.servername, 'api.openai.com');
    assert.equal(Number(options.port), 443);
    assert.notEqual(options.rejectUnauthorized, false);
    return originalConnect.call(tls, {...options, host: '127.0.0.1', port: peer.address().port}, ...args);
  };
  const permission = (entry_id, outcome, operations) => ({entry_id, outcome, principal: {all: true},
    connection: {all: true}, resource: {all: true}, operation: {any_of: operations}, exclusions: []});
  const events = [];
  async function waitForEvent(name) {
    const end = realNow() + 10000;
    for (let event; realNow() < end;) {
      event = events.find(event => event.name === name);
      if (event !== undefined) return event;
      await pause(20);
    }
    assert.fail(JSON.stringify({name, events}));
  }
  const key = await readFile('operator-private.fixture', 'utf8');
  const authorization = {hostKey: {keyId: 'http-host', privateKey: key},
    reviewers: [{keyId: 'http-reviewer', reviewerId: 'http-reviewer', principalId: userInfo().username,
      publicKey: await readFile('operator-public.fixture', 'utf8')}],
    accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1', account_id: 'http-fixture',
      entries: [permission('fixture-delegate', 'delegate', ['infer']), permission('fixture-only', 'allow', ['read', 'write']),
        {...permission('fixture-raw', rawDenied ? 'deny' : 'allow', ['model_raw_capture']), principal: {any_of: [userInfo().username]},
          connection: {any_of: [providerId]}, resource: {any_of: [taskCid]}}]}),
    observe(name, detail) {events.push({name, code: detail?.code, primaryCode: detail?.primaryCode,
      issueTag: detail?.issueTag, nestedIssueTag: detail?.nestedIssueTag,
      ...(name === 'model_resume_failed' ? {ref: detail?.ref} : {})});}};
  const dataHandlingContractWire = JSON.stringify({schema: 'actql.contract/0.1', id: 'openai-public-provider-contract',
    version: '1', kind: 'request_data_handling', body: {accepted_classifications: ['public'], allowed_regions: ['global'],
      retention: 'provider_contract', training_use: 'forbidden'},
    cid: 'sha256:2c582952a0c9a6de0dc7fd58b1411207a0eac0c02fe75c2c61a39bf2e6942c54'});
  const registerModelProviders = createRegisteredSdkProvider({providerId, dataHandlingContractWire,
    generation: {temperature: 0, topP: 1, maxOutputTokens: 100},
    transportTimeouts: {connectMs: 1000, headersMs: 1000, bodyMs: 1000, callMs: 1000},
    budget: {maxCalls: 2n, maxRows: 2, maxTokens: 1000n, maxCostUnits: 100000n, maxDurationMs: 1000n},
    observeEgress: () => ({classification: 'public', region: 'global', providerRetention: true, trainingUse: false})});
  let reference = park ? undefined : await read('run-0.json');
  const missingBindingEvidence = approve && missingBinding ? omitFixtureModelPlanBinding(reference, taskCid).evidence : undefined;
  const subject = () => ({runDefinitionCid: reference.runDefinitionCid, authorityScopeCid: reference.authorityScopeCid});
  const resultDataPolicy = {kind: 'data_policy',
    wire: '{"classification":"unknown","source_data_policy_cids":[],"source_response_policy_cids":[],"unknown_provenance":true,"version":"actql-effective-data-policy/0.1"}',
    cid: 'sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563'};
  const inferEvidence = {kind: 'usage', target: 'inferred', destination: 'local:checkpoint-usage', maxBytes: 4096,
    authorize(binding) {
      usageCounts.authorize++;
      assert.equal(binding.kind, 'usage');
      assert.equal(binding.target, 'inferred');
      assert.equal(binding.destination, 'local:checkpoint-usage');
      assert.deepEqual(binding.policy, resultDataPolicy);
      assert.deepEqual(binding.subject, subject());
      return true;
    },
    sink: {
      async capture(binding) {
        usageCounts.capture++;
        assert.deepEqual(Object.keys(binding.wires), ['usage']);
        assert(Buffer.byteLength(binding.wires.usage) <= 4096);
        const usage = JSON.parse(binding.wires.usage);
        assert.deepEqual(Object.keys(usage), ['input_tokens', 'invocation_evidence_cid', 'model_call_slot_cid',
          'model_task_contract_cid', 'observation_origin', 'output_tokens', 'raw_response_artifact_cid']);
        assert.deepEqual([usage.input_tokens, usage.output_tokens, usage.observation_origin], [2, 3, 'reported']);
        assert.equal(usage.model_task_contract_cid, taskCid);
        assert.equal(usage.model_call_slot_cid, binding.original.modelCallSlotCid);
        for (const cid of [usage.invocation_evidence_cid, usage.raw_response_artifact_cid,
          binding.original.captureBundleCid, binding.attemptCid]) assert.match(cid, cidFormat);
        await put('usage.json', {usage, attemptCid: binding.attemptCid, captureBundleCid: binding.original.captureBundleCid});
        return {status: 'complete'};
      },
      async record(receipt) {
        usageCounts.record++;
        assert.deepEqual(receipt.subject, subject());
        assert.equal(receipt.target, 'inferred');
        assert(Buffer.byteLength(JSON.stringify(receipt)) <= 4096);
        await put('usage-receipt.json', receipt);
      },
    }};
  const client = await open({stateDir: '.state', installation: {
    modelSdkRegistrations, registerModelProviders, authorization, resultDataPolicy, inferEvidence,
  }});
  try {
    assert.equal(credentialReads, 0);
    if (park) {
      const program = {version: 'actql/0.1', id: 'normal-text',
        stages: [{id: 'main', inputs: {}, steps: [
          {values: {schema: {id: {type: 'string', nullable: false}, text: {type: 'string', nullable: false}},
            rows: [{id: 'original-text', text: 'first'}]}, as: 'input'},
          {assert_rows: {unique_by: ['id']}, as: 'unique'},
          {infer: {contract: task, key: 'id', input: {text: {field: 'text'}}}, as: 'inferred'}],
          results: {answer: {from: 'inferred', fields: ['id', 'outcome', 'value']}}}],
        results: {answer: {from: {stage: 'main', result: 'answer'}}}};
      const submissionRef = client.newSubmission({nonce: 'registered-checkpoint'});
      const run = await client.start(program, {submissionRef});
      reference = run.ref;
      const status = await run.wait({signal: AbortSignal.timeout(15000)});
      assert.equal(status.status, 'waiting_checkpoint', JSON.stringify(events));
      const {items} = await client.checkpoints({checkpointId: status.checkpoint.id});
      assert.equal(items.length, 1);
      assert.equal(items[0].checkpointCid, status.checkpoint.checkpoint_cid);
      assert.equal(items[0].subject.runDefinitionCid, reference.runDefinitionCid);
      await put('run-0.json', reference);
      await put('checkpoint.json', items[0]);
      await put('submission-0.json', submissionRef);
    } else {
      const run = await client.attach(reference);
      if (approve) {
        process.env.OPENAI_API_KEY = secret;
        const checkpoint = await read('checkpoint.json');
        stoppedRunId = checkpoint.subject.runId;
        if (leaseExpired) {
          const ledger = resolve('.state/checkpoints/attempts', 'model-' + stoppedRunId + '.json');
          // The accepted Model claim expires only after this phase writes its
          // same original parked ledger. The journal's stored lease is unchanged.
          Date.now = () => advancedTime ?? realNow();
          files.rename = async (from, to) => {
            await realRename(from, to);
            if (to !== ledger || advancedTime !== undefined) return;
            const database = new DatabaseSync(journalPath, {readOnly: true});
            try {
              claimAtParkedCommit = readClaim(database, stoppedRunId);
              assert(claimAtParkedCommit.lease_expires_ms > realNow());
              advancedTime = claimAtParkedCommit.lease_expires_ms;
            } finally { database.close(); }
          };
          syncBuiltinESMExports();
        }
        const resolved = await client.resolveCheckpoints([{checkpoint, decision: 'approved'}],
          {signer: {keyId: 'http-reviewer', reviewerId: 'http-reviewer', sign: bytes => sign(null, bytes, key)}});
        assert.deepEqual(resolved.results.map(result => result.status), ['committed']);
        const signed = JSON.parse(resolved.signed[0].resolutionWire);
        assert.equal(signed.checkpoint_id, checkpoint.checkpointId);
        assert.equal(signed.checkpoint_cid, checkpoint.checkpointCid);
        assert.equal(signed.run_definition_cid, reference.runDefinitionCid);
        assert.equal(signed.run_id, stoppedRunId);
        approval = {checkpointId: signed.checkpoint_id, checkpointCid: signed.checkpoint_cid,
          runId: signed.run_id, runDefinitionCid: signed.run_definition_cid};
        if (leaseExpired) {
          const failure = await waitForEvent('dispatch_failed');
          assert(claimAtParkedCommit);
          terminalCause = failure.primaryCode;
          assert.equal(terminalCause, 'ResumeClaimStale', JSON.stringify(events));
        } else if (changedRoute || missingBinding) {
          const failure = await waitForEvent('model_resume_failed');
          terminalCause = failure.code;
          assert.equal(terminalCause, missingBinding ? 'ClientModelProviderSelectionUnavailable' :
            'ClientModelProviderSelectionChanged');
          assert.deepEqual(failure.ref, reference);
          assert.equal((await run.status()).status, 'failed');
        } else if (rawDenied) {
          const failure = await waitForEvent('dispatch_failed');
          terminalCause = failure.primaryCode;
          assert.equal(terminalCause, 'MoonBitHostFailure', JSON.stringify(events));
          assert.deepEqual([failure.issueTag, failure.nestedIssueTag], [5, 1]);
        } else {
          assert.equal((await run.wait({until: 'terminal', signal: AbortSignal.timeout(15000)})).status, 'succeeded',
            JSON.stringify(events));
        }
      }
      if (!refused) {
        typedResult = await run.result('answer').all();
        assert.deepEqual(typedResult, [{id: 'original-text', outcome: 'ok', value: {answer: true}}]);
      }
      if (!leaseExpired) {
        const lookup = await client.lookupSubmission(await read('submission-0.json'));
        assert.equal(lookup.kind, 'ready');
        assert.deepEqual(lookup.admission.ref, reference);
      }
    }
  } finally {
    try { await client.close(); firstClose = 'closed'; }
    catch (cause) {
      if (!(approve && leaseExpired && terminalCause === 'ResumeClaimStale') || cause?.code !== 'ClientCleanupPending') throw cause;
      firstClose = cause.code;
    } finally {
      if (leaseExpired) {
        Date.now = realNow;
        files.rename = realRename;
        syncBuiltinESMExports();
      }
    }
  }
  // The FD observer spawns lsof. Its independent process must not inherit the
  // synthetic provider key or inflate the selected transport's acquisition count.
  delete process.env.OPENAI_API_KEY;
  process.env = originalEnv;
  if (approve && leaseExpired) {
    assert.equal(firstClose, 'ClientCleanupPending');
    await access('.state/publication/owner/owner.json');
  } else {
    scopedStateFd0 = observeOwnScopedStateFds([resolve('.state')]).scopedStateFd0;
    assert.equal(scopedStateFd0, true);
    await assert.rejects(access('.state/publication/owner/owner.json'), {code: 'ENOENT'});
  }
  const journal = new DatabaseSync(journalPath, {readOnly: true});
  let attempts, settlement;
  try {
    const boundary = journal.prepare("SELECT json_extract(originals_json,'$.expectedBoundary.resource') AS task FROM resume_model_scopes").all();
    assert.deepEqual(boundary.map(row => row.task), [taskCid]);
    attempts = journal.prepare('SELECT attempt_cid, state FROM resume_model_attempts').all();
    assert.deepEqual(attempts.map(row => row.state), park || refused ? [] : ['SavedSuccess']);
    if (attempts.length === 1) {
      const {entry, evidence} = JSON.parse(journal.prepare(
        'SELECT settlement_json FROM resume_model_attempts WHERE attempt_cid = ?').get(attempts[0].attempt_cid).settlement_json);
      assert.equal(entry.attemptCid, attempts[0].attempt_cid);
      assert.equal(entry.runDefinitionCid, reference.runDefinitionCid);
      const checkpoint = await read('checkpoint.json');
      assert.equal(entry.runId, checkpoint.subject.runId);
      assert.equal(entry.checkpointCid, checkpoint.checkpointCid);
      assert.match(entry.slotCid, /^sha256:[0-9a-f]{64}$/u);
      for (const role of ['model_call_attempt', 'model_attempt_accounting', 'model_attempt_outcome',
        'model_dispatch_authority', 'model_slot_capture', 'model_capture_bundle']) {
        const leaf = evidence[role];
        assert.match(leaf.cid, /^sha256:[0-9a-f]{64}$/u);
        assert.match(leaf.holdingCid, /^sha256:[0-9a-f]{64}$/u);
        assert.notEqual(leaf.cid, leaf.holdingCid);
      }
      settlement = {attemptCid: entry.attemptCid, slotCid: entry.slotCid, evidence};
      const saved = await read('usage.json');
      const receipt = await read('usage-receipt.json');
      assert.equal(saved.attemptCid, settlement.attemptCid);
      assert.equal(saved.captureBundleCid, evidence.model_capture_bundle.cid);
      assert.equal(saved.usage.model_call_slot_cid, settlement.slotCid);
      assert.deepEqual([saved.usage.input_tokens, saved.usage.output_tokens, saved.usage.observation_origin], [2, 3, 'reported']);
      assert.equal(saved.usage.model_task_contract_cid, taskCid);
      assert.deepEqual(receipt, {subject: subject(), target: 'inferred',
        manifest: {kind: 'usage', status: 'complete', subject: subject(), target: 'inferred',
          items: [{modelCallSlotCid: settlement.slotCid, attemptCid: settlement.attemptCid, status: 'complete'}]}});
      const raw = await readRawHolding(saved.usage.raw_response_artifact_cid);
      usageEvidence = {usage: saved.usage, receipt, raw};
    }
    assert.deepEqual(journal.prepare('SELECT state FROM resume_model_slots').all().map(row => row.state),
      [park || refused ? 'Unsent' : 'SavedSuccess']);
    if (approve && leaseExpired) {
      assert.deepEqual(readClaim(journal, stoppedRunId), claimAtParkedCommit);
      assert.equal(journal.prepare('SELECT current_cut_link_json FROM resume_model_scopes').get().current_cut_link_json, null);
    }
  } finally { journal.close(); }
  assert.deepEqual([tlsAttempts, peerConnections, posts], positiveSend ? [1, 1, 1] : [0, 0, 0]);
  assert.equal(credentialReads, approve && !changedRoute && !missingBinding ? 1 : 0);
  assert.deepEqual(Object.values(usageCounts), positiveSend ? [1, 1, 1] : [0, 0, 0]);
  if (missingBindingEvidence !== undefined) {
    verifyFixtureModelPlanBindingStillAbsent(reference, missingBindingEvidence);
  }
  console.log(JSON.stringify({caseId, phase, reference, pid: process.pid,
    adapter, lock, sdk, firstClose, scopedStateFd0, taskCid, terminalCause, approval,
    attempts, settlement, typedResult, usageCounts, usageEvidence, credentialReads, tlsAttempts, peerConnections, posts,
    ...(missingBindingEvidence === undefined ? {} : {missingBindingEvidence})}));
} finally {
  delete process.env.OPENAI_API_KEY;
  process.env = originalEnv;
  tls.connect = originalConnect;
  if (peer) {
    peer.closeAllConnections();
    await new Promise(resolve => peer.close(resolve));
  }
}
