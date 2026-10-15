import assert from 'node:assert/strict';
import {mkdtemp, readFile, readdir, rm} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {generateKeyPairSync} from 'node:crypto';
import {takeCoverage, stopCoverage} from 'node:v8';
import {connect, getSubmissionOutcome} from '../../packages/sdk/index.mjs';
import {DatabaseSync} from 'node:sqlite';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonical, cid, configuration, program} from '../../scripts/fixtures/installed-infer-fixture.mjs';
import {providerBindingOriginals} from '../../scripts/fixtures/model-provider-binding-fixture.mjs';

// Actual Host/caller/Core scope, but deliberately refused original read layout.
// Synthetic declarations exercise identity/cleanup only, not physical funding.
// V8 coverage observes the unmodified production functions, not a new issuer.
const lateCurrentLoss = process.argv[2] === 'late-current';
const selected = process.argv[2] !== 'absent';
assert.ok(['selected', 'absent', 'late-current'].includes(process.argv[2]));
const root = await mkdtemp(join(tmpdir(), 'actql-a-original-startup-scope-'));
const profileSource = await readFile(new URL(
  '../../src/run_publication_host/client_model_preparation_layout_wbtest.mbt', import.meta.url), 'utf8');
const profileText = profileSource.match(/#\|(\{[^\n]+\})/u)[1];
let host, server, completed = false, providerCalls = 0, preflights = 0;
let invalidations = 0;
const failures = [];
const preparationFailures = [];
const keys = generateKeyPairSync('ed25519');
const authorization = {
  hostKey: {keyId: 'fixture-host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  reviewers: [{keyId: 'fixture-reviewer', reviewerId: 'fixture-reviewer',
    principalId: userInfo().username, publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  accountConfiguration: canonical({version: 'actql-execution-account-config/0.1', account_id: 'scope-fixture',
    entries: [{entry_id: 'allow', outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {all: true}, exclusions: []}]}),
  faultInjection(name) {
    if (lateCurrentLoss && name === 'physical_start_reserved') {
      invalidations++;
      // The existing Host hook is on authorization, not an ignored extra
      // open() option. Preserve a real change after preparation/admission.
      process.argv[1] = `${process.argv[1]}.changed-after-admission`;
    }
  },
  observe(name, detail) {
    if (name === 'dispatch_failed') failures.push(detail);
    if (name === 'infer_preparation_rejected') preparationFailures.push(detail);
  },
};
try {
  const base = JSON.parse(await readFile(new URL('../../spec/local-check-environment.json', import.meta.url), 'utf8'));
  const {installation, taskCid} = configuration(base);
  host = await openInstalledRemoteHttpHost({directory: root, workspaceId: 'scope', loopbackHttp: true,
    authenticate: () => userInfo().username, authorization, modelInstallation: installation,
    registerModelProviders(moon) {
      const control = runtimeCore(moon).publicationControl;
      const profileBody = JSON.parse(profileText); delete profileBody.self_cid;
      profileBody.task.contract_cid = taskCid;
      // Match the existing checked Host request ceiling, so a separate 1024
      // fixture bound cannot mask the intentionally foreign layout identity.
      profileBody.limits.request_bytes = 1000;
      const identity = cid(profileBody);
      const profile = control.readInstalledModelResponseProfile(canonical({...profileBody, self_cid: identity}),
        identity, {maxWireBytes: 10000, maxNodes: 1000, maxDepth: 30, maxMembers: 1000, maxWork: 100000});
      const physical = {...profileBody.adapter, sdk: undefined, endpoint: profileBody.operation.endpoint,
        http_method: profileBody.operation.method, streaming: false,
        validator_id: profileBody.completion.validator_id, validator_revision: profileBody.completion.validator_revision,
        validator_artifact_cid: profileBody.completion.validator_artifact_cid, completion_basis: 'generation_finish'};
      delete physical.port_abi;
      const originalReadInstallation = {
        bootstrap: {bootstrapRetainedBytes: 3n, bootstrapExecutionBytes: 2n,
          maxReservations: 8, maxHoldings: 8, maxDelegations: 0},
        modelRetainedBytes: 100n, modelExecutionBytes: 5n,
        publicationCapacity: {retainedBytes: 1n, workspaceBytes: 0n},
        currentStateCodec: {quantum: 1, comparisonWork: 5, decode: {maxWork: 20000,
          parse: {max_input_bytes: 10000, max_nodes: 1000, max_depth: 20},
          tree: {max_nodes: 1000, max_depth: 20, max_string_bytes: 10000, max_total_string_bytes: 10000}}},
        // Explicitly wrong original Program/parameter/barrier identity. The
        // real Core must refuse this only AFTER the actual Scope association.
        nodeInstallation: {layout: {response_profile: profile,
          runtime_artifact_cid: cid({fixture: 'runtime'}), layout_artifact_cid: cid({fixture: 'layout'}),
          program_definition_cid: cid({fixture: 'foreign-program'}), parameter_values_cid: cid({fixture: 'foreign-parameters'}),
          barrier_cid: cid({fixture: 'foreign-barrier'}), prepared_rows: 2n, retained_bytes: 7n, execution_bytes: 5n},
          installation: physical, runtimeArtifactCid: cid({fixture: 'runtime'}),
          layoutArtifactCid: cid({fixture: 'layout'}), probability: undefined},
      };
      return [{providerId: 'models/packed', originalReadInstallation,
        bindingOriginals: providerBindingOriginals('models/packed', {selector: 'packed-risk-model'}),
        validatePrompt: (actual, selector, wire) => actual === taskCid && selector === 'packed-risk-model' &&
          JSON.parse(wire).format === 'packed-risk/0.1',
        invoke() { providerCalls++; assert.fail('Refused original read cannot invoke a Model'); },
        quantityCapacity: {limits: {tokens: 33n, costUnits: 0n, durationMs: 500n},
          perAttempt: {tokens: 33n, costUnits: 0n, durationMs: 500n}},
        observeEgress: () => ({_0: 'public', _1: 'fixture-region', _2: false, _3: false}),
        physicalPreflight() { preflights++; assert.fail('Refused original read cannot prepare a physical Call'); },
      }];
    }});
  server = createServer(host.handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const client = await connect(`actql://127.0.0.1:${server.address().port}/scope?transport=http`,
    {token: 'synthetic-only', durability: 'durable'});
  const submissionRef = client.newSubmission({nonce: 'original-scope'});
  if (selected) {
    const run = await client.start(program, {submissionRef});
    const terminal = await run.wait();
    assert.notEqual(terminal.status, 'succeeded');
    if (lateCurrentLoss) {
      assert.equal(terminal.status, 'failed', 'same custody must settle the admitted failure');
      assert.equal(failures[0].code, 'InferTrustedStartupChanged');
      assert.equal(invalidations, 1, 'never start a replacement dispatch');
    }
    assert.equal(failures.length, 1);
    assert.equal(preparationFailures.length, 0);
  } else {
    await assert.rejects(client.start(program, {submissionRef}), error => {
      const outcome = getSubmissionOutcome(error);
      assert.equal(outcome.kind, 'preparation_failed');
      assert.equal(outcome.problem.code, 'ClientProgramUnsupported');
      return true;
    });
    assert.equal(failures.length, 0, 'known missing startup never reserves dispatch start');
    assert.equal(preparationFailures.length, 1);
    assert.equal(preparationFailures[0].boundary, 'model_admission.original_startup');
    const journal = new DatabaseSync(join(root, 'requests', 'client-requests.sqlite3'), {readOnly: true});
    try { assert.equal(journal.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count, 0); }
    finally { journal.close(); }
  }
  assert.equal(providerCalls, 0);
  assert.equal(preflights, 0);
  await host.close();
  await host.close();
  host = undefined;
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  server = undefined;
  takeCoverage(); stopCoverage();
  const counts = {};
  for (const name of await readdir(process.env.NODE_V8_COVERAGE)) {
    if (!name.endsWith('.json')) continue;
    const coverage = JSON.parse(await readFile(join(process.env.NODE_V8_COVERAGE, name), 'utf8'));
    for (const item of coverage.result) {
      if (!item.url.endsWith('/adapters/host-node/embedded-local.mjs') &&
          !item.url.endsWith('/adapters/host-common/runtime-core.mjs') &&
          !item.url.endsWith('/adapters/host-node/infer-trusted-node-preload.cjs')) continue;
      for (const fn of item.functions) {
        if (['beginCheckedClientInferOriginalReadScope', 'prepareCheckedClientInferNodeReadLayout',
          'finishCheckedClientInferOriginalReadScope', 'bindTrustedRuntimeScope', 'borrowScope', 'retire'].includes(fn.functionName)) {
          counts[fn.functionName] = (counts[fn.functionName] ?? 0) + fn.ranges[0].count;
        }
      }
    }
  }
  const scoped = selected && !lateCurrentLoss;
  assert.equal(counts.beginCheckedClientInferOriginalReadScope ?? 0, scoped ? 1 : 0);
  assert.equal(counts.bindTrustedRuntimeScope ?? 0, scoped ? 1 : 0);
  assert.equal(counts.borrowScope ?? 0, scoped ? 1 : 0);
  assert.equal(counts.prepareCheckedClientInferNodeReadLayout ?? 0, scoped ? 1 : 0);
  assert.equal(counts.finishCheckedClientInferOriginalReadScope ?? 0, scoped ? 1 : 0);
  completed = true;
  console.log(JSON.stringify({selected, lateCurrentLoss, invalidations, counts, providerCalls, preflights,
    actualHost: true, actualCoreScope: scoped ? 1 : 0, normalNumericProfile: null, publicE2E: 0}));
} catch (error) {
  // Keep the original assertion/primary diagnostic even if the same Host's
  // cleanup also refuses. This fixture contains no credentials/raw response.
  console.error(JSON.stringify({fixturePrimary: error.code ?? error.name,
    assertionActual: error.actual, assertionExpected: error.expected, invalidations,
    dispatchCodes: failures.map(detail => detail.code)}));
  throw error;
} finally {
  if (server !== undefined) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  try { if (host !== undefined) await host.close(); }
  finally {
    if (completed) await rm(root, {recursive: true, force: true});
    else console.error(`Original startup Scope fixture retained: ${root}`);
  }
}
