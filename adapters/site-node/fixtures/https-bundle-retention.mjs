import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, open, readFile, rm, unlink, writeFile} from 'node:fs/promises';
import {request as httpsRequest} from 'node:https';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import * as moon from
  '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../../host-common/runtime-core.mjs';
import {admitRemoteDispatchJson} from '../../host-common/remote-dispatch-wire.mjs';
import {sendRemoteBundleCustody} from '../../host-node/remote-bundle-retention-client.mjs';
import {startHttpsRemoteSiteAgent} from '../https-agent.mjs';
import {certificates} from '../https-test-certificates.mjs';
import {createRemoteBundleRetentionCustodian} from '../remote-bundle-retention.mjs';
import {signRemoteRuntimeBundle} from '../remote-bundle-signature.mjs';
import {
  createRemoteDispatchRuntime,
  prepareInstalledRemoteRuntimeRegistration,
} from '../remote-dispatch-runtime.mjs';
import {openRuntimeBundleStore} from '../runtime-bundle-store.mjs';
import {openSqliteDispatchJournal} from '../sqlite-dispatch-journal.mjs';

export const runtime = runtimeCore(moon);
export const control = runtime.remoteSiteControl;
export const bundles = runtime.remoteBundleControl;
export const cid = digit => `sha256:${digit.repeat(64)}`;
export const digest = body =>
  `sha256:${createHash('sha256').update(body).digest('hex')}`;
export const inputBindingBody = '{"value":7}';
const targetTriple = 'node-js-local-fixture';
const budget = control.prepareBudget({retainedBytes: 64n, executionBytes: 16n});

async function persistBinding(root, owner, distribution, binding) {
  const path = join(root, `${owner.holdBindingIdentity(binding).slice(7)}.json`);
  const file = await open(path, 'wx', 0o600);
  try {
    await file.writeFile(JSON.stringify({
      distribution: owner.distributionJson(distribution),
      distributionCid: owner.distributionIdentity(distribution),
      binding: owner.holdBindingJson(binding),
      bindingCid: owner.holdBindingIdentity(binding),
    }));
    await file.sync();
  } finally { await file.close(); }
  const directory = await open(root, 'r');
  try { await directory.sync(); }
  finally { await directory.close(); }
  return path;
}

async function restoreBinding(path, owner) {
  const saved = JSON.parse(await readFile(path, 'utf8'));
  const distribution = owner.admitDistributionJson(
    saved.distribution, saved.distributionCid,
  );
  return {distribution, binding: owner.admitHoldBindingJson(
    distribution, saved.binding, saved.bindingCid,
  )};
}

