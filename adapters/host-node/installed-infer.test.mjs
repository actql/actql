import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
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
import {checked} from '../host-common/runtime-result.mjs';
import {openLocalPublicationStore} from '../store-local/publication-store.mjs';
import {createPublicationContractControlFixture} from
  '../host-common/publication-contract-control.fixture.mjs';
import {loadPrivateEvidenceKey} from './local-continuation-evidence.mjs';

const oneRowInfer = (objectProjection = false) => {
  const program = {version: 'actql/0.1', id: 'installed-infer',
  stages: [{id: 'main', inputs: {}, steps: [
    {values: {schema: {id: {type: 'string', nullable: false},
      text: {type: 'string', nullable: true}},
      rows: [{id: 'a', text: 'hello'}]}, as: 'input'},
    {assert_rows: {unique_by: ['id']}, as: 'unique'},
    {infer: {contract: 'model-task:risk-score.v1', key: 'id',
      input: {text: {field: 'text'}}}, as: 'captured'},
  ], results: {captured: {from: 'captured',
    fields: ['id', 'outcome', 'value']}}}],
  results: {answer: {from: {stage: 'main', result: 'captured'}}}};
  if (objectProjection) {
    program.stages[0].steps.push(
      {derive: {assessment: {object: {
        input_key: {object: {id: {field: 'id'}}},
        outcome: {field: 'outcome'}, value: {field: 'value'},
      }}}},
      {select: ['assessment'], as: 'wrapped'},
    );
    program.stages[0].results.captured = {from: 'wrapped', fields: ['assessment']};
  }
  return program;
};

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
  const {initializeRoot, ...hostOptions} = options;
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
    await initializeRoot?.(join(root, 'state'));
    host = await openInstalledRemoteHttpHost({directory: join(root, 'state'),
      authenticate: () => userInfo().username,
      beforeDispatch: () => { physicalStarts++; }, ...hostOptions});
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
  return {client, root, physicalStarts: () => physicalStarts,
    async closeHost() {
      await host?.close();
      host = undefined;
    }};
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
  if (variant === 'unknown-version') prompt.version = 'actql-model-prompt/invalid';
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

