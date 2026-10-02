// Deterministic test installation of the existing common ModelTask owner.
// Canonical bodies below are fixture inputs, not expected runtime outputs.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';

// All authored configuration text here is ASCII. The common validators admit
// each body and its references; this helper supplies no execution evidence.
const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => `sha256:${createHash('sha256')
  .update(canonical(value)).digest('hex')}`;
const checked = result => {
  if (result?.$tag === 1) return result._0;
  throw new Error('FixtureModelPreflightRejected', {cause: result});
};

export async function openInferTestHost({mode, fixture}) {
  const directory = resolve(`infer-${mode}-state`);
  await mkdir(directory, {recursive: true});
  const dependencies = [
    {version: 'actql-model-prompt/0.1', payload: {
      format: 'fixture-risk/0.1', instructions: 'Classify the text.'}},
    {version: 'actql-model-retry-policy/0.1', retryable_failures: []},
    {version: 'actql-model-backoff/0.1', delays_ms: []},
  ].map(body => ({cid: cid(body),
    bodyWire: canonical({...body, self_cid: cid(body)})}));
  const {contract_cid: ignoredTask, ...task} = fixture.model_task;
  void ignoredTask;
  task.prompt_template_cid = dependencies[0].cid;
  const taskCid = cid(task);
  const {evidence_bundle_cid: ignoredEnvironment, ...environment} =
    JSON.parse(await readFile('base-environment.json', 'utf8'));
  void ignoredEnvironment;
  environment.model_task_contracts = [{...task, contract_cid: taskCid}];
  const execution = {version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: taskCid,
    retry_classification_contract_cid: dependencies[1].cid,
    backoff_contract_cid: dependencies[2].cid,
    max_attempts_per_slot: 1, max_total_attempts: 1,
    max_total_cost_units: 0, max_total_duration_ms: 500,
    max_total_wire_bytes: 66536, max_total_token_reservation: 33,
    media_input_contracts: {}, default_publication: 'outcomes'};
  const modelInstallation = {
    environmentWire: canonical({...environment,
      evidence_bundle_cid: cid(environment)}),
    executionContracts: [{modelTaskCid: taskCid, cid: cid(execution),
      bodyWire: canonical({...execution, self_cid: cid(execution)})}],
    dependencyBodies: dependencies,
  };
  const keys = generateKeyPairSync('ed25519');
  const observations = [];
  const authorization = {
    observe: (name, detail) => observations.push({name, detail}),
    hostKey: {keyId: 'fixture-host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    reviewers: [{keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    accountConfiguration: canonical({
      version: 'actql-execution-account-config/0.1', account_id: 'infer-owner',
      entries: [{entry_id: 'installed-allow', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {all: true}, exclusions: []}]}),
  };
  let calls = 0;
  const registerModelProviders = moon => [{providerId: 'models/fixture',
    invoke() { throw new Error('UnpreparedProviderCall'); },
    validatePrompt(actualTask, selector, wire) {
      return actualTask === taskCid && selector === 'fixture-risk-model' &&
        JSON.parse(wire).format === 'fixture-risk/0.1';
    },
    quantityCapacity: {
      limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
      perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
    observeEgress: () => ({_0: 'public', _1: 'fixture-region',
      _2: false, _3: false}),
    physicalPreflight: request => moon.clientProgramModelRequestPreflight(
      () => ({_0: true, _1: checked(moon.clientProgramModelPhysicalRequestPlan(
        request, 1000n, 33n, 0n, 500n, () => {
          calls++;
          assert.equal(moon.clientProgramModelRequestInput(request, 'text'),
            '"hello"');
          return moon.clientProgramModelResponse(request,
            '{"reason":null,"risk":"high"}', 'fixture-risk-model',
            'packed-request', 1n, 2n, new Date().toISOString());
        }))}), () => true),
  }];
  const observe = () => {
    const journal = new DatabaseSync(resolve(directory, 'requests',
      'client-requests.sqlite3'), {readOnly: true});
    try {
      return {acceptedRuns: journal.prepare(
        'SELECT COUNT(*) AS count FROM client_requests').get().count,
      modelDispatches: calls};
    } finally { journal.close(); }
  };
  const assertCapture = async run => {
    const storeCid = `sha256:${createHash('sha256').update(JSON.stringify({
      version: 'actql-local-store-owner/0.1', root: directory,
      principalId: userInfo().username})).digest('hex')}`;
    const identity = cid({role: 'model_slot_capture', slot: 0,
      run_definition_cid: run.ref.runDefinitionCid,
      store_authority_cid: storeCid,
      version: 'actql-model-private-holding/0.1'});
    const record = JSON.parse(await readFile(resolve(directory, 'publication',
      'physical-holdings', `${identity.slice(7)}.json`), 'utf8'));
    assert.equal(record.holding_cid, identity);
    assert.equal(record.namespace, 'publication-private');
    assert.equal(record.objects.length, 1);
  };
  if (mode === 'local') {
    return {options: {mode, owner: 'local', durability: 'durable',
      installation: {directory, modelInstallation, registerModelProviders,
        authorization}}, observe, observations, assertCapture,
    async close() {}};
  }
  const host = await openInstalledRemoteHttpHost({directory,
    authenticate: () => userInfo().username,
    modelInstallation, registerModelProviders, authorization});
  const server = createServer({key: await readFile('remote.key'),
    cert: await readFile('remote.crt')}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return {options: {mode, endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'fixture-owner', durability: 'durable'}, observe, observations,
  assertCapture, async close() {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    await host.close();
  }};
}