export async function retentionFixture(t, {maxOwners = 4} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-https-bundle-retention-'));
  const agents = [];
  const stores = [];
  const barriers = [];
  t.after(async () => {
    for (const barrier of barriers) barrier.release();
    try {
      for (const agent of agents.reverse()) await agent.close();
    } finally {
      for (const store of stores.reverse()) store.close();
      await rm(root, {recursive: true, force: true});
    }
  });
  const material = await certificates(root);
  const outputDirectory = join(root, 'outputs');
  await mkdir(outputDirectory);
  await writeFile(join(root, 'package.json'), '{"type":"module"}\n');
  const bytes = await readFile(new URL('./installed-connector-members.mjs', import.meta.url));
  const sourcePath = join(root, 'authored-component.mjs');
  await writeFile(sourcePath, bytes, {mode: 0o600});
  const keys = generateKeyPairSync('ed25519');
  const bundleOptions = {
    bundleAuthorities: new Map([
      ['fixture-authority', new Map([['fixture-key', keys.publicKey]])],
    ]),
    targetTriple, maxBundles: 2, maxOwners, maxComponentBytes: 65_536n,
  };
  const effects = {loads: [], providers: [], secrets: [], closes: []};
  const members = [];
  const tls = member => ({
    origin: member.agent.origin,
    ca: material.ca,
    cert: material.coordinatorCertificate,
    key: material.coordinatorKey,
  });
  for (const [name, operationDigit, issuerDigit] of [
    ['local-alpha', '1', 'b'], ['local-beta', '2', 'c'],
  ]) {
    const manifest = bundles.prepare({
      issuerAuthority: 'fixture-authority', bundleName: 'authored-members',
      revision: '1', targetTriple, componentCid: digest(bytes),
      componentBytes: BigInt(bytes.byteLength), connectorRegistration: name,
      connectorRevision: `${name}/1`, strategyRevision: `strategy/${name}/1`,
    });
    const member = {
      name, manifest, runtimeBundleCid: bundles.identity(manifest),
      siteKey: `retention-site-${name}`,
      operationCapabilityCid: cid(operationDigit),
      issuerCapabilityCid: cid(issuerDigit),
      authorities: new Map([[material.coordinatorFingerprint, 'coordinator-a']]),
      seen: [],
    };
    members.push(member);
    const bundleRoot = join(root, `bundles-${name}`);
    const dispatchRoot = join(root, `dispatches-${name}`);
    const start = async ({install = false, retention = true} = {}) => {
      member.bundleStore = await openRuntimeBundleStore(bundleRoot, bundleOptions);
      stores.push(member.bundleStore);
      if (install) {
        await member.bundleStore.install(sourcePath,
          signRemoteRuntimeBundle(manifest, bundles, {
            keyId: 'fixture-key', privateKey: keys.privateKey,
          }), bundles);
        member.bundleStore.activate(member.runtimeBundleCid, bundles);
      }
      // Each Site has its own existing active catalog. Preparing another Set
      // never activates or drains a bundle on this Site.
      member.site = runtime.siteControl.create({
        key: member.siteKey, generation: 1, runtimeRevision: member.runtimeBundleCid,
        maxConcurrentOperations: 4, maxConcurrentTransfers: 4,
        maxRetainedBytes: 1_048_576n, maxExecutionBytes: 1_048_576n,
      });
      member.journal = control.createJournal(member.site);
      member.store = openSqliteDispatchJournal(dispatchRoot, {
        siteKey: member.siteKey, siteGeneration: 1,
        runtimeRevision: member.runtimeBundleCid,
      });
      stores.push(member.store);
      const registration = await prepareInstalledRemoteRuntimeRegistration({
        control, site: member.site, bundleStore: member.bundleStore,
        bundleControl: bundles, runtimeBundleCid: member.runtimeBundleCid,
        connectorRegistration: name, connectorRevision: `${name}/1`,
        strategyRevision: `strategy/${name}/1`,
        operationCapabilityCid: member.operationCapabilityCid,
        evidenceKind: control.managedOutputEvidenceKind,
        issuerCapabilityCid: member.issuerCapabilityCid,
        async load(installed) {
          const location = pathToFileURL(installed.artifactPath).href;
          const component = await import(location);
          assert.equal(component.loadedFrom, location);
          effects.loads.push(name);
          return component.loadMember(name, {
            outputDirectory,
            async provider(value) { effects.providers.push(value); },
            async secret(value) { effects.secrets.push(value); },
            closed(value) { effects.closes.push(value); },
          });
        },
      });
      member.dispatchRuntime = createRemoteDispatchRuntime({
        control, siteControl: runtime.siteControl, store: member.store,
        bundleStore: member.bundleStore, bundleControl: bundles,
        registrations: [registration], budgets: [budget],
      });
      const custodian = createRemoteBundleRetentionCustodian({
        bundleStore: member.bundleStore, bundleControl: bundles,
        dispatchControl: control, registration,
        scopes: [{coordinatorAuthority: 'coordinator-a', workspaceId: 'workspace-a',
          authorityScopeCid: cid('a'), environment: 'test',
          runtimeBundleCid: member.runtimeBundleCid}],
      });
      member.agent = await startHttpsRemoteSiteAgent({
        key: material.siteKey, cert: material.siteCertificate, ca: material.ca,
        coordinatorAuthorities: member.authorities,
        siteKey: member.siteKey, siteGeneration: 1,
        journal: member.journal, store: member.store, control,
        admitDispatchJson: admitRemoteDispatchJson,
        dispatchRuntime: member.dispatchRuntime,
        maxRequestBytes: 4096,
        ...(retention ? {bundleRetention: {
          ...custodian,
          async handle(authority, request, options) {
            const operation = bundles.custodyRequestOperation(request);
            member.seen.push(bundles.custodyRequestIdentity(request));
            const barrier = member.barrier?.operation === operation
              ? member.barrier : undefined;
            if (barrier !== undefined) member.barrier = undefined;
            if (barrier?.before) {
              barrier.arrive();
              await barrier.waiting;
            }
            const response = await custodian.handle(authority, request, options);
            if (barrier !== undefined && !barrier.before) {
              barrier.arrive(response);
              await barrier.waiting;
            }
            const replacement = member.replacement;
            member.replacement = undefined;
            return replacement ?? response;
          },
        }} : {}),
      });
      agents.push(member.agent);
    };
    member.restart = async options => {
      await member.agent.close();
      member.store.close();
      member.bundleStore.close();
      await start(options);
    };
    member.pause = (operation, {before = false} = {}) => {
      assert.equal(member.barrier, undefined);
      let arrive;
      let release;
      const reached = new Promise(resolve => { arrive = resolve; });
      const waiting = new Promise(resolve => { release = resolve; });
      const barrier = {operation, before, arrive, release, reached, waiting};
      barriers.push(barrier);
      member.barrier = barrier;
      return barrier;
    };
    await start({install: true});
  }
  // Subsequent registration can load only the signed installed artifact.
  await unlink(sourcePath);
  const scope = (member, overrides = {}) => {
    const distribution = overrides.distribution ??
      bundles.prepareDistribution([member.runtimeBundleCid]);
    return {distribution, scope: bundles.prepareHoldScope({
      distribution, coordinatorAuthority: 'coordinator-a', workspaceId: 'workspace-a',
      authorityScopeCid: cid('a'), environment: 'test', setRevisionCid: cid('b'),
      runtimeBundleCid: member.runtimeBundleCid, siteKey: member.siteKey,
      siteGeneration: 1, attemptId: 'attempt-a', ...overrides,
    })};
  };
  const request = (prepared, operation) => bundles.prepareCustodyRequest(
    prepared.distribution, prepared.binding, operation,
  );
  const exchange = (member, value, options = {}) => sendRemoteBundleCustody({
    ...tls(member), control: bundles, request: value, ...options,
  });
  return {
    root, material, members, effects, tls, scope, request, exchange,
    state: member => bundles.recordProjection(
      member.bundleStore.inspect(member.runtimeBundleCid, bundles).record,
    ),
    outputPath: member => join(outputDirectory, `${member.name}.json`),
    custody: (prepared, operation, options) => exchange(
      prepared.member, request(prepared, operation), options,
    ),
    async prepare(member, overrides) {
      const value = scope(member, overrides);
      const response = await exchange(member,
        bundles.prepareCustodyContextQuery(value.distribution, value.scope));
      assert.equal(bundles.custodyResponseKind(response), 'context');
      assert.equal(bundles.custodyResponseObservation(response), '');
      const binding = bundles.custodyResponseBinding(response);
      // This fixture persists the original response before sending retain.
      // It is not a Cloud preparation transaction or a selection CAS.
      const path = await persistBinding(root, bundles, value.distribution, binding);
      return Object.freeze({member, distribution: value.distribution, binding, path});
    },
    async reload(prepared) {
      return Object.freeze({...prepared, ...await restoreBinding(prepared.path, bundles)});
    },
    dispatch(prepared, dispatchId, overrides = {}) {
      const {member, binding} = prepared;
      const parts = bundles.holdBindingProjection(binding);
      assert.equal(parts[8], member.runtimeBundleCid);
      assert.equal(parts[9], member.siteKey);
      return control.prepare({
        coordinatorAuthority: parts[2], runDefinitionCid: cid('0'),
        taskKey: member.name, taskAttempt: 1, dispatchId,
        siteKey: parts[9], siteGeneration: Number(parts[10]), runtimeBundleCid: parts[8],
        connectorRegistration: member.name, connectorRevision: `${member.name}/1`,
        strategyRevision: `strategy/${member.name}/1`,
        inputBindingCid: control.inputBindingIdentity(control.prepareInputBinding(inputBindingBody)),
        obligationsCid: cid('4'), budgetCid: control.budgetIdentity(budget),
        evidenceIssuerCapabilityCid: member.issuerCapabilityCid,
        grantCid: member.operationCapabilityCid, ...overrides,
      });
    },
  };
}

