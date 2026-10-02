import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import test from 'node:test';
import {inspect} from 'node:util';
import {connect} from '../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';

const oneRowInfer = () => ({version: 'actql/0.1', id: 'installed-infer',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false},
      text: {type: 'string', nullable: true}},
      rows: [{id: 'a', text: 'hello'}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}, as: 'unique'},
    {infer: {contract: 'model-task:risk-score.v1', key: 'id',
      input: {text: {field: 'text'}}}, as: 'captured'},
  ], results: {captured: {from: 'captured',
    fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'captured'}}}});

async function modelConfiguration() {
  const base = JSON.parse(await readFile(new URL(
    '../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const taskSource = await readFile(new URL(
    '../../src/stage_results/infer_program_test.mbt', import.meta.url), 'utf8');
  const task = JSON.parse(taskSource.match(/let body =\n\s+#\|(.+)/u)[1]);
  const {evidence_bundle_cid: ignored, ...body} = base;
  void ignored;
  body.model_task_contracts = [task];
  return {task, installation: {environmentWire: canonicalJson({...body,
    evidence_bundle_cid: contentCid(body)})}};
}

function diagnosticAuthorization(observe) {
  const keys = generateKeyPairSync('ed25519');
  return {observe,
    hostKey: {keyId: 'fixture-host', privateKey: keys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    reviewers: [{keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer',
      principalId: userInfo().username,
      publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}]};
}

function assertNoAcceptedRun(root, physicalStarts) {
  assert.equal(physicalStarts(), 0);
  const journal = new DatabaseSync(join(root, 'state', 'requests',
    'client-requests.sqlite3'), {readOnly: true});
  try {
    assert.equal(journal.prepare('SELECT COUNT(*) AS count FROM client_requests')
      .get().count, 0);
  } finally { journal.close(); }
}

async function installedHost(t, options = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-infer-'));
  const priorCertificates = getCACertificates('default');
  execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
    '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
    '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
  {cwd: root, stdio: 'ignore'});
  let host, server;
  t.after(async () => {
    try {
      if (server !== undefined) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
      await host?.close();
    } finally {
      setDefaultCACertificates(priorCertificates);
      await rm(root, {recursive: true, force: true});
    }
  });
  const certificate = await readFile(join(root, 'host.crt'));
  setDefaultCACertificates([...priorCertificates, certificate.toString()]);
  let physicalStarts = 0;
  try {
    host = await openInstalledRemoteHttpHost({directory: join(root, 'state'),
      authenticate: () => userInfo().username,
      beforeDispatch: () => { physicalStarts++; }, ...options});
  } catch (cause) {
    t.diagnostic(inspect(cause, {depth: 4}));
    throw cause;
  }
  server = createServer({key: await readFile(join(root, 'host.key')),
    cert: certificate}, host.handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const client = await connect({mode: 'remote',
    endpoint: `https://127.0.0.1:${server.address().port}/`,
    token: 'fixture-owner', durability: 'durable'});
  return {client, root, physicalStarts: () => physicalStarts};
}

test('ordinary public INFER refuses a missing installed ModelTask before Run admission',
  async t => {
    const {client, root, physicalStarts} = await installedHost(t);
    await assert.rejects(client.start(oneRowInfer(), {requestId: 'infer-missing'}),
      error => {
        t.diagnostic(`Public preparation refusal: ${error.code}`);
        assert.equal(error.code, 'ClientProgramRejected');
        return true;
      });
    assert.equal(physicalStarts(), 0);
    const journal = new DatabaseSync(join(root, 'state', 'requests',
      'client-requests.sqlite3'), {readOnly: true});
    try {
      assert.equal(journal.prepare('SELECT COUNT(*) AS count FROM client_requests')
        .get().count, 0);
    } finally { journal.close(); }
  });

test('installed ModelTask reaches normal public preparation but cannot bypass missing dispatch admission',
  async t => {
    const {installation} = await modelConfiguration();
    const observations = [];
    const {client, root, physicalStarts} = await installedHost(t,
      {modelInstallation: installation,
        authorization: diagnosticAuthorization((name, detail) => {
          if (name === 'infer_preparation_rejected') observations.push(detail);
        })});
    await assert.rejects(client.start(oneRowInfer(), {requestId: 'infer-installed'}),
      {code: 'ClientProgramUnsupported'});
    assert.equal(observations.length, 1);
    assert.equal(observations[0].boundary, 'model_execution');
    assert.equal(observations[0].code,
      'InstalledInferModelExecutionUnavailable');
    assertNoAcceptedRun(root, physicalStarts);
  });

for (const variant of ['valid', 'wrong-self-cid', 'foreign-task']) {
  test(`public submit admits the exact installed execution before dependencies: ${variant}`,
    async t => {
      const {task, installation} = await modelConfiguration();
      // Independent contract input: neither capacities nor identities come
      // from successful execution. Symbolic dependency references deliberately
      // remain unadmitted and cannot permit physical dispatch.
      const body = {version: 'actql-model-execution-contract/0.1',
        model_task_contract_cid: variant === 'foreign-task' ?
          `sha256:${'f'.repeat(64)}` : task.contract_cid,
        retry_classification_contract_cid: `sha256:${'a'.repeat(64)}`,
        backoff_contract_cid: `sha256:${'a'.repeat(64)}`,
        max_attempts_per_slot: 1, max_total_attempts: 1,
        max_total_cost_units: 0, max_total_duration_ms: 500,
        max_total_wire_bytes: 66536, max_total_token_reservation: 33,
        media_input_contracts: {}, default_publication: 'outcomes'};
      const executionCid = contentCid(body);
      installation.executionContracts = [{modelTaskCid: task.contract_cid,
        cid: executionCid, bodyWire: canonicalJson({...body,
          self_cid: variant === 'wrong-self-cid' ?
            `sha256:${'b'.repeat(64)}` : executionCid})}];
      const observations = [];
      const {client, root, physicalStarts} = await installedHost(t,
        {modelInstallation: installation,
          authorization: diagnosticAuthorization((name, detail) => {
            if (name === 'infer_preparation_rejected') observations.push(detail);
          })});
      await assert.rejects(client.start(oneRowInfer(),
        {requestId: `infer-${variant}`}), {code: 'ClientProgramUnsupported'});
      assert.equal(observations.length, 1);
      const observed = observations[0];
      if (variant === 'valid') {
        assert.equal(observed.boundary, 'model_dependencies');
        assert.equal(observed.code, 'MoonBitHostFailure');
        assert.equal(observed.typedCause, 'missing_body');
      } else {
        assert.equal(observed.boundary, 'model_execution');
        assert.equal(observed.code, 'MoonBitHostFailure');
        assert.notEqual(observed.cause, undefined);
        assert.equal(observed.typedCause, variant === 'wrong-self-cid' ?
          'identity_mismatch' : 'reference_mismatch');
      }
      assertNoAcceptedRun(root, physicalStarts);
    });
}

async function installedDependencyConfiguration(variant) {
  const {task, installation} = await modelConfiguration();
  const prompt = {version: 'actql-model-prompt/0.1',
    payload: variant === 'unsupported-payload' ? null :
      {format: 'fixture-risk/0.1', instructions: 'Classify the text.'}};
  if (variant === 'unknown-field') prompt.extra = true;
  if (variant === 'unknown-version') prompt.version = 'actql-model-prompt/9.9';
  const retry = {version: 'actql-model-retry-policy/0.1',
    retryable_failures: variant === 'nonempty-retry' ? ['timeout'] :
      variant === 'duplicate-retry' ? ['timeout', 'timeout'] :
        variant === 'reordered-retry' ? ['timeout', 'rate_limit'] : []};
  const backoff = {version: 'actql-model-backoff/0.1',
    delays_ms: variant === 'nonempty-backoff' ? [0] :
      variant === 'invalid-number' ? [-1] : []};
  const bodies = [prompt, retry, backoff].map(body => ({
    cid: contentCid(body), bodyWire: canonicalJson({...body,
      self_cid: contentCid(body)})}));
  if (variant === 'substituted-body') {
    bodies[0].bodyWire = bodies[0].bodyWire.replace('Classify', 'Ignore');
  }
  if (variant === 'wrong-self-cid') {
    bodies[0].bodyWire = canonicalJson({...prompt,
      self_cid: `sha256:${'f'.repeat(64)}`});
  }
  const {contract_cid: ignoredTask, ...taskBody} = task;
  void ignoredTask;
  taskBody.prompt_template_cid = bodies[0].cid;
  const taskCid = contentCid(taskBody);
  const {evidence_bundle_cid: ignoredEnvironment, ...environment} =
    JSON.parse(installation.environmentWire);
  void ignoredEnvironment;
  environment.model_task_contracts = [{...taskBody, contract_cid: taskCid}];
  installation.environmentWire = canonicalJson({...environment,
    evidence_bundle_cid: contentCid(environment)});
  const execution = {version: 'actql-model-execution-contract/0.1',
    model_task_contract_cid: taskCid,
    retry_classification_contract_cid: bodies[1].cid,
    backoff_contract_cid: bodies[2].cid,
    max_attempts_per_slot: 1, max_total_attempts: 1,
    max_total_cost_units: 0, max_total_duration_ms: 500,
    max_total_wire_bytes: 66536, max_total_token_reservation: 33,
    media_input_contracts: {}, default_publication: 'outcomes'};
  installation.executionContracts = [{modelTaskCid: taskCid,
    cid: contentCid(execution), bodyWire: canonicalJson({...execution,
      self_cid: contentCid(execution)})}];
  installation.dependencyBodies = bodies;
  return {installation, taskCid};
}

for (const [variant, boundary, typedCause] of [
  ['valid', 'model_dispatch', undefined],
  ['unknown-field', 'model_dependencies', 'invalid_body'],
  ['unknown-version', 'model_dependencies', 'invalid_body'],
  ['invalid-number', 'model_dependencies', 'invalid_body'],
  ['duplicate-retry', 'model_dependencies', 'invalid_body'],
  ['reordered-retry', 'model_dependencies', 'invalid_body'],
  ['wrong-self-cid', 'model_dependencies', 'identity_mismatch'],
  ['substituted-body', 'model_dependencies', 'identity_mismatch'],
  ['nonempty-retry', 'model_dependencies', 'unsupported_policy'],
  ['nonempty-backoff', 'model_dependencies', 'unsupported_policy'],
  ['unsupported-payload', 'model_provider', 'unsupported_prompt'],
]) {
  test(`public INFER checks dependency bodies and selected provider before accepting a Run: ${variant}`,
    async t => {
      const {installation, taskCid} = await installedDependencyConfiguration(variant);
      const observations = [];
      let validations = 0, calls = 0;
      const {client, root, physicalStarts} = await installedHost(t, {
        modelInstallation: installation,
        registerModelProviders: () => [{providerId: 'models/fixture',
          invoke() { calls++; throw new Error('UnexpectedProviderDispatch'); },
          validatePrompt(actualTask, selector, wire) {
            validations++;
            assert.equal(actualTask, taskCid);
            assert.equal(selector, 'fixture-risk-model');
            const payload = JSON.parse(wire);
            return payload !== null &&
              Object.keys(payload).sort().join(',') === 'format,instructions' &&
              payload.format === 'fixture-risk/0.1' &&
              payload.instructions === 'Classify the text.';
          }}],
        authorization: diagnosticAuthorization((name, detail) => {
          if (name === 'infer_preparation_rejected') observations.push(detail);
        }),
      });
      await assert.rejects(client.start(oneRowInfer(),
        {requestId: `dependencies-${variant}`}), {code: 'ClientProgramUnsupported'});
      assert.equal(observations.length, 1);
      assert.equal(observations[0].boundary, boundary);
      assert.equal(observations[0].typedCause, typedCause);
      if (variant === 'valid') {
        assert.equal(observations[0].code, 'InstalledInferDispatchNotConnected');
      }
      assert.equal(validations, ['valid', 'unsupported-payload'].includes(variant) ? 1 : 0);
      assert.equal(calls, 0);
      assertNoAcceptedRun(root, physicalStarts);
    });
}
