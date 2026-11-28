// Controlled HTTPS acceptance on an already authenticated, installed CLI.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {constants} from 'node:fs';
import {lstat, mkdir, open, readFile, unlink, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {canonicalText} from './check-canonical-json.mjs';
import {nativeJoinedModelRun, requireModelAttempts, requireNativeJoinedDelivery} from './fixtures/native-joined-model-run.mjs';
import {inspectNativeModelCustody} from './fixtures/native-model-custody-observation.mjs';
import {requireNativeModelAccounting, requireNativeRawReceipts, splitNativeModelConfirmations}
  from './fixtures/native-model-confirmation-observation.mjs';
import {providerBindingOriginals} from './fixtures/model-provider-binding-fixture.mjs';
import {captureNativeMockCommand} from './native-cli-mock-scenario.mjs';
import {nativeMockAcceptanceObservations} from '../packages/native-cli/lib/project-scaffold.mjs';

const requestBytes = 32_768;
const selectedModels = [
  {prefix: 'model', taskId: 'model-task:churn-risk.v1', model: 'controlled-chat'},
  {prefix: 'confirm', taskId: 'model-task:churn-risk-confirm.v1', model: 'controlled-confirm'},
];
const provider = 'models/http';
const completionPath = '/v1/chat/completions';
const answer = n => ({level: n === 1 ? 'low' : 'high', reason: `controlled reply ${n}`});
const joinedUsage = [{input_tokens: 0, output_tokens: 8}, {input_tokens: 15, output_tokens: null}];
const cid = body => 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex');
const seal = body => ({...body, self_cid: cid(body)});
const json = async path => JSON.parse(await readFile(path, 'utf8'));
const write = (path, body, flag = 'wx') => writeFile(path, canonicalText(body), {mode: 0o600, flag});

async function configureModelTask({project, endpoint, certPath, dataPolicy, runtimeSha256, selection}) {
  const {prefix, taskId, model, token} = selection;
  const file = suffix => `${prefix}-${suffix}.json`;
  const keyFile = `${prefix}.key`;
  const fixture = await json(new URL('./fixtures/public-model-task-signed64.json', import.meta.url));
  const task = {...fixture.task, task_id: taskId, version: taskId, connector_id: provider,
    authored_model_selector: model, max_items: 1,
    generation_config: {...fixture.task.generation_config, max_output_tokens: 100}};
  delete task.contract_cid;
  task.contract_cid = cid(task);

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
    [file('credential')]: {version: 'actql-config/0.1', native: {preparation_credential: {
      credential_file: keyFile, provider_file: file('provider')}}},
    [file('profile')]: profile,
    [file('provider')]: {...JSON.parse(vendor.configuration.wire),
      installation_revision_cid: vendor.installationRevision.cid,
      configuration_contract_cid: vendor.configurationContract.cid,
      response_profile_cid: profile.self_cid, model_id: model, credential_ref: `file:${keyFile}`,
      adapter_kind: 'portable-http', api_mode: 'chat-completions', model_defaults: defaults},
    [file('execution')]: {contract_cid: execution.self_cid, contract: canonicalText(execution),
      prompt: canonicalText(fixture.prompt), retry_policy: canonicalText(retry), backoff: canonicalText(backoff)},
    [file('policy')]: {ca_path: certPath, connect_timeout_ms: 1500, operation_timeout_ms: 4000,
      credential_expires_at_ms: Date.now() + 172800000, max_projection_frames: 1000,
      attempt_tokens: 1024, attempt_cost_units: 0, input_classification: 'internal',
      provider_region: 'explicit-fixture-region', provider_retention: false, provider_training_use: false,
      retention_contract_file: file('retention'), metadata_retention_file: file('metadata'),
      clock_contract_file: file('clock'), data_policy_file: file('data'),
      available_until: '2099-01-01T00:00:00.000Z', delete_by: '2099-01-02T00:00:00.000Z',
      extension_ceiling_at: '2099-01-02T00:00:00.000Z', metadata_delete_by: '2099-01-03T00:00:00.000Z'},
  };
  for (const [name, body] of Object.entries(files)) await write(join(project, name), body);
  const retention = await json(join(project, 'retention.json'));
  const originalWires = {
    [file('revision')]: vendor.installationRevision.wire,
    [file('contract')]: vendor.configurationContract.wire,
    [file('retention')]: retention[0].wire,
    [file('metadata')]: retention[1].wire,
    [file('clock')]: retention[2].wire,
    [file('data')]: dataPolicy,
  };
  for (const [name, body] of Object.entries(originalWires))
    await writeFile(join(project, name), body, {mode: 0o600, flag: 'wx'});
  await writeFile(join(project, keyFile), token, {mode: 0o600, flag: 'wx'});

  const taskFile = `${taskId.slice('model-task:'.length)}.yaml`;
  const document = fixture.document.replace(`task: ${fixture.task.task_id}`, `task: ${taskId}`)
    .replace('provider: openai, name: "<model id>"', `provider: "${provider}", name: "${model}"`)
    .replace('max_items: 5000', 'max_items: 1').replace('max_output_tokens: 200', 'max_output_tokens: 100');
  assert(document.includes(`task: ${taskId}\nmodel: { provider: "${provider}", name: "${model}" }`));
  await writeFile(join(project, taskFile), document, {mode: 0o600, flag: 'wx'});
  return {task, taskFile, files: [...Object.keys(files), ...Object.keys(originalWires)], installation: {
    task_id: taskId, provider_id: provider, credential_installation: file('credential'),
    installation_revision: file('revision'), configuration_contract: file('contract'),
    response_profile: file('profile'), response_profile_cid: profile.self_cid,
    execution_file: file('execution'), run_policy_file: file('policy'),
  }};
}

