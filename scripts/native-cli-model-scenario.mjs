// Controlled HTTPS acceptance on an already authenticated, installed CLI.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {canonicalText} from './check-canonical-json.mjs';
import {providerBindingOriginals} from './fixtures/model-provider-binding-fixture.mjs';
import {captureNativeMockCommand} from './native-cli-mock-scenario.mjs';
import {nativeMockAcceptanceObservations} from '../packages/native-cli/lib/project-scaffold.mjs';

const requestBytes = 32_768;
const model = 'controlled-chat';
const provider = 'models/http';
const completionPath = '/v1/chat/completions';
const answer = n => ({level: n === 1 ? 'low' : 'high', reason: `controlled reply ${n}`});
const cid = body => 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex');
const seal = body => ({...body, self_cid: cid(body)});
const json = async path => JSON.parse(await readFile(path, 'utf8'));
const write = (path, body, flag = 'wx') => writeFile(path, canonicalText(body), {mode: 0o600, flag});

async function configureModelProject({project, endpoint, certPath, token, assets, runtimeSha256}) {
  const fixture = await json(new URL('./fixtures/public-model-task-signed64.json', import.meta.url));
  const task = {...fixture.task, connector_id: provider, authored_model_selector: model, max_items: 1,
    generation_config: {...fixture.task.generation_config, max_output_tokens: 100}};
  delete task.contract_cid;
  task.contract_cid = cid(task);
  const environmentPath = join(project, 'environment.json');
  const environment = await json(environmentPath);
  environment.model_task_contracts = [task];
  Object.assign(environment.host_policy_profile.capacity, {
    max_model_request_bytes_per_item: requestBytes, max_model_input_tokens_per_item: 256,
    max_model_total_duration_ms: 6000,
  });
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = cid(environment);
  await write(environmentPath, environment, 'w');

  const vendor = providerBindingOriginals(provider, {selector: model, endpoint});
  const responseFixture = await json(new URL('../portability/corpus/model-response-profiles.json', import.meta.url));
  const responseProfile = responseFixture.cases[0].body;
  const artifactIdentity = 'sha256:' + runtimeSha256;
  Object.assign(responseProfile.adapter, {builder_id: 'actql/native-portable-chat',
    codec_id: 'actql/openai-chat-envelope', build_artifact_cid: artifactIdentity});
  Object.assign(responseProfile.completion, {validator_id: 'actql/openai-chat-envelope',
    validator_artifact_cid: artifactIdentity});
  responseProfile.operation.endpoint = endpoint;
  Object.assign(responseProfile.task, {contract_cid: task.contract_cid,
    input_schema_cid: task.input_schema_cid, output_schema_cid: task.output_schema_cid});
  Object.assign(responseProfile.limits, {request_bytes: requestBytes, response_bytes: 65536,
    header_bytes: 4096, adapter_holding_bytes: 131072, adapter_workspace_bytes: 65536,
    active_slots: 1, unsettled_slots: 1, chunk_bytes: 4096});
  const profile = seal(responseProfile);
  const defaults = fixture.profile.model_defaults;
  defaults.default_model = model;
  defaults.models[0].model = model;
  const retry = seal({version: 'actql-model-retry-policy/0.1', retryable_failures: []});
  const backoff = seal({version: 'actql-model-backoff/0.1', delays_ms: []});
  const execution = seal({version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: task.contract_cid, retry_classification_contract_cid: retry.self_cid,
    backoff_contract_cid: backoff.self_cid, max_attempts_per_slot: 1, max_total_attempts: 1,
    max_total_cost_units: 0, max_total_duration_ms: 6000, max_total_wire_bytes: 131072,
    max_total_token_reservation: 1024, media_input_contracts: {}, default_publication: 'outcomes'});
  const files = {
    'model-credential.json': {version: 'actql-config/0.1', native: {preparation_credential: {
      credential_file: 'model.key', provider_file: 'model-provider.json'}}},
    'model-profile.json': profile,
    'model-provider.json': {...JSON.parse(vendor.configuration.wire),
      installation_revision_cid: vendor.installationRevision.cid,
      configuration_contract_cid: vendor.configurationContract.cid,
      response_profile_cid: profile.self_cid, model_id: model, credential_ref: 'file:model.key',
      adapter_kind: 'portable-http', api_mode: 'chat-completions', model_defaults: defaults},
    'model-execution.json': {contract_cid: execution.self_cid, contract: canonicalText(execution),
      prompt: canonicalText(fixture.prompt), retry_policy: canonicalText(retry), backoff: canonicalText(backoff)},
    'model-policy.json': {ca_path: certPath, connect_timeout_ms: 1500, operation_timeout_ms: 4000,
      credential_expires_at_ms: Date.now() + 172800000, max_projection_frames: 1000,
      attempt_tokens: 1024, attempt_cost_units: 0, input_classification: 'internal',
      provider_region: 'explicit-fixture-region', provider_retention: false, provider_training_use: false,
      retention_contract_file: 'model-retention.json', metadata_retention_file: 'model-metadata.json',
      clock_contract_file: 'model-clock.json', data_policy_file: 'model-data.json',
      available_until: '2099-01-01T00:00:00.000Z', delete_by: '2099-01-02T00:00:00.000Z',
      extension_ceiling_at: '2099-01-02T00:00:00.000Z', metadata_delete_by: '2099-01-03T00:00:00.000Z'},
  };
  for (const [name, body] of Object.entries(files)) await write(join(project, name), body);
  const retention = await json(join(project, 'retention.json'));
  const originalWires = {
    'model-revision.json': vendor.installationRevision.wire,
    'model-contract.json': vendor.configurationContract.wire,
    'model-retention.json': retention[0].wire,
    'model-metadata.json': retention[1].wire,
    'model-clock.json': retention[2].wire,
    'model-data.json': assets['result-policy'],
  };
  for (const [name, body] of Object.entries(originalWires))
    await writeFile(join(project, name), body, {mode: 0o600, flag: 'wx'});
  await writeFile(join(project, 'model.key'), token, {mode: 0o600, flag: 'wx'});

  const configPath = join(project, 'operator.json');
  const config = await json(configPath);
  config.native.check_environment.evidence_bundle_cid = environment.evidence_bundle_cid;
  config.native.local.installation_files.push(...Object.keys(files), ...Object.keys(originalWires));
  config.native.local.model_http_installation = {provider_id: provider, credential_installation: 'model-credential.json',
    installation_revision: 'model-revision.json', configuration_contract: 'model-contract.json',
    response_profile: 'model-profile.json', response_profile_cid: profile.self_cid,
    execution_file: 'model-execution.json', run_policy_file: 'model-policy.json'};
  await write(configPath, config, 'w');
  const accountPath = join(project, 'account.json');
  const account = await json(accountPath);
  account.entries.unshift({entry_id: 'bounded-native-model', outcome: 'allow', principal: {any_of: [account.account_id]},
    connection: {any_of: [provider]}, resource: {any_of: [task.contract_cid]},
    operation: {any_of: ['infer', 'model_raw_capture']}, exclusions: []});
  await write(accountPath, account, 'w');
  return task.task_id;
}

