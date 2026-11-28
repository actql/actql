// Controlled HTTPS acceptance on an already authenticated, installed CLI.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {once} from 'node:events';
import {constants} from 'node:fs';
import {lstat, mkdir, open, readFile, realpath, rename, unlink, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {canonicalText} from './check-canonical-json.mjs';
import {nativeFileModelEffect, requireNativeFileModelEffectTrace} from './fixtures/native-file-model-effect.mjs';
import {nativeFileModelEffectPolicy} from './fixtures/native-file-model-effect-policy.mjs';
import {nativeJoinedModelRun, requireModelAttempts, requireNativeJoinedDelivery} from './fixtures/native-joined-model-run.mjs';
import {dropNativeDependentModelReply, nativeDependentModelDocument, nativeDependentModelInput, nativeDependentModelOutputPolicy,
  nativeDependentModelRun, nativeModelBindingIdentity} from './fixtures/native-dependent-model-run.mjs';
import {inspectNativeModelCustody, withMissingNativeModelFixtureCell} from './fixtures/native-model-custody-observation.mjs';
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
const sharedProvider = 'models/http';
const completionPath = '/v1/chat/completions';
const answer = n => ({level: n === 1 ? 'low' : 'high', reason: `controlled reply ${n}`});
const joinedUsage = [{input_tokens: 0, output_tokens: 8}, {input_tokens: 15, output_tokens: null}];
const cid = body => 'sha256:' + createHash('sha256').update(canonicalText(body)).digest('hex');
const seal = body => ({...body, self_cid: cid(body)});
const json = async path => JSON.parse(await readFile(path, 'utf8'));
const write = (path, body, flag = 'wx') => writeFile(path, canonicalText(body), {mode: 0o600, flag});

async function configureModelTask({project, endpoint, certPath, dataPolicy, runtimeSha256, selection, itemCount, projectRegistry}) {
  const {prefix, taskId, model, token, provider} = selection;
  const file = suffix => `${prefix}-${suffix}.json`;
  const keyFile = `${prefix}.key`;
  const fixture = await json(new URL('./fixtures/public-model-task-signed64.json', import.meta.url));
  const task = {...fixture.task, task_id: taskId, version: taskId, connector_id: provider,
    authored_model_selector: model, max_items: itemCount,
    generation_config: {...fixture.task.generation_config, max_output_tokens: 100}};
  if (selection.receivesModelOutput) {
    task.input_contract = nativeDependentModelInput(fixture.output_schema);
    task.input_schema_cid = cid(task.input_contract);
  }
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
    backoff_contract_cid: backoff.self_cid, max_attempts_per_slot: 1, max_total_attempts: itemCount,
    max_total_cost_units: 0, max_total_duration_ms: 6000 * itemCount, max_total_wire_bytes: 131072 * itemCount,
    max_total_token_reservation: 1024 * itemCount, media_input_contracts: {}, default_publication: 'outcomes'});
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

  let taskFile;
  if (projectRegistry) {
    taskFile = `${taskId.slice('model-task:'.length)}.yaml`;
    let document = fixture.document.replace(`task: ${fixture.task.task_id}`, `task: ${taskId}`)
      .replace('provider: openai, name: "<model id>"', `provider: "${provider}", name: "${model}"`)
      .replace('max_items: 5000', `max_items: ${itemCount}`).replace('max_output_tokens: 200', 'max_output_tokens: 100');
    assert(document.includes(`task: ${taskId}\nmodel: { provider: "${provider}", name: "${model}" }`));
    if (selection.receivesModelOutput) document = nativeDependentModelDocument(document, task.input_contract);
    await writeFile(join(project, taskFile), document, {mode: 0o600, flag: 'wx'});
  }
  return {task, taskFile, binding: nativeModelBindingIdentity(provider, vendor, files[file('provider')]), files: [...Object.keys(files), ...Object.keys(originalWires)], installation: {
    task_id: taskId, provider_id: provider, credential_installation: file('credential'),
    installation_revision: file('revision'), configuration_contract: file('contract'),
    response_profile: file('profile'), response_profile_cid: profile.self_cid,
    execution_file: file('execution'), run_policy_file: file('policy'),
  }};
}