for (const boundary of ['success', 'object-projection', 'private-write-failure',
  'usage-overflow', 'usage-overflow-write-failure', 'cancel-after-dispatch',
  'observation-step-failure', 'observation-complete-failure',
  'cancel-before-publication', 'restart-after-capture',
  'restart-after-capture-object-projection', 'restart-before-capture']) {
test(`ordinary public INFER dispatch and capture custody: ${boundary}`,
  {timeout: 60000}, async t => {
    const {installation, taskCid} = await installedDependencyConfiguration('valid');
    let calls = 0;
    let failedWrite = false;
    let failedObservation = false;
    let observationSteps = 0;
    let cancelledDuringExecution = false;
    const injectedFailure = boundary.endsWith('-failure');
    const restarting = boundary.startsWith('restart-');
    const objectProjection = boundary.includes('object-projection');
    const cancelledBeforeCapture = boundary === 'cancel-after-dispatch';
    const failedBeforeCapture = boundary.startsWith('usage-overflow') ||
      cancelledBeforeCapture;
    let run;
    let started;
    const startedRun = new Promise(resolve => { started = resolve; });
    const observations = [];
    const authorization = {...diagnosticAuthorization((name, detail) => {
      observations.push({name, detail});
    }), accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1', account_id: 'infer-owner',
      entries: [{entry_id: 'installed-allow', outcome: 'allow',
        principal: {all: true}, connection: {all: true}, resource: {all: true},
        operation: {all: true}, exclusions: []}],
    })};
    authorization.faultInjection = async (name, detail) => {
      if (cancelledBeforeCapture && !cancelledDuringExecution && calls === 1 &&
          name === 'infer_execution_advanced') {
        cancelledDuringExecution = true;
        await startedRun;
        await run.cancel();
      }
      if (name === 'infer_observation_advanced') {
        observationSteps++;
        if (!failedObservation &&
            ((boundary === 'observation-step-failure' && !detail.complete) ||
             (boundary === 'observation-complete-failure' && detail.complete))) {
          failedObservation = true;
          throw new Error('InjectedObservationBoundaryFailure');
        }
      }
      if ((boundary === 'private-write-failure' ||
          boundary === 'usage-overflow-write-failure') && !failedWrite &&
          name === 'infer_private_holding_commit' &&
          detail.role === (failedBeforeCapture ? 'model_attempt_accounting' :
            'model_slot_capture')) {
        failedWrite = true;
        throw new Error('InjectedPrivateCaptureWriteFailure');
      }
      if (boundary === 'cancel-before-publication' &&
          name === 'infer_capture_committed') {
        await startedRun;
        await run.cancel();
      }
    };
    const registerModelProviders = moon => [{providerId: 'models/fixture',
        invoke() { throw new Error('UnpreparedProviderCall'); },
        validatePrompt(actualTask, selector, wire) {
          return actualTask === taskCid && selector === 'fixture-risk-model' &&
            JSON.parse(wire).format === 'fixture-risk/0.1';
        },
        quantityCapacity: {
          limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
          perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n},
        },
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
                'installed-request', 1n,
                boundary.startsWith('usage-overflow') ? 1000n : 2n,
                new Date().toISOString());
            }))}), () => true),
      }];
    const {client, root, physicalStarts, closeHost} = await installedHost(t, {
      modelInstallation: installation, authorization, registerModelProviders,
      initializeRoot: !restarting ? undefined : directory => {
        // A separate process uses the real public HTTPS entry, then exits
        // after durable capture and before Result publication or cleanup.
        const source = `
          import assert from 'node:assert/strict';
          import {readFileSync} from 'node:fs';
          import {createServer} from 'node:https';
          import {dirname, join} from 'node:path';
          import {userInfo} from 'node:os';
          import {setDefaultCACertificates} from 'node:tls';
          import {connect} from ${JSON.stringify(new URL('../../packages/sdk/index.mjs', import.meta.url).href)};
          import {openInstalledRemoteHttpHost} from ${JSON.stringify(new URL('./embedded-local.mjs', import.meta.url).href)};
          const input = JSON.parse(readFileSync(0, 'utf8'));
          const {directory, installation, taskCid, authorization, boundary} = input;
          const checked = ${checked.toString()};
          const oneRowInfer = ${oneRowInfer.toString()};
          let calls = 0;
          const registerModelProviders = ${registerModelProviders.toString()};
          authorization.faultInjection = name => {
            if (name === (boundary.startsWith('restart-after-capture')
              ? 'infer_capture_committed' : 'infer_private_holding_commit')) {
              assert.equal(calls, 1);
              process.stdout.write('capture-stop\\n', () => process.exit(0));
              return new Promise(() => {});
            }
          };
          const host = await openInstalledRemoteHttpHost({directory,
            authenticate: () => userInfo().username, authorization,
            modelInstallation: installation, registerModelProviders});
          const certificate = readFileSync(join(dirname(directory), 'host.crt'));
          setDefaultCACertificates([certificate.toString()]);
          const server = createServer({cert: certificate,
            key: readFileSync(join(dirname(directory), 'host.key'))}, host.handler);
          await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
          const client = await connect({mode: 'remote',
            endpoint: 'https://127.0.0.1:' + server.address().port + '/',
            token: 'fixture-owner', durability: 'durable'});
          const run = await client.start(oneRowInfer(boundary.includes('object-projection')),
            {requestId: 'public-infer'});
          await run.wait();
          throw new Error('CaptureStopNotReached');
        `;
        const output = execFileSync(process.execPath,
          ['--input-type=module', '-e', source], {encoding: 'utf8', timeout: 30000,
            input: JSON.stringify({directory, installation, taskCid, authorization,
              boundary})});
        assert.match(output, /capture-stop/);
      },
    });
    try {
      run = await client.start(oneRowInfer(objectProjection),
        {requestId: 'public-infer'});
      started();
      let terminal = await run.wait();
      if (boundary === 'restart-before-capture') {
        assert.equal(terminal.status, 'needs_reconciliation');
        await assert.rejects(run.result('answer').all());
        assert.equal(calls, 0, 'unknown response custody cannot redispatch');
        assert.equal(observationSteps, 0);
        return;
      }
      // A failed private write can be observed before retained cleanup has
      // confirmed physical close. Do not confuse that honest unknown state
      // with a stopped failure; wait for the actual owner observation.
      for (let poll = 0; injectedFailure &&
        terminal.status === 'needs_reconciliation' && poll < 100; poll++) {
        await new Promise(resolve => setImmediate(resolve));
        terminal = await run.wait();
      }
      const successful = boundary === 'success' ||
        boundary.startsWith('restart-after-capture') || objectProjection;
      assert.equal(terminal.status, successful
        ? 'succeeded' : cancelledBeforeCapture ? 'cancelled' :
          injectedFailure || failedBeforeCapture ? 'failed' : 'cancelled');
      assert.equal(cancelledDuringExecution, cancelledBeforeCapture);
      assert.equal(failedWrite, boundary === 'private-write-failure' ||
        boundary === 'usage-overflow-write-failure');
      assert.equal(failedObservation, boundary.startsWith('observation-'));
      // Begin, one slot, and finalize: retries retain the issuer
      // rather than starting another observation or advancing a terminal one.
      assert.equal(observationSteps, failedBeforeCapture ? 0 : 3);
      if (successful) {
        assert.deepEqual(await run.result('answer').all(),
          objectProjection
            ? [{assessment: {input_key: {id: 'a'}, outcome: 'ok',
              value: {reason: null, risk: 'high'}}}]
            : [{id: 'a', outcome: 'ok', value: {reason: null, risk: 'high'}}]);
      } else {
        await assert.rejects(run.result('answer').all());
      }
      assert.equal(calls, restarting ? 0 : 1);
      assert.equal(physicalStarts(), 1);
      // Independent custody preimages: no product holding helper is used to
      // discover the expected cells. Successful response and all slot proofs
      // remain retained even when publication is cancelled or a write retries.
      const storeCid = `sha256:${createHash('sha256').update(JSON.stringify({
        version: 'actql-local-store-owner/0.1', root: join(root, 'state'),
        principalId: userInfo().username})).digest('hex')}`;
      for (const [role, slot] of [
        ...(!failedBeforeCapture ? [['model_capture_bundle', -1], ['observation_set', -1],
          ['run_invocation', -1], ['model_slot_capture', 0]] : []),
        ['model_call_attempt', 0], ['model_attempt_accounting', 0],
        ['model_attempt_outcome', 0], ['model_dispatch_authority', 0],
      ]) {
        const identity = contentCid({role, slot,
          run_definition_cid: run.ref.runDefinitionCid,
          store_authority_cid: storeCid,
          version: 'actql-model-private-holding/0.1'});
        const record = JSON.parse(await readFile(join(root, 'state', 'publication',
          'physical-holdings', `${identity.slice(7)}.json`), 'utf8'));
        assert.equal(record.holding_cid, identity);
        assert.equal(record.namespace, 'publication-private');
        assert.equal(record.objects.length, 1);
      }
      if (failedBeforeCapture) {
        await closeHost();
        const key = await loadPrivateEvidenceKey(join(root, 'state', 'checkpoints'));
        const evidenceStore = await openLocalPublicationStore({
          directory: join(root, 'state', 'publication'), storeAuthorityCid: storeCid,
          capacityBytes: 512 * 1024 * 1024, maxObjectBytes: 1048576,
          maxObjects: 10000, maxContractNodes: 10000, maxContractDepth: 64,
          privateEvidenceKey: key.key,
        }, createPublicationContractControlFixture());
        key.key.fill(0);
        try {
          for (const role of ['model_attempt_accounting', 'model_attempt_outcome']) {
            const holdingCid = contentCid({role, slot: 0,
              run_definition_cid: run.ref.runDefinitionCid,
              store_authority_cid: storeCid,
              version: 'actql-model-private-holding/0.1'});
            const record = await evidenceStore.inspectPhysicalHolding(holdingCid);
            const body = JSON.parse(new TextDecoder().decode(
              await evidenceStore.readPrivateEvidence(role, record.manifest_cid,
                holdingCid)));
            if (role === 'model_attempt_accounting') {
              assert.equal(body.input_tokens, 1);
              assert.equal(body.output_tokens, cancelledBeforeCapture ? 2 : 1000);
              assert.equal(body.cost_units, null);
              assert.equal(body.duration_ms, null);
              assert.ok(body.cumulative_work > 0);
            } else {
              assert.equal(body.category, cancelledBeforeCapture ? 'cancelled' :
                'contract_violation');
              assert.equal(body.failure, cancelledBeforeCapture ? 'cancelled' :
                'budget_exceeded');
            }
          }
        } finally { await evidenceStore.close(); }
        assert.equal(calls, 1, 'failed custody retries must not invoke the model');
      }
    } catch (error) {
      const journal = new DatabaseSync(join(root, 'state', 'requests',
        'client-requests.sqlite3'), {readOnly: true});
      try {
        t.diagnostic(inspect(journal.prepare('SELECT physical_start_reserved, ' +
          'physical_close_confirmed, observed_terminal_outcome FROM client_requests')
          .all()));
      } finally { journal.close(); }
      t.diagnostic(inspect(observations, {depth: 6}));
      throw error;
    }
  });
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