function program(contract, n) {
  return {version: 'actql/0.1', id: 'native-direct-model-qualification', stages: [
    {id: 'model', inputs: {}, steps: [
      {values: {schema: {id: {type: 'string', nullable: false}, notes: {type: 'string', nullable: false},
        active_users: {type: 'int64', nullable: false}, trend: {type: 'string', nullable: false}},
      rows: [{id: `row${n}`, notes: `original input ${n}`, active_users: String(n), trend: 'stable'}]}, as: 'seed'},
      {assert_rows: {unique_by: ['id']}},
      {infer: {contract, key: 'id', input: {notes: {field: 'notes'}, active_users: {field: 'active_users'},
        trend: {field: 'trend'}}}, as: 'inferred'}], results: {rows: {from: 'inferred', fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'model', result: 'rows'}}}};
}

export async function observeInstalledNativeModel({root, binary, modelImage, prepareProject,
  environment, runtimeSha256, assets, records}) {
  assert(modelImage?.role === 'model-http', 'Required Model HTTPS member is unavailable');
  const project = join(root, 'project');
  const tls = join(root, 'tls');
  await mkdir(root, {mode: 0o700});
  await mkdir(tls, {mode: 0o700});
  execFileSync('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-days', '2', '-subj', '/CN=ActQL Controlled Model', '-addext',
    'subjectAltName=IP:127.0.0.1', '-keyout', 'key.pem', '-out', 'cert.pem'],
  {cwd: tls, stdio: 'ignore', timeout: 30_000});
  const certPath = join(tls, 'cert.pem');
  const token = 'synthetic-controlled-model-' + randomUUID();
  const calls = [];
  const phases = [];
  const connections = {tcp: 0, tls: 0};
  const sockets = new Set();
  let serverFailure;
  const server = createServer({cert: await readFile(certPath), key: await readFile(join(tls, 'key.pem')),
    requestTimeout: 5000}, async (request, response) => {
    try {
      const chunks = [];
      let bytes = 0;
      for await (const chunk of request) {
        bytes += chunk.length;
        assert(bytes <= requestBytes, 'Controlled request exceeded the admitted body bound');
        chunks.push(chunk);
      }
      const n = calls.length + 1;
      const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      const call = {method: request.method, path: request.url, authorized: request.headers.authorization === 'Bearer ' + token,
        model: body.model, notesMatch: JSON.stringify(body.messages).includes(`original input ${n}`)};
      calls.push(call);
      assert.deepEqual(call, {method: 'POST', path: completionPath, authorized: true, model, notesMatch: true});
      assert(n <= 3, 'Unexpected Model resend');
      const payload = JSON.stringify({id: `controlled-${n}`, model, object: 'chat.completion',
        choices: [{index: 0, message: {role: 'assistant', content: JSON.stringify(answer(n))}, finish_reason: 'stop'}],
        usage: {prompt_tokens: n === 1 ? 0 : 15, completion_tokens: 8}});
      response.writeHead(200, {'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload), connection: 'close'});
      response.end(payload);
    } catch (error) {
      serverFailure ??= error;
      response.destroy();
    }
  });
  server.on('error', error => {serverFailure ??= error;});
  server.on('connection', socket => {
    connections.tcp++;
    sockets.add(socket);
    socket.once('close', () => sockets.delete(socket));
  });
  server.on('secureConnection', () => {connections.tls++;});
  try {
    const listening = once(server, 'listening');
    server.listen({host: '127.0.0.1', port: 0});
    await listening;
    const endpoint = `https://127.0.0.1:${server.address().port}${completionPath}`;
    const {configuration} = await prepareProject(project);
    const contract = await configureModelProject({project, endpoint, certPath, token, assets, runtimeSha256});
    async function cli(phase, args) {
      const record = {phase, args, physicalRequests: calls.length};
      records.push(record);
      try {
        const result = await captureNativeMockCommand(binary, [...configuration, ...args], {
          cwd: project, env: environment, stderrPath: join(root, `${phase}.stderr`),
          timeout: 90_000, maxBuffer: 65_536,
        });
        Object.assign(record, result, {code: 0, signal: null, physicalRequests: calls.length});
      } catch (error) {
        Object.assign(record, {pid: error.pid, code: error.exitCode, signal: error.signal,
          stdout: error.stdout, stderr: error.stderr, physicalRequests: calls.length});
        throw serverFailure ?? error;
      }
      if (serverFailure) throw serverFailure;
      const groups = nativeMockAcceptanceObservations(record.stderr);
      assert.equal(groups.length, 1);
      assert.equal(groups[0].pid, record.pid);
      const close = record.stderr.split('\n').filter(line => line.startsWith('ACTQL_NATIVE_PHASE '))
        .map(line => JSON.parse(line.slice('ACTQL_NATIVE_PHASE '.length))).find(phase => phase.name === 'close');
      assert.deepEqual([close?.begins, close?.ends, close?.active, close?.unmatched_end], [1, 1, 0, 0]);
      const observed = {phase, pid: record.pid, firstClose: true, events: groups[0].events,
        physicalRequests: calls.length, connections: {...connections}};
      phases.push(observed);
      return {stdout: record.stdout, ...observed};
    }
    assert.equal(JSON.parse((await cli('adopt', ['adopt', '--initialize-signing', '--json'])).stdout).kind,
      'local_host_adopted');
    const runs = [];
    const requireSends = n => {
      assert.equal(calls.length, n);
      assert.deepEqual(connections, {tcp: n, tls: n});
    };
    for (const n of [1, 2, 3]) {
      const file = `infer-${n}.json`;
      await write(join(project, file), program(contract, n));
      const checked = await cli(`check-${n}`, ['check', file, '--format', 'json', '--json']);
      const check = JSON.parse(checked.stdout);
      assert.equal(check.outcome, 'completed');
      assert.equal(check.report.verdict, 'verified');
      assert.equal(check.report.runnable.verdict, 'yes');
      assert.deepEqual(checked.events, []);
      requireSends(n - 1);
      const started = await cli(`run-${n}`, ['run', file, '--format', 'json', '--json']);
      const state = JSON.parse(started.stdout);
      assert.equal(state.status, 'succeeded');
      assert.match(state.run_id, /^sha256:[0-9a-f]{64}$/u);
      assert.deepEqual(started.events.map(event => event.tag), [0, 1, 2]);
      const call = started.events[1].identity;
      assert(started.events.every(event => event.identity === call && event.ordinal === 0));
      requireSends(n);
      // The cold delivery supplies the independent Result evidence for this Run.
      const saved = await cli(`saved-${n}`, ['result', state.run_id, '--result', 'answer', '--format', 'jsonl']);
      const rows = saved.stdout.trim().split('\n').map(line => JSON.parse(line));
      assert.deepEqual(rows, [{id: `row${n}`, outcome: 'ok', value: answer(n)}]);
      assert.deepEqual(saved.events, []);
      requireSends(n);
      runs.push({runId: state.run_id, call, rows, coldPid: saved.pid});
    }
    for (const key of ['runId', 'call']) assert.equal(new Set(runs.map(run => run[key])).size, 3);
    assert.equal(new Set(phases.map(phase => phase.pid)).size, phases.length);
    return {image: modelImage, fixture: 'controlled-loopback-tls', phases, runs, calls, connections};
  } finally {
    for (const socket of sockets) socket.destroy();
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
}