async function configureModelProject({project, endpoint, certPath, assets, runtimeSha256, selections, joined, omitUsageRead = false}) {
  const environmentPath = join(project, 'environment.json');
  const environment = await json(environmentPath);
  assert.deepEqual(environment.model_task_contracts, []);
  Object.assign(environment.host_policy_profile.capacity, {
    max_model_request_bytes_per_item: requestBytes, max_model_input_tokens_per_item: 256,
    max_model_total_duration_ms: 6000,
  });
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = cid(environment);
  await write(environmentPath, environment, 'w');

  const dataPolicy = joined ? canonicalText(joined.modelRawDataPolicy) : assets['result-policy'];
  if (joined) {
    const expectedFinalPolicyCid = cid(joined.finalResultPolicy);
    for (const file of ['read.json', 'file-read.json']) {
      const path = join(project, file);
      const original = await json(path);
      const read = original.native.result_read;
      assert.deepEqual(read.data_policy_cids, [cid(JSON.parse(assets['result-policy']))]);
      read.data_policy_cids = [expectedFinalPolicyCid];
      await write(path, original, 'w');
    }
  }
  const configured = [];
  for (const selection of selections) {
    configured.push(await configureModelTask({project, endpoint, certPath, dataPolicy, runtimeSha256, selection}));
  }
  const configPath = join(project, 'operator.json');
  const config = await json(configPath);
  config.native.check_environment.evidence_bundle_cid = environment.evidence_bundle_cid;
  const local = config.native.local;
  local.installation_files.push(...configured.flatMap(({files}) => files));
  local.model_http_installations = configured.map(({installation}) => installation);

  const accountPath = join(project, 'account.json');
  const account = await json(accountPath);
  const allow = (entry_id, connection, resource, operations) => ({
    entry_id, outcome: 'allow', principal: {any_of: [account.account_id]},
    connection: {any_of: [connection]}, resource: {any_of: [resource]},
    operation: {any_of: operations}, exclusions: [],
  });
  account.entries.unshift(...configured.map(({task}, index) => allow(index === 0 ? 'bounded-native-model' :
    'bounded-native-model-confirm', provider, task.contract_cid, ['infer', 'model_raw_capture'])));
  if (joined) {
    const dataFile = join(project, 'source-data.json');
    await write(dataFile, joined.payload);
    await write(join(project, 'source-installation.json'), {version: 'actql-config/0.1', native: {source: {
      kind: 'declared_file', connections: canonicalText(joined.connections), catalog: canonicalText(joined.catalog),
      data_file: dataFile,
    }}});
    local.source_file = 'source-installation.json';
    local.installation_files.push(local.source_file);
    const readable = omitUsageRead ? joined.resources.filter(resource => resource !== 'usage') : joined.resources;
    if (omitUsageRead) assert.deepEqual(readable, ['accounts']);
    account.entries.unshift(...readable.map(resource => allow(`bounded-file-${resource}`, joined.connection,
      resource, ['read'])));
  }
  await write(configPath, config, 'w');
  await write(accountPath, account, 'w');

  await write(join(project, 'actql.config.json'), {version: 'actql-config/0.1',
    state_dir: './host', model_tasks: './model-tasks.json'});
  await write(join(project, 'model-tasks.json'), {version: 'actql-model-tasks/0.1',
    providers: {[provider]: {type: 'openai'}},
    tasks: Object.fromEntries(configured.map(({task, taskFile}) => [task.task_id, './' + taskFile])),
    default_provider: provider});
  return configured.map(({task, installation}) => ({task: task.contract_cid, profile: installation.response_profile_cid}));
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

async function readJoinedOutput(path) {
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const original = await file.stat({bigint: true});
    assert(original.isFile() && original.size > 0n && original.size <= 65_536n);
    const bytes = Buffer.alloc(Number(original.size));
    const {bytesRead} = await file.read(bytes, 0, bytes.length, 0);
    assert.equal(bytesRead, bytes.length);
    const current = await lstat(path, {bigint: true});
    assert.deepEqual([current.dev, current.ino, current.size, current.mtimeNs, current.ctimeNs],
      [original.dev, original.ino, original.size, original.mtimeNs, original.ctimeNs]);
    return bytes;
  } finally {
    await file.close();
  }
}

