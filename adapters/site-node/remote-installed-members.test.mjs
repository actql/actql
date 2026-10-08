import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, unlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {pathToFileURL} from 'node:url';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {runtimeCore} from '../host-common/runtime-core.mjs';
import {signRemoteRuntimeBundle} from './remote-bundle-signature.mjs';
import {
  createRemoteDispatchRuntime,
  prepareInstalledRemoteRuntimeRegistration,
} from './remote-dispatch-runtime.mjs';
import {openRuntimeBundleStore} from './runtime-bundle-store.mjs';
import {openSqliteDispatchJournal} from './sqlite-dispatch-journal.mjs';

const runtime = runtimeCore(moon);
const control = runtime.remoteSiteControl;
const bundleControl = runtime.remoteBundleControl;
const cid = digit => `sha256:${digit.repeat(64)}`;
const targetTriple = 'node-js-local-fixture';
const inputBindingBody = '{"value":7}';
const inputBindingCid = control.inputBindingIdentity(
  control.prepareInputBinding(inputBindingBody),
);
const budget = control.prepareBudget({retainedBytes: 64n, executionBytes: 16n});
const budgetCid = control.budgetIdentity(budget);

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-installed-members-'));
  const outputDirectory = join(root, 'outputs');
  const runtimes = [];
  const stores = [];
  const pauses = new Map();
  let bundleStore;
  t.after(async () => {
    for (const pause of pauses.values()) pause.release();
    try {
      for (const value of runtimes) await value.close();
    } finally {
      for (const store of stores) store.close();
      bundleStore?.close();
      await rm(root, {recursive: true, force: true});
    }
  });
  await mkdir(outputDirectory);
  // Installed component filenames are content addresses without extensions.
  // This local package makes their direct file-URL imports unambiguously ESM.
  await writeFile(join(root, 'package.json'), '{"type":"module"}\n');
  const bytes = await readFile(new URL(
    './fixtures/installed-connector-members.mjs',
    import.meta.url,
  ));
  const sourcePath = join(root, 'authored-component.mjs');
  await writeFile(sourcePath, bytes);
  const componentCid = `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  const keys = generateKeyPairSync('ed25519');
  bundleStore = await openRuntimeBundleStore(join(root, 'bundles'), {
    bundleAuthorities: new Map([
      ['fixture-authority', new Map([['fixture-key', keys.publicKey]])],
    ]),
    targetTriple,
    maxBundles: 4,
    maxOwners: 4,
    maxComponentBytes: 65_536n,
  });
  const members = [];
  for (const [name, operationDigit, issuerDigit] of [
    ['local-alpha', '1', 'b'],
    ['local-beta', '2', 'c'],
  ]) {
    const tuple = Object.freeze({
      connectorRegistration: name,
      connectorRevision: `${name}/1`,
      strategyRevision: `strategy/${name}/1`,
    });
    const manifest = bundleControl.prepare({
      issuerAuthority: 'fixture-authority',
      bundleName: 'authored-members',
      revision: '1',
      targetTriple,
      componentCid,
      componentBytes: BigInt(bytes.byteLength),
      ...tuple,
    });
    const signed = signRemoteRuntimeBundle(manifest, bundleControl, {
      keyId: 'fixture-key',
      privateKey: keys.privateKey,
    });
    const installed = await bundleStore.install(
      sourcePath, signed, bundleControl,
    );
    const runtimeBundleCid = bundleControl.identity(manifest);
    const siteKey = `members-site-${name}`;
    // Each existing Site owner is bound to exactly one bundle revision. The
    // shared artifact does not imply multiple active bundles on one Site.
    const selectedSite = runtime.siteControl.create(Object.freeze({
      key: siteKey,
      generation: 1,
      runtimeRevision: runtimeBundleCid,
      maxConcurrentOperations: 4,
      maxConcurrentTransfers: 4,
      maxRetainedBytes: 1_048_576n,
      maxExecutionBytes: 1_048_576n,
    }));
    const journal = control.createJournal(selectedSite);
    const store = openSqliteDispatchJournal(join(root, `dispatches-${name}`), {
      siteKey,
      siteGeneration: 1,
      runtimeRevision: runtimeBundleCid,
    });
    stores.push(store);
    members.push(Object.freeze({
      ...tuple,
      runtimeBundleCid,
      operationCapabilityCid: cid(operationDigit),
      issuerCapabilityCid: cid(issuerDigit),
      installed,
      siteKey,
      selectedSite,
      journal,
      store,
    }));
  }
  // The loader has only the installed artifact; it cannot import this source.
  await unlink(sourcePath);
  const effects = {loads: [], providers: [], secrets: [], closes: []};
  const register = (member, overrides = {}) =>
    prepareInstalledRemoteRuntimeRegistration({
      control,
      site: member.selectedSite,
      bundleStore,
      bundleControl,
      runtimeBundleCid: member.runtimeBundleCid,
      connectorRegistration: member.connectorRegistration,
      connectorRevision: member.connectorRevision,
      strategyRevision: member.strategyRevision,
      operationCapabilityCid: member.operationCapabilityCid,
      evidenceKind: control.managedOutputEvidenceKind,
      issuerCapabilityCid: member.issuerCapabilityCid,
      ...overrides,
      async load(installed) {
        const name = bundleControl.projection(installed.manifest)[7];
        effects.loads.push(name);
        const location = pathToFileURL(installed.artifactPath).href;
        const component = await import(location);
        assert.equal(component.loadedFrom, location);
        return component.loadMember(name, {
          outputDirectory,
          async provider(name) {
            effects.providers.push(name);
            const pause = pauses.get(name);
            pause?.entered();
            await pause?.waiting;
          },
          async secret(name) { effects.secrets.push(name); },
          closed(name) { effects.closes.push(name); },
        });
      },
    });
  const request = (member, overrides = {}) => control.prepare({
    coordinatorAuthority: 'fixture-coordinator',
    runDefinitionCid: cid('0'),
    taskKey: member.connectorRegistration,
    taskAttempt: 1,
    dispatchId: `${member.connectorRegistration}-dispatch`,
    siteKey: member.siteKey,
    siteGeneration: 1,
    runtimeBundleCid: member.runtimeBundleCid,
    connectorRegistration: member.connectorRegistration,
    connectorRevision: member.connectorRevision,
    strategyRevision: member.strategyRevision,
    inputBindingCid,
    obligationsCid: cid('4'),
    budgetCid,
    evidenceIssuerCapabilityCid: member.issuerCapabilityCid,
    grantCid: member.operationCapabilityCid,
    ...overrides,
  });
  return {
    bundleStore,
    bytes,
    effects,
    members,
    register,
    request,
    activate: member => bundleStore.activate(
      member.runtimeBundleCid, bundleControl,
    ),
    state: member => bundleControl.recordProjection(
      bundleStore.inspect(member.runtimeBundleCid, bundleControl).record,
    ),
    outputPath: member => join(
      outputDirectory, `${member.connectorRegistration}.json`,
    ),
    accept: (member, request) => member.store.accept(
      control.prepareAdmission(member.journal, request), request, control,
    ),
    createRuntime(member, registration) {
      const value = createRemoteDispatchRuntime({
        control,
        siteControl: runtime.siteControl,
        store: member.store,
        bundleStore,
        bundleControl,
        registrations: [registration],
        budgets: [budget],
      });
      runtimes.push(value);
      return value;
    },
    pauseProvider(member) {
      let entered;
      let release;
      const started = new Promise(resolve => { entered = resolve; });
      const waiting = new Promise(resolve => { release = resolve; });
      pauses.set(member.connectorRegistration, {entered, release, waiting});
      return {started, release};
    },
  };
}

test('signed Connector members on distinct Sites share code and independent output owners',
  async t => {
    const f = await fixture(t);
    const [alpha, beta] = f.members;
    assert.notEqual(alpha.runtimeBundleCid, beta.runtimeBundleCid);
    assert.notEqual(alpha.siteKey, beta.siteKey);
    assert.equal(alpha.installed.artifactPath, beta.installed.artifactPath);
    const remotes = new Map();
    for (const member of f.members) {
      f.activate(member);
      const registration = await f.register(member);
      assert.deepEqual(control.managedRuntimeRegistrationScope(
        registration.capability, registration.issuer,
      ), [
        member.siteKey, '1', member.runtimeBundleCid,
        member.connectorRegistration, member.connectorRevision,
        member.strategyRevision, member.operationCapabilityCid,
        member.issuerCapabilityCid,
      ]);
      assert.deepEqual(member.store.configuration(), {
        siteKey: member.siteKey,
        siteGeneration: 1,
        runtimeRevision: member.runtimeBundleCid,
      });
      remotes.set(member, f.createRuntime(member, registration));
    }
    const firstRuntime = remotes.get(alpha);
    const secondRuntime = remotes.get(beta);
    const first = f.request(alpha);
    const second = f.request(beta);
    f.activate(alpha);
    assert.equal(firstRuntime.supports(first), true);
    assert.equal(secondRuntime.supports(second), false);
    const paused = f.pauseProvider(alpha);
    const firstRecord = f.accept(alpha, first);
    const executing = firstRuntime.start(
      first, firstRecord, undefined, inputBindingBody,
    );
    await Promise.race([paused.started, executing]);
    f.activate(beta);
    assert.equal(firstRuntime.supports(first), false);
    assert.equal(secondRuntime.supports(second), true);
    assert.deepEqual(f.state(alpha).slice(1), ['2', '1']);
    const runningState = f.state(alpha);
    await assert.rejects(
      f.bundleStore.reclaim(alpha.runtimeBundleCid, bundleControl),
      {code: 'MoonBitHostFailure'},
    );
    assert.deepEqual(f.state(alpha), runningState);
    await assert.rejects(readFile(f.outputPath(alpha)), {code: 'ENOENT'});
    paused.release();
    const firstCompleted = await executing;
    const secondRecord = f.accept(beta, second);
    const secondCompleted = await secondRuntime.start(
      second, secondRecord, undefined, inputBindingBody,
    );
    assert.equal(await readFile(f.outputPath(alpha), 'utf8'), '[8,9]\n');
    assert.equal(await readFile(f.outputPath(beta), 'utf8'), '[14,21]\n');
    assert.deepEqual(f.effects, {
      loads: ['local-alpha', 'local-beta'],
      providers: ['local-alpha', 'local-beta'],
      secrets: ['local-alpha', 'local-beta'],
      closes: [],
    });
    for (const [member, request, completed] of [
      [alpha, first, firstCompleted], [beta, second, secondCompleted],
    ]) {
      assert.deepEqual(completed.state, [3, 2, 0, 1, 0]);
      assert.equal(
        member.store.inspectEvidence(request, control).execution_evidence_cid,
        control.evidenceIdentity(completed.evidence),
      );
    }
    assert.notEqual(control.evidenceIdentity(firstCompleted.evidence),
      control.evidenceIdentity(secondCompleted.evidence));
    for (const [member, retainedBytes] of [[alpha, 6n], [beta, 8n]]) {
      assert.deepEqual(
        runtime.siteControl.status(member.selectedSite).slice(2, 9),
        [0n, 0n, 1n, 0n, retainedBytes, 0n, 0n],
      );
    }
    f.bundleStore.drain(beta.runtimeBundleCid, bundleControl);
    for (const member of f.members) {
      const retainedState = f.state(member);
      assert.deepEqual(retainedState.slice(1), ['2', '1']);
      await assert.rejects(
        f.bundleStore.reclaim(member.runtimeBundleCid, bundleControl),
        {code: 'MoonBitHostFailure'},
      );
      assert.deepEqual(f.state(member), retainedState);
    }
    assert.equal(await firstRuntime.release(first), true);
    assert.equal(await firstRuntime.release(first), false);
    assert.deepEqual(f.effects.closes, ['local-alpha']);
    await assert.rejects(readFile(f.outputPath(alpha)), {code: 'ENOENT'});
    assert.equal(await readFile(f.outputPath(beta), 'utf8'), '[14,21]\n');
    assert.deepEqual(control.status(firstRecord), [3, 2, 2, 0, 0]);
    assert.deepEqual(control.status(secondRecord), [3, 2, 0, 1, 0]);
    assert.deepEqual(runtime.siteControl.status(alpha.selectedSite).slice(2, 9),
      [0n, 0n, 0n, 0n, 0n, 0n, 0n]);
    assert.deepEqual(runtime.siteControl.status(beta.selectedSite).slice(2, 9),
      [0n, 0n, 1n, 0n, 8n, 0n, 0n]);
    await f.bundleStore.reclaim(alpha.runtimeBundleCid, bundleControl);
    assert.deepEqual(f.state(alpha).slice(1), ['3', '0']);
    assert.deepEqual(await readFile(alpha.installed.artifactPath), f.bytes);
    await f.bundleStore.verify(beta.runtimeBundleCid, bundleControl);
    assert.equal(await secondRuntime.release(second), true);
    assert.deepEqual(f.effects.closes, ['local-alpha', 'local-beta']);
    await assert.rejects(readFile(f.outputPath(beta)), {code: 'ENOENT'});
    assert.deepEqual(control.status(secondRecord), [3, 2, 2, 0, 0]);
    await f.bundleStore.reclaim(beta.runtimeBundleCid, bundleControl);
    assert.deepEqual(f.state(beta).slice(1), ['3', '0']);
    await assert.rejects(readFile(beta.installed.artifactPath), {code: 'ENOENT'});
    for (const member of f.members) {
      assert.deepEqual(
        runtime.siteControl.status(member.selectedSite).slice(2, 9),
        [0n, 0n, 0n, 0n, 0n, 0n, 0n],
      );
    }
  });

test('installed member tuples and scoped capabilities reject substitution before effects',
  async t => {
    const f = await fixture(t);
    const remotes = new Map();
    for (const member of f.members) {
      const other = f.members.find(value => value !== member);
      f.activate(member);
      const loadsBefore = [...f.effects.loads];
      for (const overrides of [
        {connectorRegistration: 'unlisted-member'},
        {connectorRegistration: other.connectorRegistration},
        {connectorRevision: other.connectorRevision},
        {strategyRevision: other.strategyRevision},
      ]) {
        await assert.rejects(f.register(member, overrides),
          {code: 'RemoteRuntimeBundleRegistrationMismatch'});
        assert.deepEqual(f.effects.loads, loadsBefore);
      }
      await assert.rejects(f.register(member, {
        runtimeBundleCid: other.runtimeBundleCid,
      }), {code: 'RemoteRuntimeBundleNotActive'});
      assert.deepEqual(f.effects.loads, loadsBefore);
      remotes.set(member, f.createRuntime(member, await f.register(member)));
    }
    for (const member of f.members) {
      const other = f.members.find(value => value !== member);
      const remote = remotes.get(member);
      f.activate(member);
      assert.equal(remote.supports(f.request(member)), true);
      for (const [index, overrides] of [
        {connectorRegistration: 'unlisted-member'},
        {connectorRegistration: other.connectorRegistration},
        {connectorRevision: other.connectorRevision},
        {strategyRevision: other.strategyRevision},
        {runtimeBundleCid: other.runtimeBundleCid},
        {siteKey: other.siteKey},
        {grantCid: other.operationCapabilityCid},
        {evidenceIssuerCapabilityCid: other.issuerCapabilityCid},
      ].entries()) {
        const dispatch = f.request(member, {
          ...overrides,
          dispatchId: `${member.connectorRegistration}-refused-${index}`,
        });
        assert.equal(remote.supports(dispatch), false);
        assert.throws(
          () => remote.start(dispatch, undefined, undefined, inputBindingBody),
          {code: 'RemoteRuntimeUnsupported'},
        );
        assert.equal(member.store.inspect(dispatch, control), undefined);
      }
    }
    assert.deepEqual(f.effects, {
      loads: ['local-alpha', 'local-beta'],
      providers: [],
      secrets: [],
      closes: [],
    });
    for (const member of f.members) {
      assert.equal(f.state(member)[2], '0');
      await assert.rejects(readFile(f.outputPath(member)), {code: 'ENOENT'});
    }
  });