async function configureModelProject({project, endpoints, certPath, assets, runtimeSha256, selections,
  joined, dependent, fileEffect, omitUsageRead = false, itemCount = 1}) {
  const environmentPath = join(project, 'environment.json');
  const environment = await json(environmentPath);
  assert.deepEqual(environment.model_task_contracts, []);
  Object.assign(environment.host_policy_profile.capacity, {
    max_model_request_bytes_per_item: requestBytes, max_model_input_tokens_per_item: 256,
    max_model_total_duration_ms: 6000 * itemCount,
  });
  const policies = joined ?? fileEffect?.policy;
  const dataPolicy = policies ? canonicalText(policies.modelRawDataPolicy) : assets['result-policy'];
  if (policies) {
    const expectedFinalPolicyCid = cid(policies.finalResultPolicy);
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
    const endpoint = endpoints.get(selection.provider);
    assert(endpoint);
    configured.push(await configureModelTask({project, endpoint, certPath, dataPolicy, runtimeSha256,
      selection, itemCount, projectRegistry: fileEffect === undefined}));
  }
  const originals = configured.map(({task, installation, binding}) => ({
    task: task.contract_cid, profile: installation.response_profile_cid, binding, outputSchema: task.output_schema_cid,
    provider: task.connector_id,
  }));
  if (dependent) {
    const path = join(project, configured[1].installation.run_policy_file);
    await write(path, {...await json(path), upstream_model_outputs: nativeDependentModelOutputPolicy(...originals)}, 'w');
  }
  if (fileEffect) environment.model_task_contracts = configured.map(({task}) => task);
  delete environment.evidence_bundle_cid;
  environment.evidence_bundle_cid = cid(environment);
  await write(environmentPath, environment, 'w');
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
    'bounded-native-model-confirm', task.connector_id, task.contract_cid, ['infer', 'model_raw_capture'])));
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
  if (fileEffect) {
    const {fixture} = fileEffect;
    const {principal, connection} = local;
    const resource = 'key/initial-host-attestation';
    assert.equal(principal, account.account_id);
    assert.equal(configured.length, 1);
    local.initial_host_signing = {principal, connection, resource};
    local.installation_files.push('host.json');
    await write(join(project, 'host.json'), {version: 'actql-host/0.1'});
    const model = account.entries.find(entry => entry.entry_id === 'bounded-native-model');
    account.entries = [
      allow('bounded-effect-file', 'drive', 'files', ['read']),
      allow('bounded-effect-result', connection, 'result/' + fixture.resultName, ['read']),
      allow('bounded-effect-run', connection, 'run', ['cancel', 'publish', 'read', 'resolve', 'submit']),
      allow('bounded-effect-signer', connection, resource, ['sign']),
      {...allow('bounded-effect-target', 'salesforce', 'Opportunity', ['effect']), outcome: 'delegate'},
      allow('bounded-effect-target-read', 'salesforce', 'Opportunity', ['read']),
      model,
    ];
    for (const name of ['read.json', 'file-read.json']) {
      const path = join(project, name);
      const original = await json(path);
      original.native.result_read.result_names = [fixture.resultName];
      await write(path, original, 'w');
    }
  }
  await write(configPath, config, 'w');
  await write(accountPath, account, 'w');

  if (fileEffect) {
    await mkdir(join(project, 'mock'), {mode: 0o700});
    for (const [name, body] of Object.entries(fileEffect.fixture.files)) {
      await writeFile(join(project, name), body, {mode: 0o600, flag: 'wx'});
    }
  } else {
    await write(join(project, 'actql.config.json'), {version: 'actql-config/0.1',
      state_dir: './host', model_tasks: './model-tasks.json'});
    await write(join(project, 'model-tasks.json'), {version: 'actql-model-tasks/0.1',
      providers: Object.fromEntries(selections.map(({provider}) => [provider, {type: 'openai'}])),
      tasks: Object.fromEntries(configured.map(({task, taskFile}) => [task.task_id, './' + taskFile])),
      default_provider: selections[0].provider});
  }
  return originals;
}

// Same physical operator preparation as the existing installed Model cases.
// The separate Project supplies only the bounded File Source and Effect.
export async function prepareControlledNativeFileModelEffect({
  project, prepareProject, endpoint, certPath, assets, runtimeSha256, selection,
  fixture = nativeFileModelEffect(selection.taskId),
}) {
  const {configuration} = await prepareProject(project);
  assert.equal(await realpath(project), project, 'Select the physical File Effect project root');
  const policy = nativeFileModelEffectPolicy();
  const selected = {provider: sharedProvider, ...selection};
  const endpoints = new Map([[selected.provider, endpoint]]);
  const [original] = await configureModelProject({project, endpoints, certPath, assets, runtimeSha256,
    selections: [selected], fileEffect: {fixture, policy}});
  return {fixture, policy, original, configuration: [...configuration, '--host-config', join(project, 'host.json')]};
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

async function readNativeFixtureFile(path) {
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
    return {bytes, original};
  } finally {
    await file.close();
  }
}

async function readJoinedOutput(path) {
  return (await readNativeFixtureFile(path)).bytes;
}

async function effectTargetSnapshot(path) {
  const {bytes, original} = await readNativeFixtureFile(path);
  return {bytes: new TextDecoder('utf-8', {fatal: true}).decode(bytes),
    sha256: createHash('sha256').update(bytes).digest('hex'),
    device: String(original.dev), inode: String(original.ino), size: String(original.size),
    mtimeNs: String(original.mtimeNs), ctimeNs: String(original.ctimeNs)};
}

export function requireNativeFileModelDeletePreview(stdout, fixture) {
  const lines = stdout.trimEnd().split('\n');
  const own = prefix => {
    const selected = lines.filter(line => line.startsWith(prefix));
    assert.equal(selected.length, 1, 'Missing or repeated saved Preview field');
    return JSON.parse(selected[0].slice(prefix.length));
  };
  const header = 'Stored Effect Preview (read-only; not approval):';
  const start = lines.indexOf(header);
  assert(start >= 0 && start === lines.lastIndexOf(header));
  const [{id}] = fixture.rows;
  const before = JSON.parse(fixture.before).salesforce.Opportunity.rows.find(row => row.id === id);
  assert(before);
  assert.deepEqual(lines.slice(start + 1).map(line => {
    const field = /^      (Before|After): (.+)$/u.exec(line);
    return field ? [field[1], JSON.parse(field[2])] : line;
  }), [
    '  Effect: "delete"  Target: "connector://salesforce/Opportunity"',
    '  Items: 1', '  Preview strength: "full_diff"', '  Changes:', `    Row: ${JSON.stringify(id)}`,
    ['Before', {state: 'present', value: before}], ['After', {state: 'absent'}],
  ]);
  return {run_id: own('Run: '), status: own('State: '),
    checkpoint: {checkpoint_id: own('Checkpoint: '), checkpoint_cid: own('  Original CID: ')}};
}