async function joinedCustodyOptions(project, tasks) {
  assert.equal(new Set(tasks).size, 2);
  const {native: {run}} = await json(join(project, 'run.json'));
  return {
    journalPath: join(project, 'host/client.sqlite3'),
    storePath: join(project, 'results/.actql-publication.sqlite3'),
    authority: run.store_authority_cid, namespace: run.namespace_id, provider, tasks,
  };
}

export async function observeInstalledNativeModel({root, binary, modelImage, prepareProject,
  environment, runtimeSha256, assets, records, joinedFile = false, includeReview = false}) {
  assert(!includeReview || joinedFile);
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
  const selections = (joinedFile ? selectedModels : selectedModels.slice(0, 1)).map(selection => ({
    ...selection, token: 'synthetic-controlled-model-' + randomUUID(),
  }));
  const joined = joinedFile
    ? nativeJoinedModelRun(selections[0].taskId, selections[1].taskId, {includeReview}) : null;
  const expectedSends = joined ? selections.length : 3;
  const calls = [];
  const fixtures = new Map();
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
      const selected = selections.find(({model}) => model === body.model);
      let notesMatch;
      if (joined) {
        assert(Array.isArray(body.messages), 'JOIN request did not contain the admitted Chat messages');
        assert.deepEqual(body.messages.map(message => message?.role), ['system', 'user']);
        const [{content: system}, {content: user}] = body.messages;
        assert.equal(typeof system, 'string');
        assert.equal(typeof user, 'string');
        assert.deepEqual(JSON.parse(user), joined.expectedInput);
        notesMatch = true;
      } else {
        const messages = JSON.stringify(body.messages);
        notesMatch = typeof messages === 'string' && messages.includes(`original input ${n}`);
      }
      const call = {method: request.method, path: request.url,
        authorized: selected !== undefined && request.headers.authorization === 'Bearer ' + selected.token,
        model: body.model, notesMatch};
      calls.push(call);
      assert.deepEqual(call, {method: 'POST', path: completionPath, authorized: true, model: selected?.model,
        notesMatch: true});
      assert(n <= expectedSends, 'Unexpected Model resend');
      const selectedIndex = selections.indexOf(selected);
      if (joined) assert(!calls.slice(0, -1).some(request => request.model === selected.model), 'Repeated Model selection');
      const reply = joined ? joined.answers[selectedIndex] : answer(n);
      const reported = joined ? joinedUsage[selectedIndex] : {input_tokens: n === 1 ? 0 : 15, output_tokens: 8};
      const usage = {prompt_tokens: reported.input_tokens,
        ...(reported.output_tokens === null ? {} : {completion_tokens: reported.output_tokens})};
      const payload = JSON.stringify({id: `controlled-${n}`, model: selected.model, object: 'chat.completion',
        choices: [{index: 0, message: {role: 'assistant', content: JSON.stringify(reply)}, finish_reason: 'stop'}], usage});
      if (joined) fixtures.set(selected.model, {
        content: 'sha256:' + createHash('sha256').update(payload).digest('hex'),
        bytes: Buffer.byteLength(payload), status: 200, eof: true,
      });
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
    const originals = await configureModelProject({project, endpoint, certPath, assets, runtimeSha256, selections, joined});
    const tasks = originals.map(({task}) => task);
    const custodyOptions = joined ? await joinedCustodyOptions(project, tasks) : null;
    async function cli(phase, args, {cwd = project, config = configuration} = {}) {
      const record = {phase, args, physicalRequests: calls.length};
      records.push(record);
      try {
        const projectSelection = args[0] === 'adopt' ? [] : ['--config', 'actql.config.json'];
        const result = await captureNativeMockCommand(binary, [...config, ...projectSelection, ...args], {
          cwd, env: joined && phase === 'run-1' ?
            {...environment, ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS: 'model-confirmations'} : environment,
          stderrPath: join(root, `${phase}.stderr`),
          timeout: 90_000, maxBuffer: 65_536,
        });
        Object.assign(record, result, {code: 0, signal: null, physicalRequests: calls.length});
      } catch (error) {
        Object.assign(record, {pid: error.pid, code: error.exitCode, signal: error.signal,
          stdout: error.stdout, stderr: error.stderr, physicalRequests: calls.length});
        throw serverFailure ?? error;
      }
      if (serverFailure) throw serverFailure;
      const {timing, accounting, raw} = splitNativeModelConfirmations(record.stderr, record.pid);
      if (!joined || phase !== 'run-1') assert.deepEqual([...accounting, ...raw], []);
      const groups = nativeMockAcceptanceObservations(timing);
      assert.equal(groups.length, 1);
      assert.equal(groups[0].pid, record.pid);
      const phaseRows = record.stderr.split('\n').filter(line => line.startsWith('ACTQL_NATIVE_PHASE '))
        .map(line => JSON.parse(line.slice('ACTQL_NATIVE_PHASE '.length)));
      const [close, ...duplicateClose] = phaseRows.filter(row => row.name === 'close');
      assert.deepEqual(duplicateClose, []);
      assert.deepEqual([close?.begins, close?.ends, close?.active, close?.unmatched_end], [1, 1, 0, 0]);
      const observed = {phase, pid: record.pid, firstClose: true, events: groups[0].events,
        physicalRequests: calls.length, connections: {...connections}};
      if (joined && phase.startsWith('saved-')) {
        const runPhases = ['preparation', 'execution', 'save'];
        for (const name of runPhases) {
          const rows = phaseRows.filter(row => row.name === name);
          assert.equal(rows.length, 1);
          const [row] = rows;
          assert.deepEqual([row.begins, row.ends, row.active, row.unmatched_end], [0, 0, 0, 0]);
        }
        const counters = timing.split('\n').filter(line => line.startsWith('ACTQL_NATIVE_COUNTER '))
          .map(line => JSON.parse(line.slice('ACTQL_NATIVE_COUNTER '.length)))
          .filter(row => [66, 67, 68, 69].includes(row.tag)).sort((left, right) => left.tag - right.tag);
        assert.deepEqual(counters.map(({tag, count}) => [tag, count]), [[66, 0], [67, 0], [68, 0], [69, 0]]);
        observed.runWork = {phases: runPhases, counters};
      }
      phases.push(observed);
      return {stdout: record.stdout, ...observed, accounting, raw};
    }
    assert.equal(JSON.parse((await cli('adopt', ['adopt', '--initialize-signing', '--json'])).stdout).kind,
      'local_host_adopted');
    const runs = [];
    const requireSends = n => {
      assert.equal(calls.length, n);
      assert.deepEqual(connections, {tcp: n, tls: n});
    };
    const protectedChecks = [];
    async function requireProtectedCheck(phase, file, selection) {
      const observed = await cli(phase, ['check', file, '--format', 'json', '--json'], selection);
      const check = JSON.parse(observed.stdout);
      assert.equal(check.outcome, 'completed');
      assert.equal(check.report.verdict, 'undetermined');
      assert.deepEqual(check.report.coverage, {
        limits: [], unresolved: [{boundary: 'source_resolution', reason: 'unresolved_protected'}],
      });
      assert.deepEqual(check.report.runnable, {reasons: [{code: 'unresolved_protected'}], verdict: 'no'});
      assert.deepEqual(check.report.reasons, []);
      assert.deepEqual(observed.events, []);
      requireSends(0);
      protectedChecks.push({phase, pid: observed.pid, firstClose: observed.firstClose,
        verdict: check.report.verdict, coverage: check.report.coverage, runnable: check.report.runnable});
    }
    if (joined) {
      const omittedView = structuredClone(joined.program);
      delete omittedView.stages[0].inputs.usage.view;
      const omittedFile = 'joined-omitted-view.json';
      await write(join(project, omittedFile), omittedView);
      await requireProtectedCheck('check-omitted-view', omittedFile);
      await unlink(join(project, omittedFile));

      // Adoption precedes Check on this independently scoped refused Account.
      const deniedProject = join(root, 'denied-file-read-project');
      const {configuration: deniedConfig} = await prepareProject(deniedProject);
      const deniedSelection = {cwd: deniedProject, config: deniedConfig};
      await configureModelProject({project: deniedProject, endpoint, certPath, assets,
        runtimeSha256, selections, joined, omitUsageRead: true});
      assert.equal(JSON.parse((await cli('adopt-denied-file-read',
        ['adopt', '--initialize-signing', '--json'], deniedSelection)).stdout).kind, 'local_host_adopted');
      requireSends(0);
      await write(join(deniedProject, 'joined.json'), joined.program);
      await requireProtectedCheck('check-denied-file-read', 'joined.json', deniedSelection);
    }
    const programs = joined ? [{file: 'joined.json', program: joined.program, rows: joined.expectedRows,
      sends: expectedSends}] : [1, 2, 3].map(n => ({
      file: `infer-${n}.json`, program: program(selections[0].taskId, n),
      rows: [{id: `row${n}`, outcome: 'ok', value: answer(n)}], sends: 1,
    }));
    let sends = 0;
    for (const [index, scenario] of programs.entries()) {
      const n = index + 1;
      const {file} = scenario;
      await write(join(project, file), scenario.program);
      const checked = await cli(`check-${n}`, ['check', file, '--format', 'json', '--json']);
      const check = JSON.parse(checked.stdout);
      assert.equal(check.outcome, 'completed');
      assert.equal(check.report.verdict, 'verified');
      assert.equal(check.report.runnable.verdict, 'yes');
      assert.deepEqual(checked.events, []);
      requireSends(sends);
      const runReceiptPath = join(root, 'joined-run-receipt.json');
      const outputs = joined ? Object.fromEntries(Object.keys(joined.program.results).map(name =>
        [name, {path: join(root, `joined-${name}.jsonl`)}])) : {};
      const presentation = joined ? [
        ...Object.entries(outputs).flatMap(([name, {path}]) => ['--deliver', `${name}=jsonl:${path}`]),
        '--receipt', runReceiptPath,
      ] : [];
      const started = await cli(`run-${n}`, ['run', file, '--format', 'json', ...presentation, '--json']);
      const report = JSON.parse(started.stdout);
      const state = joined ? report.run : report;
      assert.equal(state.status, 'succeeded');
      assert.match(state.run_id, /^sha256:[0-9a-f]{64}$/u);
      const attempts = requireModelAttempts(started.events, scenario.sends);
      sends += scenario.sends;
      requireSends(sends);
      let runReceipt, publicationContracts;
      if (joined) {
        for (const output of Object.values(outputs)) {
          output.payload = await readJoinedOutput(output.path);
        }
        const runReceiptWire = new TextDecoder('utf-8', {fatal: true}).decode(await readJoinedOutput(runReceiptPath));
        runReceipt = JSON.parse(runReceiptWire);
        assert.equal(canonicalText(runReceipt), runReceiptWire, 'Run receipt export changed the original canonical bytes');
        const {result_manifest: manifest} = runReceipt;
        publicationContracts = [
          {identity: runReceipt.receipt_identity_cid, wire: runReceiptWire},
          {identity: manifest.result_manifest_cid, wire: canonicalText(manifest)},
          ...Object.values(manifest.results).map(artifact =>
            ({identity: artifact.result_artifact_cid, wire: canonicalText(artifact)})),
        ];
      }
      const observeCustody = custodyOptions ? () => inspectNativeModelCustody({
        ...custodyOptions, runId: state.run_id, attempts, publicationContracts,
        expectedPolicyWire: canonicalText(joined.finalResultPolicy), expectedResponseViews: joined.modelRawResponseViews,
      }) : null;
      const custody = observeCustody ? await observeCustody() : null;
      const accounting = custody ? requireNativeModelAccounting(started.accounting, custody,
        new Map(tasks.map((task, index) => [task, joinedUsage[index]]))) : null;
      const raw = custody ? requireNativeRawReceipts(started.raw, custody,
        new Map(originals.map(({task, profile}, index) => [task, {profile, ...fixtures.get(selections[index].model)}]))) : null;
      const delivery = joined ? requireNativeJoinedDelivery({report, runReceipt, outputs,
        rows: scenario.rows, policyCid: cid(joined.finalResultPolicy), custody,
        additionalResults: joined.additionalResults}) : null;
      if (joined) {
        const dataPath = join(project, 'source-data.json');
        assert.equal(await readFile(dataPath, 'utf8'), canonicalText(joined.payload));
        await unlink(dataPath);
        await unlink(join(project, file));
      }
      // Fresh-process delivery reads the original Run after its authored inputs
      // are unavailable in the joined case.
      const saved = await cli(`saved-${n}`, ['result', state.run_id, '--result', 'answer', '--format', 'jsonl']);
      const rows = saved.stdout.trim().split('\n').map(line => JSON.parse(line));
      assert.deepEqual(rows, scenario.rows);
      assert.deepEqual(saved.events, []);
      requireSends(sends);
      const additionalSaved = {};
      if (joined) {
        assert.deepEqual(Buffer.from(saved.stdout, 'utf8'), outputs.answer.payload, 'Cold Saved returned different answer JSONL');
        for (const [name, expected] of Object.entries(joined.additionalResults)) {
          const observed = await cli(`saved-${n}-${name}`,
            ['result', state.run_id, '--result', name, '--format', 'jsonl']);
          const rows = observed.stdout.trim().split('\n').map(line => JSON.parse(line));
          assert.deepEqual(rows, expected);
          assert.deepEqual(Buffer.from(observed.stdout, 'utf8'), outputs[name].payload,
            'Cold Saved returned different named Result JSONL');
          assert.deepEqual(observed.events, []);
          requireSends(sends);
          additionalSaved[name] = {pid: observed.pid, rows,
            artifactCid: runReceipt.result_manifest.results[name].result_artifact_cid};
        }
        for (const {path, payload} of Object.values(outputs)) {
          assert.deepEqual(await readJoinedOutput(path), payload, 'Cold Saved changed the delivered file');
        }
        assert.deepEqual(await observeCustody(), custody, 'Cold Saved changed the original publication or Model custody');
      }
      runs.push({runId: state.run_id, ...(joined ? {attempts, custody, accounting, raw, delivery} : {call: attempts[0]}), rows,
        ...(includeReview ? {additionalSaved} : {}),
        coldPid: saved.pid});
    }
    assert.equal(new Set(runs.map(run => run.runId)).size, programs.length);
    assert.equal(new Set(runs.flatMap(run => run.attempts ?? [run.call])).size, expectedSends);
    assert.equal(new Set(phases.map(phase => phase.pid)).size, phases.length);
    return {image: modelImage, fixture: 'controlled-loopback-tls', phases, runs, calls, connections,
      ...(joined ? {protectedChecks} : {})};
  } finally {
    for (const socket of sockets) socket.destroy();
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
}
