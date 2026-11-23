import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {execFile, execFileSync, spawn} from 'node:child_process';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {dirname, join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {promisify} from 'node:util';

const [source, packaged] = process.argv.slice(2);
assert(source && source === resolve(source) && packaged && packaged === resolve(packaged),
  'Supply the exact-source checkout and its private Linux package directory');
assert.equal(process.platform, 'linux');
assert.equal(process.arch, 'x64');
const root = await mkdtemp(join(packaged, 'qualification-installed-'));
console.log(root);
const sha = 'a4d67fbb9fe0072c543e355083efd123015b4c2e';
assert.equal(execFileSync('/usr/bin/git', ['rev-parse', 'HEAD'], {cwd: source, encoding: 'utf8'}).trim(), sha);
const platform = 'linux-x64-gnu';
const glibc = process.report.getReport().header.glibcVersionRuntime;
const version = '0.0.2';
const producer = join(packaged, 'production/artifact');
const dependency = path => import(pathToFileURL(join(source, path)));
const {verifyNativeCliRelease} = await dependency('scripts/native-cli-release.mjs');
const {openReleaseTestRegistry} = await dependency('scripts/release-test-registry.mjs');
const {prepareNativeNumericOperator} = await dependency('scripts/test-native-cli-source-free-install.mjs');
const {admitInstalledLocalRuntime, installedLocalRuntimeEnvironment} = await dependency('packages/native-cli/lib/local-runtime.mjs');
const {canonicalText} = await dependency('scripts/check-canonical-json.mjs');
const {providerBindingOriginals} = await dependency('scripts/fixtures/model-provider-binding-fixture.mjs');
const {nativeLauncherEnvelope} = await dependency('scripts/native-cli-mock-scenario.mjs');
const {nativeMockAcceptanceObservations} = await dependency('packages/native-cli/lib/project-scaffold.mjs');

const {verifiedNativeRemoteHttpPackage, verifiedNativeModelHttpPackage} =
  await dependency('scripts/native-preparation-originals.mjs');

const digest = wire => createHash('sha256').update(wire).digest('hex');
const cid = body => 'sha256:' + digest(canonicalText(body));
const seal = body => ({...body, self_cid: cid(body)});
const json = async path => JSON.parse(await readFile(path, 'utf8'));
const write = async (path, body, flag = 'wx') =>
  writeFile(path, canonicalText(body), {mode: 0o600, flag});
const cohortDir = join(packaged, 'release');
const record = await json(join(producer, 'artifact.json'));
assert.equal(record.sourceSha, sha);
assert.equal(record.platform, platform);
assert.equal(record.packageVersion, version);
const manifest = await verifyNativeCliRelease(cohortDir);
assert.equal(manifest.sourceSha, sha);
const registry = await openReleaseTestRegistry([{directory: cohortDir, manifest}]);
let server;
const calls = [];
const phases = [];
const connections = {tcp: 0, tls: 0};
const transferBodies = [];
const verifiedRoles = [];
const faultOriginals = [];
const recordFile = join(root, 'controlled-native.json');
async function save() {
  await writeFile(recordFile, JSON.stringify({source: sha, platform, glibc, phases, calls, connections, transferBodies, verifiedRoles, faultOriginals}, null, 2) + '\n',
    {mode: 0o600});
}
try {
  const dirs = Object.fromEntries(['prefix', 'home', 'tmp', 'empty-path', 'tls']
    .map(name => [name, join(root, name)]));
  for (const path of Object.values(dirs)) await mkdir(path, {mode: 0o700});
  const npmrc = join(root, 'npmrc');
  const globalrc = join(root, 'npmrc-global');
  await writeFile(npmrc, `registry=${registry.url}\n@actql:registry=${registry.url}\n`);
  await writeFile(globalrc, '');
  const npmRoot = dirname(dirname(process.execPath));
  const npm = join(npmRoot, 'lib/node_modules/npm/bin/npm-cli.js');
  const baseEnv = {PATH: join(npmRoot, 'bin') + ':/usr/bin:/bin', HOME: dirs.home, TMPDIR: dirs.tmp,
    npm_config_registry: registry.url, npm_config_userconfig: npmrc,
    npm_config_globalconfig: globalrc, npm_config_cache: join(root, 'cache'),
    npm_config_ignore_scripts: 'true', npm_config_update_notifier: 'false',
    NO_PROXY: '127.0.0.1,localhost'};
  await promisify(execFile)(process.execPath, [npm, 'install', '-g', '--prefix', dirs.prefix,
    '--ignore-scripts', '--no-audit', '--no-fund', `actql@${version}`],
    {cwd: root, env: baseEnv, timeout: 120000});
  const installed = join(dirs.prefix, 'lib/node_modules/actql/node_modules/@actql', 'cli-' + platform);
  assert.deepEqual(await json(join(installed, 'artifact.json')), record);
  const original = join(installed, 'bin/actql-native-client');
  assert.equal(digest(await readFile(original)), record.binarySha256);
  const expected = {sourceSha: sha, platform, localRuntimeSha256: record.localRuntime.sha256};
  const localRuntime = admitInstalledLocalRuntime({root: installed, expected, metadata: record.localRuntime});

  for (const [role, name, verify] of [
    ['remote-http','libcurl.so.4',verifiedNativeRemoteHttpPackage],
    ['model-http','libcurl-model.so.4',verifiedNativeModelHttpPackage],
  ]) {
    const preparationPath = join(packaged, role, 'preparation.json');
    const preparationWire = await readFile(preparationPath);
    const preparation = JSON.parse(preparationWire);
    assert.equal(preparation.source, sha);
    const selected = verify({path: preparationPath, source: sha,
      bytes: preparationWire.length, sha256: digest(preparationWire)},
      {source: sha, target: 'linux-x64'});
    const matches = localRuntime.libraries.filter(item => item.role === role);
    assert.equal(matches.length, 1);
    const path = join(installed, matches[0].path);
    assert.equal(path.split('/').at(-1), name);
    assert.equal(matches[0].sha256, selected.library.sha256);
    const installedBytes = await readFile(path);
    assert.equal(installedBytes.length, selected.library.bytes);
    assert.equal(digest(installedBytes), selected.library.sha256);
    const dynamic = execFileSync('/usr/bin/readelf', ['-d', path], {encoding: 'utf8'});
    const matchesOf = field => dynamic.split('\n').filter(line => line.includes('(' + field + ')'))
      .map(line => {
        const value = /\[([^\]]+)\]/u.exec(line);
        assert(value, 'Expected one ELF dynamic value');
        return value[1];
      });
    const identity = matchesOf('SONAME');
    assert.deepEqual(identity, [name]);
    const loadedDependencies = matchesOf('NEEDED');
    assert.deepEqual(loadedDependencies.sort(), [...selected.dependencies].sort());
    verifiedRoles.push({role, path:matches[0].path, bytes:installedBytes.length, sha256:digest(installedBytes),
      preparationSha256:digest(preparationWire), identity:identity[0], dependencies:[...selected.dependencies].sort()});
  }
  assert.equal(new Set(verifiedRoles.map(role=>role.path)).size, 2);
  assert.equal(new Set(verifiedRoles.map(role=>role.sha256)).size, 2);
  await save();
  const env = installedLocalRuntimeEnvironment({root: installed, expected, metadata: record.localRuntime,
    platformFacts: {glibc},
    environment: {HOME: dirs.home, TMPDIR: dirs.tmp, PATH: dirs['empty-path'],
      ACTQL_NATIVE_TIMINGS: '1', ACTQL_NATIVE_ACCEPTANCE_OBSERVATIONS: '1'}});
  const openssl = '/usr/bin/openssl';
  execFileSync(openssl, ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-days', '2', '-subj', '/CN=ActQL Controlled Model', '-addext',
    'subjectAltName=IP:127.0.0.1', '-keyout', 'key.pem', '-out', 'cert.pem'],
    {cwd: dirs.tls, stdio: 'ignore', timeout: 30000});
  const certPath = join(dirs.tls, 'cert.pem');
  const token = 'synthetic-controlled-model-' + randomUUID();
  const answer = n => ({level: n === 1 ? 'low' : 'high', reason: `controlled reply ${n}`});
  server = createServer({cert: await readFile(certPath), key: await readFile(join(dirs.tls, 'key.pem'))},
    async (request, response) => {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const n = calls.length + 1;
      const uploaded = Buffer.concat(chunks);
      const received = JSON.parse(uploaded.toString('utf8'));
      const authorized = request.headers.authorization === 'Bearer ' + token;
      calls.push({method: request.method, path: request.url, authorized,
        model: received.model, notesMatch: JSON.stringify(received.messages).includes(`original input ${n}`)});
      const body = JSON.stringify({id: `controlled-${n}`, model: received.model, object: 'chat.completion',
        choices: [{index: 0, message: {role: 'assistant', content: JSON.stringify(answer(n))},
          finish_reason: 'stop'}],
        usage: {prompt_tokens: n === 1 ? 0 : 15, completion_tokens: 8}});
      if (n === 5) {
        // Preserve the TLS connection after accepting the one request. The
        // installed client's deadline must stop it before any response.
        transferBodies.push({upload: uploaded.length, download: 0, timeout: true, receivedAt: Date.now()});
        return;
      }
      response.writeHead(authorized ? 200 : 401, {'content-type': 'application/json',
        'content-length': Buffer.byteLength(body), connection: 'close'});
      const lost = n === 4;
      const sent = lost ? body.slice(0, 20) : body;
      transferBodies.push({upload: uploaded.length, download: Buffer.byteLength(sent), lost});
      if (lost) {
        response.write(sent, () => response.destroy());
      } else {
        response.end(sent);
      }
    });
  server.on('connection', () => { connections.tcp++; });
  server.on('secureConnection', () => { connections.tls++; });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen({host: '127.0.0.1', port: 0}, resolve);
  });
  const endpoint = `https://127.0.0.1:${server.address().port}/v1/chat/completions`;
  const project = join(root, 'project');
  const assets = Object.fromEntries(await Promise.all(localRuntime.assets.map(async item =>
    [item.role, await readFile(join(installed, item.path), 'utf8')])));
  const libraries = Object.fromEntries(localRuntime.libraries.map(item => [item.role, join(installed, item.path)]));
  const selected = await prepareNativeNumericOperator({
    project, assets, libraries, runtimeWire: await readFile(join(installed, 'local-runtime.json'), 'utf8'),
    maxRows: 16, includeSqlResult: true,
  });
  const fixture = await json(join(source, 'scripts/fixtures/public-model-task-signed64.json'));
  const task = structuredClone(fixture.task);
  const model = 'controlled-chat';
  const provider = 'models/http';
  Object.assign(task, {connector_id: provider, authored_model_selector: model, max_items: 1,
    generation_config: {...task.generation_config, max_output_tokens: 100}});
  delete task.contract_cid;
  task.contract_cid = cid(task);
  const envPath = join(project, 'environment.json');
  const checkEnvironment = await json(envPath);
  checkEnvironment.model_task_contracts = [task];
  Object.assign(checkEnvironment.host_policy_profile.capacity, {
    max_model_request_bytes_per_item: 32768, max_model_input_tokens_per_item: 256,
    max_model_total_duration_ms: 6000,
  });
  delete checkEnvironment.evidence_bundle_cid;
  checkEnvironment.evidence_bundle_cid = cid(checkEnvironment);
  await write(envPath, checkEnvironment, 'w');

  const vendor = providerBindingOriginals(provider, {selector: model, endpoint});
  await writeFile(join(project, 'model-revision.json'), vendor.installationRevision.wire, {mode: 0o600, flag:'wx'});
  await writeFile(join(project, 'model-contract.json'), vendor.configurationContract.wire, {mode: 0o600, flag:'wx'});
  const responseFixture = await json(join(source, 'portability/corpus/model-response-profiles.json'));
  const responseProfile = structuredClone(responseFixture.cases[0].body);
  const artifactIdentity = 'sha256:' + record.localRuntime.sha256;
  Object.assign(responseProfile.adapter, {builder_id: 'actql/native-portable-chat',
    codec_id:'actql/openai-chat-envelope', build_artifact_cid: artifactIdentity});
  Object.assign(responseProfile.completion, {validator_id:'actql/openai-chat-envelope',
    validator_artifact_cid: artifactIdentity});
  responseProfile.operation.endpoint = endpoint;
  Object.assign(responseProfile.task, {contract_cid: task.contract_cid,
    input_schema_cid: task.input_schema_cid, output_schema_cid: task.output_schema_cid});
  Object.assign(responseProfile.limits, {request_bytes: 32768, response_bytes: 65536,
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
  const retention = await json(join(project, 'retention.json'));
  const files = {
    'model-credential.json': {version:'actql-config/0.1', native:{preparation_credential:{
      credential_file:'model.key', provider_file:'model-provider.json'}}},
    'model-profile.json': profile,
    'model-provider.json': {...JSON.parse(vendor.configuration.wire),
      installation_revision_cid: vendor.installationRevision.cid,
      configuration_contract_cid: vendor.configurationContract.cid,
      response_profile_cid: profile.self_cid, model_id:model, credential_ref:'file:model.key',
      adapter_kind:'portable-http', api_mode:'chat-completions', model_defaults: defaults},
    'model-execution.json': {contract_cid:execution.self_cid, contract:canonicalText(execution),
      prompt:canonicalText(fixture.prompt), retry_policy:canonicalText(retry), backoff:canonicalText(backoff)},
    'model-policy.json': {ca_path: certPath, connect_timeout_ms: 1500, operation_timeout_ms: 4000,
      credential_expires_at_ms: Date.now() + 172800000, max_projection_frames: 1000,
      attempt_tokens:1024, attempt_cost_units:0, input_classification:'internal',
      provider_region:'explicit-fixture-region', provider_retention:false, provider_training_use:false,
      retention_contract_file:'model-retention.json', metadata_retention_file:'model-metadata.json',
      clock_contract_file:'model-clock.json', data_policy_file:'model-data.json',
      available_until:'2099-01-01T00:00:00.000Z', delete_by:'2099-01-02T00:00:00.000Z',
      extension_ceiling_at:'2099-01-02T00:00:00.000Z', metadata_delete_by:'2099-01-03T00:00:00.000Z'},
  };
  for (const [name, body] of Object.entries(files)) await write(join(project, name), body);
  for (const [index, name] of ['model-retention.json','model-metadata.json','model-clock.json'].entries())
    await writeFile(join(project, name), retention[index].wire, {mode:0o600, flag:'wx'});
  await writeFile(join(project, 'model-data.json'), assets['result-policy'], {mode:0o600, flag:'wx'});
  await writeFile(join(project, 'model.key'), token, {mode:0o600, flag:'wx'});
  const configPath = join(project, 'operator.json');
  const config = await json(configPath);
  config.native.check_environment.evidence_bundle_cid = checkEnvironment.evidence_bundle_cid;
  config.native.local.installation_files.push(...Object.keys(files), 'model-revision.json',
    'model-contract.json','model-retention.json','model-metadata.json','model-clock.json','model-data.json');
  config.native.local.model_http_installation = {provider_id:provider, credential_installation:'model-credential.json',
    installation_revision:'model-revision.json', configuration_contract:'model-contract.json',
    response_profile:'model-profile.json', response_profile_cid:profile.self_cid, execution_file:'model-execution.json',
    run_policy_file:'model-policy.json'};
  await write(configPath, config, 'w');
  const accountPath = join(project, 'account.json');
  const account = await json(accountPath);
  account.entries.push({entry_id:'bounded-native-model', outcome:'allow', principal:{any_of:[account.account_id]},
    connection:{any_of:[provider]}, resource:{any_of:[task.contract_cid]},
    operation:{any_of:['infer', 'model_raw_capture']}, exclusions:[]});
  account.entries.sort((a, b) => Buffer.compare(Buffer.from(a.entry_id), Buffer.from(b.entry_id)));
  await write(accountPath, account, 'w');

  const program = n => ({version:'actql/0.1', id:'native-direct-model-qualification', stages:[n].map(n =>
    ({id:`model${n}`, inputs:{}, steps:[
      {values:{schema:{id:{type:'string',nullable:false},notes:{type:'string',nullable:false},
        active_users:{type:'int64',nullable:false},trend:{type:'string',nullable:false}},
        rows:[{id:`row${n}`, notes:`original input ${n}`,active_users:String(n),trend:'stable'}]},as:'seed'},
      {assert_rows:{unique_by:['id']}},
      {infer:{contract:task.task_id,key:'id',input:{notes:{field:'notes'},active_users:{field:'active_users'},
        trend:{field:'trend'}}},as:'inferred'}],
      results:{rows:{from:'inferred',fields:['id','outcome','value']}}})),
    results:{answer:{from:{stage:`model${n}`,result:'rows'}}}});
  for (const n of [1, 2, 3, 4, 5]) await write(join(project, `infer-${n}.json`), program(n));

  async function cli(phase, args, {expected = 0} = {}) {
    const startedAt = Date.now();
    const child = spawn(original, [...selected.configuration, ...args], {cwd:project, env});
    const stdout = [], stderr = [];
    child.stdout.on('data', chunk => stdout.push(chunk));
    child.stderr.on('data', chunk => stderr.push(chunk));
    const timer = setTimeout(() => child.kill('SIGKILL'), 90000);
    let code, signal;
    try {
      [code, signal] = await new Promise((resolve,reject) => {
        child.once('error',reject);
        child.once('close',(...values) => resolve(values));
      });
    } finally {clearTimeout(timer);}
    const result = {phase,pid:child.pid,code,signal,startedAt,endedAt:Date.now(),
      stdout:Buffer.concat(stdout).toString('utf8'), stderr:Buffer.concat(stderr).toString('utf8'),
      physicalRequests:calls.length, connections: {...connections}};
    phases.push(result);
    await save();
    assert.equal(signal,null);
    if (expected !== undefined && expected !== null) assert.equal(code,expected,`${phase} exited ${code}`);
    const {native} = nativeLauncherEnvelope(result.stderr, 'optional');
    const telemetry = [];
    const diagnostics = [];
    for (const row of native.trimEnd().split('\n')) {
      if (row.startsWith('ACTQL_NATIVE_')) {
        telemetry.push(row);
      } else {
        assert.notEqual(code, 0);
        assert(row.length <= 4096, 'Oversized Native command diagnostic');
        if (/^actql-native-client: [A-Za-z]/u.test(row)) {
          diagnostics.push({kind:'primary',message:row});
        } else {
          const detail = JSON.parse(row);
          assert.deepEqual(Object.keys(detail).sort(), ['code','message']);
          assert.match(detail.code,/^ACTQL_E_[A-Z_]+$/u);
          assert.equal(typeof detail.message,'string');
          diagnostics.push({kind:'coded',...detail});
        }
      }
    }
    const groups = nativeMockAcceptanceObservations(telemetry.join('\n') + '\n');
    result.diagnostics = diagnostics;
    assert.equal(groups.length,1);
    assert.equal(groups[0].pid,result.pid);
    result.events = groups[0].events;
    const close = result.stderr.split('\n').filter(line => line.startsWith('ACTQL_NATIVE_PHASE '))
      .map(line => JSON.parse(line.slice('ACTQL_NATIVE_PHASE '.length))).find(row => row.tag === 5);
    result.closeScopeReturned = close?.begins === 1 && close?.ends === 1 &&
      close.active === 0 && close.unmatched_end === 0;
    result.diagnosticCode = diagnostics.find(detail => detail.kind === 'coded')?.code ?? null;
    result.cleanupPending = diagnostics.some(detail => detail.code === 'ACTQL_E_CLEANUP_PENDING');
    const correlatedRecovery = diagnostics.length === 1 && diagnostics[0].kind === 'primary' &&
      /^actql-native-client: LocalOriginalValuesWorkUnavailable originalSubmissionRequestId=sha256:[0-9a-f]{64} originalOperationAttemptId=cli-[0-9a-f]{64} \(reconcile with lookup-request; do not resend this operation\)$/u
        .test(diagnostics[0].message);
    result.commandCloseCompleted = result.closeScopeReturned && !result.cleanupPending &&
      (code === 0 || code === 1 &&
        (result.diagnosticCode === 'ACTQL_E_COMMAND_FAILED' || correlatedRecovery));
    await save();
    if (expected === 0) assert.equal(result.commandCloseCompleted, true);
    return result;
  }

  assert.equal(JSON.parse((await cli('adopt',['adopt','--initialize-signing','--json'])).stdout).kind,
    'local_host_adopted');
  await cli('check', ['check', 'infer-1.json', '--format', 'json', '--json']);
  assert.equal(calls.length, 0);
  assert.deepEqual(connections, {tcp: 0, tls: 0});
  const runIds = [];
  const callIds = [];
  for (const n of [1, 2, 3]) {
    const launched = await cli(`run-${n}`, ['run', `infer-${n}.json`, '--format', 'json', '--json']);
    const state = JSON.parse(launched.stdout);
    assert.equal(state.status, 'succeeded');
    assert.equal(typeof state.run_id, 'string');
    runIds.push(state.run_id);
    assert.deepEqual(launched.events.map(event => event.tag), [0, 1, 2]);
    const identity = launched.events[1].identity;
    callIds.push(identity);
    assert(launched.events.every(event => event.identity === identity && event.ordinal === 0));
    assert.equal(calls.length, n);
    assert.deepEqual(calls[n-1], {
      method:'POST', path:'/v1/chat/completions', authorized:true, model, notesMatch:true,
    });
    assert.deepEqual(connections, {tcp: n, tls: n});
    const saved = await cli(`saved-${n}`, ['result', state.run_id, '--result', 'answer', '--format', 'jsonl']);
    assert.notEqual(saved.pid, launched.pid);
    assert.equal(saved.events.length, 0);
    assert.deepEqual(saved.stdout.trim().split('\n').map(line => JSON.parse(line)),
      [{id:`row${n}`, outcome:'ok', value:answer(n)}]);
    assert.equal(calls.length, n);
    assert.deepEqual(connections, {tcp: n, tls: n});
  }
  assert.equal(new Set(runIds).size, 3);
  assert.equal(new Set(callIds).size, 3);
  await save();

  const failures = [];
  for (const [fault, n] of [['response-loss', 4], ['response-timeout', 5]]) {
    const failed = await cli(fault, ['run', `infer-${n}.json`, '--format', 'json', '--json'], {expected:null});
    assert.equal(calls.length, n);
    assert.deepEqual(calls[n-1], {
      method:'POST', path:'/v1/chat/completions', authorized:true, model, notesMatch:true,
    });
    assert.deepEqual(connections, {tcp: n, tls: n});
    assert.deepEqual(failed.events.map(event => event.tag), [0,1]);
    assert(failed.events.every(event => event.identity === failed.events[0].identity && event.ordinal === 0));
    const firstState = failed.stdout.trim() ? JSON.parse(failed.stdout) : null;
    const firstStatus = firstState?.state?.status ?? firstState?.status ?? null;
    assert.notEqual(firstStatus, 'succeeded');
    assert.notEqual(failed.signal,'SIGKILL');
    if (n === 5) {
      assert.equal(transferBodies[n-1].timeout,true);
      assert.equal(transferBodies[n-1].download,0);
      const wait = failed.endedAt - transferBodies[n-1].receivedAt;
      assert(wait >= 3000 && wait < 15000, 'No response was supplied during the original transport deadline');
    }
    const identifier = /originalSubmissionRequestId=(sha256:[0-9a-f]{64}) originalOperationAttemptId=(cli-[0-9a-f]{64})/u.exec(failed.stderr);
    assert(identifier, 'The refused execution retains its original request and attempt');
    const [, requestId, attemptId] = identifier;
    const lookupResult = await cli(fault+'-lookup',['lookup-request','--request-id',requestId]);
    const lookup = JSON.parse(lookupResult.stdout);
    assert.equal(lookup.requestId,requestId);
    assert.equal(lookup.history,'retained');
    assert.equal(lookup.phase,'ready');
    assert.equal(lookup.ref.runDefinitionCid,lookup.runDefinitionCid);
    assert.notEqual(lookupResult.pid,failed.pid);
    const reference = [`--ref-file`, fault+'-ref.json', `--submission-ref-file`, fault+'-submission.json'];
    await write(join(project,fault+'-ref.json'),lookup.ref);
    await write(join(project,fault+'-submission.json'),lookup.submissionRef);

    const inspectJournal = () => JSON.parse(execFileSync('/usr/bin/python3', [
      new URL('./unknown-state-journal.py', import.meta.url).pathname,join(project,'host/client.sqlite3'),lookup.runDefinitionCid,requestId,
    ],{encoding:'utf8',timeout:15000}));
    const facts = inspectJournal();
    assert.deepEqual({entries:facts.entries,attempts:facts.attempts,settlements:facts.settlements},
      {entries:1,attempts:[1],settlements:0});
    const statusRef = await cli(fault+'-status-ref',['status',...reference,'--json'],{expected:null});
    const statusId = await cli(fault+'-status-id',['status','--run-id',facts.runId,'--json'],{expected:null});
    const foreignDefinition = 'sha256:' + 'f'.repeat(64);
    assert.notEqual(foreignDefinition,lookup.runDefinitionCid);
    const foreignRef = fault+'-foreign-ref.json';
    await write(join(project,foreignRef),{...lookup.ref,runDefinitionCid:foreignDefinition});
    const foreignStatus = await cli(fault+'-status-foreign',[
      'status','--ref-file',foreignRef,'--submission-ref-file',fault+'-submission.json','--json',
    ],{expected:null});
    function observeStatus(phase) {
      const payload = phase.stdout.trim() ? JSON.parse(phase.stdout) : null;
      return {exit:phase.code,pid:phase.pid,firstClose:phase.commandCloseCompleted,
        state:payload?.state??null,ref:payload?.ref??null,submissionRef:payload?.submissionRef??null,
        controlRevision:payload?.controlRevision??null};
    }
    const refStatus = observeStatus(statusRef);
    const idStatus = observeStatus(statusId);
    assert.deepEqual(inspectJournal(),facts,'status must not rewrite the saved observation');
    assert.equal(statusRef.events.length,0);
    assert.equal(statusId.events.length,0);
    const observed = {fault,requestId,attemptId,definition:lookup.runDefinitionCid,facts,
      firstStatus,firstExit:failed.code,firstClose:failed.commandCloseCompleted,cleanupPending:failed.cleanupPending,
      refStatus,idStatus,foreignStatus:{exit:foreignStatus.code,
        firstClose:foreignStatus.commandCloseCompleted,diagnostics:foreignStatus.diagnostics}};
    faultOriginals.push(observed);
    await save();
    try {
      assert.equal(failed.code,1);
      assert.equal(foreignStatus.code,1);
      assert.equal(foreignStatus.stdout.trim(),'');
      assert.equal(foreignStatus.events.length,0);
      assert.equal(foreignStatus.commandCloseCompleted,true);
      assert(foreignStatus.diagnostics.some(value=>value.message.includes('LocalOriginalRunReferenceMismatch')));
      assert.equal(facts.savedStatus,'needs_reconciliation');
      assert.equal(facts.observationRevision,0);
      for (const observedStatus of [refStatus,idStatus]) {
        assert.equal(observedStatus.exit,0);
        assert.equal(observedStatus.firstClose,true);
        assert.equal(observedStatus.state?.status,'needs_reconciliation');
        assert.equal(observedStatus.state.run_id,facts.runId);
        assert.equal(observedStatus.state.revision,facts.observationRevision);
        assert.equal(observedStatus.state.result_available,false);
        assert.deepEqual(observedStatus.ref,lookup.ref);
        assert.deepEqual(observedStatus.submissionRef,lookup.submissionRef);
        assert.equal(observedStatus.controlRevision,lookup.controlRevision);
        assert.equal(observedStatus.state.next_action?.kind,'reconcile_run');
      }
      assert.deepEqual(idStatus.state,refStatus.state);
      assert.equal(failed.commandCloseCompleted,true);
    } catch (error) {
      failures.push(new Error(fault,{cause:error}));
    }
    assert.equal(calls.length, n);
    assert.deepEqual(connections, {tcp: n, tls: n});
    await save();
  }
  assert.equal(new Set(phases.map(phase => phase.pid)).size, phases.length);
  await save();
  if (failures.length) throw new AggregateError(failures,'Native HTTP fault acceptance');
} finally {
  await registry.close();
  if (server !== undefined) await new Promise(resolve => server.close(resolve));
}