// The supplied portable client and the checkout Site runtime never exchange
// opaque values. Only canonical JSON/CIDs cross their real HTTPS boundary.
export async function exercisePortableBundleRetention(clientControl) {
  const cleanup = [];
  try {
    const f = await retentionFixture({after: action => cleanup.push(action)});
    const [member] = f.members;
    const distribution = clientControl.prepareDistribution([member.runtimeBundleCid]);
    const scope = clientControl.prepareHoldScope({
      distribution, coordinatorAuthority: 'coordinator-a', workspaceId: 'workspace-a',
      authorityScopeCid: cid('a'), environment: 'test', setRevisionCid: cid('b'),
      runtimeBundleCid: member.runtimeBundleCid, siteKey: member.siteKey,
      siteGeneration: 1, attemptId: 'portable-client',
    });
    const send = request => sendRemoteBundleCustody({
      ...f.tls(member), control: clientControl, request,
    });
    const context = await send(clientControl.prepareCustodyContextQuery(distribution, scope));
    assert.equal(clientControl.custodyResponseKind(context), 'context');
    assert.equal(clientControl.custodyResponseObservation(context), '');
    assert.equal(f.state(member)[2], '0');
    const original = clientControl.custodyResponseBinding(context);
    const bindingCid = clientControl.holdBindingIdentity(original);
    const path = await persistBinding(f.root, clientControl, distribution, original);
    const restored = await restoreBinding(path, clientControl);
    assert.equal(clientControl.holdBindingIdentity(restored.binding), bindingCid);
    const observations = [];
    for (const [operation, expected, owners] of [
      ['retain', 'retained', '1'], ['query', 'retained', '1'],
      ['release', 'fenced', '0'], ['query', 'fenced', '0'],
    ]) {
      const response = await send(clientControl.prepareCustodyRequest(
        restored.distribution, restored.binding, operation,
      ));
      const observation = clientControl.custodyResponseObservation(response);
      assert.equal(observation, expected);
      assert.equal(f.state(member)[2], owners);
      assert.equal(clientControl.holdBindingIdentity(restored.binding), bindingCid);
      observations.push(observation);
    }
    assert.deepEqual(f.effects.providers, []);
    assert.deepEqual(f.effects.secrets, []);
    return Object.freeze({bindingCid,
      distributionCid: clientControl.distributionIdentity(restored.distribution),
      observations: Object.freeze(observations)});
  } finally {
    for (const action of cleanup.reverse()) await action();
  }
}

export async function rawCustody(f, member, body, {
  claimed = digest(body), cert = f.material.coordinatorCertificate,
  key = f.material.coordinatorKey, path,
} = {}) {
  const target = path ?? `/v1/sites/${member.siteKey}/generations/1/bundle-retention`;
  return await new Promise((resolve, reject) => {
    const request = httpsRequest(new URL(target, member.agent.origin), {
      method: 'POST', ca: f.material.ca, cert, key, agent: false,
      servername: 'localhost', minVersion: 'TLSv1.3', rejectUnauthorized: true,
      headers: {'content-type': 'application/json',
        'content-length': String(Buffer.byteLength(body)), 'actql-bundle-custody-cid': claimed},
    }, response => {
      response.resume();
      response.on('error', reject);
      response.on('end', () => resolve(response.statusCode));
    });
    request.on('error', reject);
    request.end(body);
  });
}