async function modelCustodyOptions(project, originals, count) {
  const tasks = originals.map(({task}) => task);
  assert.equal(new Set(tasks).size, count);
  const {native: {run}} = await json(join(project, 'run.json'));
  return {
    journalPath: join(project, 'host/client.sqlite3'),
    storePath: join(project, 'results/.actql-publication.sqlite3'),
    authority: run.store_authority_cid, namespace: run.namespace_id, provider: sharedProvider, tasks,
    providerByTask: new Map(originals.map(({task, provider}) => [task, provider])),
  };
}

// Match the single ordinary primary diagnostic, then let the existing Native
// parser verify every remaining row and its End marker unmodified.
export function requireNativeModelCommandFailure(timing, expected) {
  const lines = timing.split('\n');
  const reported = lines.slice(0, -1).filter(line => !line.startsWith('ACTQL_NATIVE_'));
  assert.equal(reported.length, 1, 'Missing or competing Native failure diagnostics');
  if (typeof expected === 'string') assert.equal(reported[0], expected);
  else if (expected instanceof RegExp) assert.match(reported[0], expected);
  else assert.deepEqual(JSON.parse(reported[0]), expected);
  return lines.filter(line => line !== reported[0]).join('\n');
}

export async function observeInstalledNativeModel({root, binary, modelImage, prepareProject,
  environment, runtimeSha256, assets, records, joinedFile = false, terminal = null, referenceControl = false,
  dependent = null, fileModelEffect = false, includeReview = false}) {
  assert(!includeReview || joinedFile);
  assert(modelImage?.role === 'model-http', 'Required Model HTTPS member is unavailable');
  assert(!fileModelEffect || !joinedFile);
  await mkdir(root, {mode: 0o700});
  if (fileModelEffect) root = await realpath(root);
  const project = join(root, 'project');
  const tls = join(root, 'tls');
  await mkdir(tls, {mode: 0o700});
  execFileSync('/usr/bin/openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-days', '2', '-subj', '/CN=ActQL Controlled Model', '-addext',
    'subjectAltName=IP:127.0.0.1', '-keyout', 'key.pem', '-out', 'cert.pem'],
  {cwd: tls, stdio: 'ignore', timeout: 30_000});
  const certPath = join(tls, 'cert.pem');
  assert(dependent === null || ['completed', 'rate-limited', 'lost-reply'].includes(dependent));
  assert(!(dependent && joinedFile));
  const selections = ((joinedFile || dependent) ? selectedModels : selectedModels.slice(0, 1)).map((selection, index) => ({
    ...selection, receivesModelOutput: dependent !== null && index === 1,
    provider: dependent ? (index === 0 ? 'models/r6-producer' : 'models/r6-receiver') : sharedProvider,
    token: 'synthetic-controlled-model-' + randomUUID(),
  }));
  const taskIds = selections.map(({taskId}) => taskId);
  const receiverRateLimited = dependent === 'rate-limited';
  const joined = dependent ? nativeDependentModelRun(...taskIds, {receiverRateLimited}) :
    joinedFile ? nativeJoinedModelRun(taskIds[0], taskIds[1], {includeReview}) : null;
  const effect = fileModelEffect ? nativeFileModelEffect(selections[0].taskId) : null;
  assert(!((joined || effect) && (terminal || referenceControl)));
  const expectedSends = joined || effect ? selections.length : terminal ? 1 : 3;
  const calls = [];
  const fixtures = new Map();
  let effectInput;
  const phases = [];
  const connections = {tcp: 0, tls: 0};
  const sockets = new Set();
  let serverFailure;
  let receiverReplyCut;
  const tlsOptions = {cert: await readFile(certPath), key: await readFile(join(tls, 'key.pem')),
    requestTimeout: 5000};
  const providers = [...new Set(selections.map(({provider}) => provider))];
  const peers = new Map(providers.map(id => [id, {tcp: 0, tls: 0, posts: 0}]));
  const endpoints = new Map();
  const servers = new Map();
  const observeRequest = async (peer, request, response) => {
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
      peers.get(peer).posts++;
      assert.equal(selected?.provider, peer, 'Request reached a different Provider endpoint');
      let notesMatch;
      if (joined || effect) {
        assert(Array.isArray(body.messages), 'File-backed request did not contain the admitted Chat messages');
        assert.deepEqual(body.messages.map(message => message?.role), ['system', 'user']);
        const [{content: system}, {content: user}] = body.messages;
        assert.equal(typeof system, 'string');
        assert.equal(typeof user, 'string');
        const input = JSON.parse(user);
        const expected = selected?.receivesModelOutput ? joined.expectedReceiverInput : joined?.expectedInput ?? effect.input;
        assert.deepEqual(input, expected);
        if (effect) effectInput = input;
        notesMatch = true;
      } else {
        const messages = JSON.stringify(body.messages);
        notesMatch = typeof messages === 'string' && messages.includes(`original input ${n}`);
      }
      const call = {method: request.method, path: request.url,
        authorized: request.headers.authorization === 'Bearer ' + selected.token,
        model: body.model, notesMatch};
      calls.push(call);
      assert.deepEqual(call, {method: 'POST', path: completionPath, authorized: true, model: selected?.model,
        notesMatch: true});
      assert(n <= expectedSends, 'Unexpected Model resend');
      const selectedIndex = selections.indexOf(selected);
      if (joined) assert(!calls.slice(0, -1).some(request => request.model === selected.model), 'Repeated Model selection');
      if (dependent) {
        assert.equal(selectedIndex, n - 1, 'The dependent Model started outside the checked Task order');
        if (dependent === 'lost-reply' && selected.receivesModelOutput) {
          assert.equal(receiverReplyCut, undefined);
          // The installed Journal is exclusive while the original command
          // runs. Observe the live reply here and verify custody after close.
          receiverReplyCut = await dropNativeDependentModelReply(request, response, () => ({
            ordinal: n, producer: calls[0].model, receiver: call.model,
          }));
          return;
        }
      }
      const reply = joined ? joined.answers[selectedIndex] : effect?.reply ?? answer(n);
      const reported = joined ? joinedUsage[selectedIndex] : {input_tokens: n === 1 ? 0 : 15, output_tokens: 8};
      const usage = {prompt_tokens: reported.input_tokens,
        ...(reported.output_tokens === null ? {} : {completion_tokens: reported.output_tokens})};
      const rateLimited = receiverRateLimited && selected.receivesModelOutput;
      const payload = rateLimited ? 'controlled receiver quota exhausted' :
        terminal?.body ?? JSON.stringify({id: `controlled-${n}`, model: selected.model, object: 'chat.completion',
          choices: [{index: 0, message: {role: 'assistant', content: JSON.stringify(reply)}, finish_reason: 'stop'}], usage});
      const status = rateLimited ? 429 : terminal?.status ?? 200;
      if (joined || terminal || effect) fixtures.set(selected.model, {
        content: 'sha256:' + createHash('sha256').update(payload).digest('hex'),
        bytes: Buffer.byteLength(payload), status, eof: true,
      });
      response.writeHead(status, {'content-type': 'application/json',
        'content-length': Buffer.byteLength(payload), connection: 'close'});
      response.end(payload);
    } catch (error) {
      serverFailure ??= error;
      response.destroy();
    }
  };
  try {
    for (const id of providers) {
      const server = createServer(tlsOptions, (request, response) => observeRequest(id, request, response));
      servers.set(id, server);
      const peer = peers.get(id);
      server.on('error', error => {serverFailure ??= error;});
      server.on('connection', socket => {
        connections.tcp++;
        peer.tcp++;
        sockets.add(socket);
        socket.once('close', () => sockets.delete(socket));
      });
      server.on('secureConnection', () => {
        connections.tls++;
        peer.tls++;
      });
      const listening = once(server, 'listening');
      server.listen({host: '127.0.0.1', port: 0});
      await listening;
      endpoints.set(id, `https://127.0.0.1:${server.address().port}${completionPath}`);
    }
    if (dependent) {
      assert.equal(providers.length, 2);
      assert.equal(new Set(endpoints.values()).size, 2);
      assert.equal(new Set(selections.map(({token}) => token)).size, 2);
    }
    const observePeers = () => providers.map(provider => ({provider, endpoint: endpoints.get(provider), ...peers.get(provider)}));
    let configuration, originals, effectPolicy;
    if (effect) {
      const selected = await prepareControlledNativeFileModelEffect({project, prepareProject,
        endpoint: endpoints.get(selections[0].provider), certPath, assets, runtimeSha256,
        selection: selections[0], fixture: effect});
      ({configuration, policy: effectPolicy} = selected);
      originals = [selected.original];
    } else {
      ({configuration} = await prepareProject(project));
      originals = await configureModelProject({project, endpoints, certPath, assets, runtimeSha256,
        selections, joined, dependent, itemCount: terminal?.items ?? 1});
    }
    const tasks = originals.map(({task}) => task);
    const custodyOptions = joined || terminal || effect ?
      await modelCustodyOptions(project, originals, joined ? 2 : 1) : null;
    async function cli(phase, args, {cwd = project, config = configuration, expectedFailure} = {}) {
      const record = {phase, args, physicalRequests: calls.length};
      records.push(record);
      const confirmations = ((joined || terminal) && phase === 'run-1') || (effect && phase === 'run');
      try {
        // Issue and locate the reference on this adopted operator. The Project
        // is selected independently by Check, Run and the supported Saved reads.
        const operatorOnly = ['adopt', 'new-submission', 'lookup-submission'].includes(args[0]);
        const projectSelection = operatorOnly ? [] : ['--config', 'actql.config.json'];
        const result = await captureNativeMockCommand(binary, [...config, ...projectSelection, ...args], {
          cwd, env: confirmations ?
            {...environment, ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS: 'model-confirmations'} : environment,
          stderrPath: join(root, `${phase}.stderr`),
          timeout: 90_000, maxBuffer: 65_536,
        });
        Object.assign(record, result, {code: 0, signal: null, physicalRequests: calls.length});
      } catch (error) {
        Object.assign(record, {pid: error.pid, code: error.exitCode, signal: error.signal,
          stdout: error.stdout, stderr: error.stderr, physicalRequests: calls.length});
        if (!expectedFailure || error.code !== 1 || error.exitCode !== 1 || error.signal !== null || error.killed)
          throw serverFailure ?? error;
      }
      if (serverFailure) throw serverFailure;
      assert.equal(record.code, expectedFailure ? 1 : 0);
      const {timing, accounting, raw} = splitNativeModelConfirmations(record.stderr, record.pid);
      if (!confirmations) assert.deepEqual([...accounting, ...raw], []);
      const nativeTiming = expectedFailure ? requireNativeModelCommandFailure(timing, expectedFailure) : timing;
      if (expectedFailure) assert.equal(record.stdout, '');
      const groups = nativeMockAcceptanceObservations(nativeTiming);
      assert.equal(groups.length, 1);
      assert.equal(groups[0].pid, record.pid);
      const phaseRows = record.stderr.split('\n').filter(line => line.startsWith('ACTQL_NATIVE_PHASE '))
        .map(line => JSON.parse(line.slice('ACTQL_NATIVE_PHASE '.length)));
      const [close, ...duplicateClose] = phaseRows.filter(row => row.name === 'close');
      assert.deepEqual(duplicateClose, []);
      assert.deepEqual([close?.begins, close?.ends, close?.active, close?.unmatched_end], [1, 1, 0, 0]);
      const observed = {phase, pid: record.pid, firstClose: true, events: groups[0].events,
        physicalRequests: calls.length, connections: {...connections}};
      if ((joined && phase.startsWith('saved-')) || (dependent && phase.startsWith('status-')) ||
          (effect && ['saved-status', 'saved-result'].includes(phase))) {
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
      if (terminal || referenceControl || dependent === 'lost-reply') {
        const [counter, ...duplicates] = nativeTiming.split('\n')
          .filter(line => line.startsWith('ACTQL_NATIVE_COUNTER '))
          .map(line => JSON.parse(line.slice('ACTQL_NATIVE_COUNTER '.length)))
          .filter(row => row.name === 'sqlite_open_calls');
        assert.deepEqual(duplicates, []);
        assert(counter);
        observed.sqliteOpenCalls = counter.count;
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
      if (dependent) {
        assert(n === 0 || n === 2);
        for (const peer of peers.values()) {
          assert.deepEqual(peer, {tcp: n / 2, tls: n / 2, posts: n / 2});
        }
      }
    };
    if (effect) {
      const target = join(project, 'mock/data.json');
      const before = await effectTargetSnapshot(target);
      assert.equal(before.bytes, effect.before);
      const check = await cli('check', ['check', effect.document, '--format', 'aql', '--json']);
      const checked = JSON.parse(check.stdout);
      assert.equal(checked.outcome, 'completed');
      assert.equal(checked.report.verdict, 'verified');
      assert.equal(checked.report.runnable.verdict, 'yes');
      assert.deepEqual(check.events, []);
      assert.deepEqual(await effectTargetSnapshot(target), before);
      requireSends(0);
      const started = await cli('run',
        ['run', effect.document, '--format', 'aql', '--stop-before', 'commit', '--json']);
      const waiting = JSON.parse(started.stdout);
      assert.equal(waiting.version, 'actql-run-state/0.1');
      assert.equal(waiting.status, 'waiting_checkpoint');
      assert.match(waiting.checkpoint.checkpoint_cid, /^sha256:[0-9a-f]{64}$/u);
      requireSends(1);
      const attempts = requireModelAttempts(started.events, 1);
      const observeCustody = () => inspectNativeModelCustody({...custodyOptions,
        runId: waiting.run_id, attempts, publicationContracts: [], singleEffect: true,
        expectedPolicyWire: canonicalText(effectPolicy.modelRawDataPolicy),
        expectedResponseViews: effectPolicy.modelRawResponseViews});
      const custody = await observeCustody();
      const accounting = requireNativeModelAccounting(started.accounting, custody,
        new Map([[tasks[0], {input_tokens: 0, output_tokens: 8}]]));
      const raw = requireNativeRawReceipts(started.raw, custody,
        new Map([[tasks[0], {profile: originals[0].profile, ...fixtures.get(selections[0].model)}]]));
      await unlink(join(project, effect.document));
      await unlink(join(project, 'model-tasks.json'));
      const preview = requireNativeFileModelDeletePreview(
        (await cli('waiting-status', ['status', waiting.run_id])).stdout, effect);
      const pending = await effectTargetSnapshot(target);
      assert.equal(preview.run_id, waiting.run_id);
      assert.equal(preview.status, 'waiting_checkpoint');
      assert.equal(preview.checkpoint.checkpoint_id, waiting.checkpoint.checkpoint_id);
      assert.equal(preview.checkpoint.checkpoint_cid, waiting.checkpoint.checkpoint_cid);
      assert.deepEqual(pending, before, 'Refuse approval if Preview changed the target');
      await cli('approve', ['approve', waiting.checkpoint.checkpoint_id, '--wait', '--json']);
      await assert.rejects(lstat(target + '.actql-write.lock'), {code: 'ENOENT'});
      const applied = await effectTargetSnapshot(target);
      await unlink(join(project, 'mock/catalog.json'));
      await unlink(join(project, 'connectors.json'));
      const completed = JSON.parse((await cli('saved-status', ['status', waiting.run_id, '--json'])).stdout);
      const saved = await cli('saved-result', ['result', waiting.run_id, '--result', effect.resultName, '--format', 'jsonl']);
      const savedRows = saved.stdout.trimEnd().split('\n').map(line => JSON.parse(line));
      const afterSaved = await effectTargetSnapshot(target);
      const accepted = requireNativeFileModelEffectTrace({fixture: effect, phases, input: effectInput,
        waiting, preview, completed, savedRows, before, pending, applied, afterSaved});
      assert.deepEqual(await observeCustody(), custody, 'Approval or Saved changed original Model evidence');
      return {image: modelImage, fixture: 'controlled-file-model-effect', phases, calls, connections, ...accepted,
        custody, accounting, raw, savedRows};
    }
    async function prepareReference() {
      const requestId = dependent ? 'r6-dependent-model-reference' : 'r13-reference-oracle';
      const issued = await cli('new-submission', ['new-submission', '--request-id', requestId]);
      const submission = JSON.parse(issued.stdout);
      assert.deepEqual(issued.events, []);
      await write(join(project, 'submission.json'), submission);
      return {submission, options: ['--submission-ref-file', 'submission.json',
        '--operation-attempt-id', dependent ? 'r6-original-attempt' : 'r13-original-attempt']};
    }
    async function recoverReference(selected) {
      const observed = await cli('lookup-submission', ['lookup-submission', '--submission-ref-file', 'submission.json']);
      assert.deepEqual(observed.events, []);
      const lookup = JSON.parse(observed.stdout);
      assert.equal(lookup.kind, 'local_submission_lookup');
      assert.equal(lookup.history, 'retained');
      assert.equal(lookup.phase, 'ready');
      assert.deepEqual(lookup.submissionRef, selected.submission);
      assert.match(lookup.requestId, /^sha256:[0-9a-f]{64}$/u);
      await write(join(project, 'run-ref.json'), lookup.ref);
      return lookup;
    }
    async function referenceStatus(lookup) {
      await write(join(project, 'foreign-run-ref.json'), {
        ...lookup.ref, runDefinitionCid: cid('different original definition'),
      });
      const args = file => ['status', '--ref-file', file, '--submission-ref-file', 'submission.json', '--json'];
      const before = calls.length;
      const foreign = await cli('status-foreign-ref', args('foreign-run-ref.json'),
        {expectedFailure: {code: 'ACTQL_E_COMMAND_FAILED', message: 'LocalOriginalRunReferenceMismatch'}});
      assert.equal(foreign.physicalRequests, before);
      const saved = await cli('status-ref', args('run-ref.json'));
      assert.equal(saved.physicalRequests, before);
      assert.deepEqual(foreign.events, []);
      assert.deepEqual(saved.events, []);
      const wrapper = JSON.parse(saved.stdout);
      assert.equal(wrapper.kind, 'local_saved_run_state');
      assert.deepEqual(wrapper.ref, lookup.ref);
      assert.deepEqual(wrapper.submissionRef, lookup.submissionRef);
      return {wrapper, opened: saved.sqliteOpenCalls, foreignOpened: foreign.sqliteOpenCalls};
    }
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
    if (joinedFile) {
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
      await configureModelProject({project: deniedProject, endpoints, certPath, assets,
        runtimeSha256, selections, joined, omitUsageRead: true});
      assert.equal(JSON.parse((await cli('adopt-denied-file-read',
        ['adopt', '--initialize-signing', '--json'], deniedSelection)).stdout).kind, 'local_host_adopted');
      requireSends(0);
      await write(join(deniedProject, 'joined.json'), joined.program);
      await requireProtectedCheck('check-denied-file-read', 'joined.json', deniedSelection);
    }
    if (terminal) {
      const file = 'terminal.json';
      const authored = program(selections[0].taskId, 1);
      authored.stages[0].steps[2].infer.on_non_success = 'fail';
      if (terminal.items === 2) {
        authored.stages[0].steps[0].values.rows.push(program(selections[0].taskId, 2).stages[0].steps[0].values.rows[0]);
      }
      await write(join(project, file), authored);
      const checked = await cli('check-1', ['check', file, '--format', 'json', '--json']);
      const check = JSON.parse(checked.stdout);
      assert.equal(check.outcome, 'completed');
      assert.equal(check.report.verdict, 'verified');
      assert.equal(check.report.runnable.verdict, 'yes');
      assert.deepEqual(checked.events, []);
      const selected = await prepareReference();
      requireSends(0);
      const started = await cli('run-1', ['run', file, '--format', 'json', ...selected.options, '--json'],
        {expectedFailure: terminal.diagnostic});
      const attempts = requireNativeTerminalModelAttempt(started.events, terminal);
      requireSends(1);
      await unlink(join(project, file));
      const lookup = await recoverReference(selected);
      const observeCustody = () => inspectNativeModelCustody({...custodyOptions, attempts, publicationContracts: [],
        expectedPolicyWire: assets['result-policy'], expectedResponseViews: new Map(),
        terminal: {submissionId: lookup.requestId, diagnostic: terminal.diagnostic}});
      const custody = await observeCustody();
      assert.equal(custody.definition, lookup.runDefinitionCid);
      assert.equal(custody.terminalRun.controlRevision, lookup.controlRevision);
      const [{task, profile}] = originals;
      const accounting = requireNativeModelAccounting(started.accounting, custody, new Map([[task, terminal.usage]]));
      const raw = requireNativeRawReceipts(started.raw, custody, new Map([[task, {
        profile, ...fixtures.get(selections[0].model),
      }]]));
      const id = await cli('status-id', ['status', custody.runId, '--json']);
      assert.deepEqual(id.events, []);
      assert.deepEqual(JSON.parse(id.stdout), custody.terminalRun.state);
      requireSends(1);
      const {wrapper, opened, foreignOpened} = await referenceStatus(lookup);
      assert.deepEqual(wrapper.state, custody.terminalRun.state);
      assert.equal(wrapper.controlRevision, custody.terminalRun.controlRevision);
      assert(opened > foreignOpened, 'Expected Store open only after matching both references');
      assert.deepEqual(await observeCustody(), custody, 'Cold status changed original Run or Model custody');
      requireSends(1);
      assert.equal(new Set(phases.map(phase => phase.pid)).size, phases.length);
      return {image: modelImage, fixture: 'controlled-loopback-tls-terminal', status: terminal.status, admittedItems: terminal.items,
        phases, calls, connections, custody, accounting, raw, coldReferences: {opened, foreignOpened}};
    }
    if (dependent === 'lost-reply') {
      const file = 'dependent.json';
      await write(join(project, file), joined.program);
      const checked = await cli('check-1', ['check', file, '--format', 'json', '--json']);
      const check = JSON.parse(checked.stdout);
      assert.equal(check.outcome, 'completed');
      assert.equal(check.report.verdict, 'verified');
      assert.equal(check.report.runnable.verdict, 'yes');
      assert.deepEqual(checked.events, []);
      const selected = await prepareReference();
      requireSends(0);
      const dependencyCustody = {
        ...custodyOptions, publicationContracts: [],
        expectedPolicyWire: canonicalText(joined.finalResultPolicy),
        expectedResponseViews: joined.modelRawResponseViews,
      };
      const started = await cli('run-1', ['run', file, '--format', 'json', ...selected.options, '--json'], {
        expectedFailure: /^actql-native-client: LocalOriginalSourceWorkUnavailable:compute-driver-[a-z-]+$/u,
      });
      const byAttempt = new Map();
      for (const {identity, tag, ordinal} of started.events) {
        assert.match(identity, /^sha256:[0-9a-f]{64}$/u);
        assert.equal(ordinal, 0);
        if (!byAttempt.has(identity)) byAttempt.set(identity, []);
        byAttempt.get(identity).push(tag);
      }
      assert.deepEqual([...byAttempt.values()], [[0, 1, 2], [0, 1]]);
      const [producerAttempt, receiverAttempt] = byAttempt.keys();
      // BeforeInvoke follows the original Entry ACK. The first Model must
      // have returned before the admitted receiver can cross that boundary.
      assert.deepEqual(started.events.map(({identity, tag}) => [identity, tag]), [
        [producerAttempt, 0], [producerAttempt, 1], [producerAttempt, 2],
        [receiverAttempt, 0], [receiverAttempt, 1],
      ]);
      assert.deepEqual(receiverReplyCut, {ordinal: 2, producer: selections[0].model, receiver: selections[1].model});
      requireSends(2);
      await unlink(join(project, file));
      await unlink(join(project, 'source-data.json'));
      const lookup = await recoverReference(selected);
      const observeCustody = (enteredRawAbsent = false) => inspectNativeModelCustody({
        ...dependencyCustody, attempts: [...byAttempt.keys()], enteredRawAbsent,
        dependent: {loss: true, submissionId: lookup.requestId},
      });
      const custody = await observeCustody();
      const {terminalRun} = custody;
      assert.equal(custody.definition, lookup.runDefinitionCid);
      assert.equal(terminalRun.controlRevision, lookup.controlRevision);
      assert.equal(custody.observed[0].attempt, producerAttempt);
      assert.equal(custody.receiver.attempt, receiverAttempt);
      const [{task, profile}] = originals;
      const accounting = requireNativeModelAccounting(started.accounting, custody, new Map([[task, joinedUsage[0]]]));
      const raw = requireNativeRawReceipts(started.raw, custody, new Map([[task, {
        profile, ...fixtures.get(selections[0].model),
      }]]));
      const id = await cli('status-id', ['status', custody.runId, '--json']);
      assert.deepEqual(id.events, []);
      assert.deepEqual(JSON.parse(id.stdout), custody.terminalRun.state);
      const {wrapper, opened, foreignOpened} = await referenceStatus(lookup);
      assert.deepEqual(wrapper.state, custody.terminalRun.state);
      assert.equal(wrapper.controlRevision, custody.terminalRun.controlRevision);
      assert(opened > foreignOpened, 'Expected the original Store open only after matching both references');
      assert.deepEqual(await observeCustody(), custody, 'Cold status changed original Run or Model custody');
      const [producer] = custody.observed;
      const readStatus = (phase, options) => cli(phase, ['status', custody.runId, '--json'], options);
      const absentEnteredRaw = await withMissingNativeModelFixtureCell(custodyOptions.storePath, producer.rawHolding,
        async () => {
          const omitted = await observeCustody(true);
          assert.deepEqual(omitted, {...custody, observed: [{...producer, encryptedRawCid: null}]});
          const read = await readStatus('status-no-entered-raw');
          assert.deepEqual(read.events, []);
          assert.deepEqual(JSON.parse(read.stdout), custody.terminalRun.state);
          assert.deepEqual(await observeCustody(true), omitted);
          requireSends(2);
          return {pid: read.pid, status: 'needs_reconciliation'};
        });
      const missingSettled = [];
      for (const role of ['model_invocation_evidence', 'model_raw_response', 'model_capture_bundle']) {
        const original = producer.evidence.find(leaf => leaf.role === role);
        assert(original);
        const read = await withMissingNativeModelFixtureCell(custodyOptions.storePath, original.holding,
          () => readStatus(`status-missing-${role}`, {
            expectedFailure: {code: 'ACTQL_E_COMMAND_FAILED', message: 'LocalOriginalRunStateCustodyUnavailable'},
          }));
        assert.deepEqual(read.events, []);
        requireSends(2);
        missingSettled.push({role, pid: read.pid});
      }
      assert.deepEqual(await observeCustody(), custody, 'Fixture controls changed original Run or Model custody');
      requireSends(2);
      assert.equal(new Set(phases.map(phase => phase.pid)).size, phases.length);
      return {image: modelImage, fixture: 'controlled-loopback-tls-dependent-lost-reply',
        phases, calls, connections, peers: observePeers(), receiverReplyCut, custody, raw, accounting,
        coldReferences: {opened, foreignOpened}, fixtureOmissionControls: {absentEnteredRaw, missingSettled}};
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
      const selected = referenceControl && n === 1 ? await prepareReference() : null;
      if (selected) requireSends(sends);
      const started = await cli(`run-${n}`, ['run', file, '--format', 'json', ...presentation,
        ...(selected?.options ?? []), '--json']);
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
        ...(dependent ? {dependent: {loss: false, receiverRateLimited}} : {}),
      }) : null;
      const custody = observeCustody ? await observeCustody() : null;
      const accounting = custody ? requireNativeModelAccounting(started.accounting, custody,
        new Map(tasks.map((task, index) => [task, receiverRateLimited && index === 1 ? noUsage : joinedUsage[index]]))) : null;
      const raw = custody ? requireNativeRawReceipts(started.raw, custody,
        new Map(originals.map(({task, profile}, index) => [task, {profile, ...fixtures.get(selections[index].model)}]))) : null;
      const delivery = joined ? requireNativeJoinedDelivery({report, runReceipt, outputs,
        rows: scenario.rows, policyCid: cid(joined.finalResultPolicy), custody,
        additionalResults: joined.additionalResults,
        failedModelTask: receiverRateLimited ? tasks[1] : null}) : null;
      if (joined) {
        const dataPath = join(project, 'source-data.json');
        assert.equal(await readFile(dataPath, 'utf8'), canonicalText(joined.payload));
        await unlink(dataPath);
        await unlink(join(project, file));
      }
      if (selected) {
        const lookup = await recoverReference(selected);
        const store = join(project, 'results');
        const excluded = join(project, 'results-reference-control');
        await rename(store, excluded);
        try {
          const {wrapper, opened, foreignOpened} = await referenceStatus(lookup);
          assert.equal(wrapper.state.run_id, state.run_id);
          assert.equal(wrapper.state.status, 'succeeded');
          assert.deepEqual(wrapper.state, state);
          assert.equal(opened, foreignOpened, 'Ordinary reference status opened the unavailable Result Store');
          await assert.rejects(lstat(store), {code: 'ENOENT'});
          requireSends(sends);
        } finally { await rename(excluded, store); }
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
        for (const [name, expected] of Object.entries(joined.additionalResults ?? {})) {
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
    return {image: modelImage, fixture: receiverRateLimited ? 'controlled-loopback-tls-dependent-rate-limit' :
      'controlled-loopback-tls', phases, runs, calls, connections,
    ...(joined ? {protectedChecks} : {}), ...(dependent ? {peers: observePeers()} : {})};
  } finally {
    for (const socket of sockets) socket.destroy();
    await Promise.all([...servers.values()].filter(server => server.listening)
      .map(server => new Promise(resolve => server.close(resolve))));
  }
}

const providerError = {code: 'ACTQL_E_MODEL_PROVIDER_ERROR', message: 'The Model provider returned an HTTP error'};
const noUsage = {input_tokens: null, output_tokens: null};

export function requireNativeTerminalModelAttempt(events, terminal) {
  // A complete 2xx response returns before its nested answer is decoded.
  // The typed rejection is then observed on the same Attempt.
  const expectedTags = terminal.status === 200 ? [0, 1, 2, 3] : [0, 1, 2];
  return requireModelAttempts(events, 1, expectedTags);
}

// Independent authored response bytes. The peer sends these originals once;
// the native Raw receipt must agree with their known bytes and complete EOF.
export const nativeModelTerminalCases = [
  {status: 429, items: 2, body: 'gateway rejected', usage: noUsage, diagnostic: {
    code: 'ACTQL_E_MODEL_RATE_LIMIT', message: 'The Model provider rate-limited the request',
  }},
  {status: 401, items: 1, body: 'gateway rejected', usage: noUsage, diagnostic: providerError},
  {status: 503, items: 1, body: 'gateway rejected', usage: noUsage, diagnostic: providerError},
  {status: 200, items: 1, usage: {input_tokens: 0, output_tokens: null},
    body: '{"id":"r13-schema-invalid","model":"controlled-chat","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"{"},"finish_reason":"stop"}],"usage":{"prompt_tokens":0}}',
    diagnostic: {
      code: 'ACTQL_E_MODEL_SCHEMA_INVALID', message: 'The Model response did not match the output contract',
    }},
];
