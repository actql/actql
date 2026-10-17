// Real installed-source selection/callback and matching Common DATA; no Site,
// Account grant, key, journal claim, Provider I/O or numerical funding fixture.
import assert from 'node:assert/strict';
import {mkdtemp, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';
import test from 'node:test';
import {createInstalledConnectorTable} from './installed-connectors.mjs';
import {publishInstalledSourceProfile, installedSourcePublicationRequestId,
  assertInstalledSourcePublicationRequest, observeInstalledSourcePublicationCurrent}
  from './installed-source.mjs';
import {runtimeCore} from '../host-common/runtime-core.mjs';

assert(process.env.ACTQL_METADATA_COMMON_RUNTIME,
  'Select an actual matching retained Common runtime explicitly');
const runtimeUrl = pathToFileURL(process.env.ACTQL_METADATA_COMMON_RUNTIME);
const moon = await import(runtimeUrl.href);
const version = 'actql-installed-publication-original-source/0.1';
const cid = digit => 'sha256:' + digit.repeat(64);
const foreign = {code: 'ForeignInstalledSourcePublication'};
const mismatched = {code: 'ForeignInstalledSourcePublicationBinding'};
const closed = {code: 'InstalledSourcePublicationClosed'};
const fence = ({publicationRequest, ...options}, profile) => ({
  request: publicationRequest, originals: {...options, profile},
});

async function fixture(t, publish, {check, sourcePublish = true, signal} = {}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-publication-original-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const path = join(root, 'profile.json');
  const input = {version, connection: 'notion', generation: 1};
  await writeFile(path, JSON.stringify(input));
  let publishes = 0, secrets = 0;
  const module = {check: check ?? (profile => Object.freeze({...profile})),
    identityParts: () => {assert.fail('Publication does not rediscover identity');},
    load: () => {assert.fail('Publication does not load a query Source');},
    ...(sourcePublish ? {async publish(profile, options) {
      publishes++;
      return publish(profile, options);
    }} : {})};
  const connectorTable = createInstalledConnectorTable([{name: 'notion',
    registration: 'notion', revision: 'notion/0.1', source: {profileVersion: version,
      load: async () => module}}]);
  const options = {root, principalId: 'original-actor', moon, runtimeUrl,
    connectorTable, signal, resolveSecret() {secrets++; assert.fail('No secret I/O');}};
  return {root, path, input, options, module,
    run: () => publishInstalledSourceProfile(path, options),
    counters: () => ({publishes, secrets})};
}

test('publication actual selected callback binds the same request to Common metadata DATA', async t => {
  let original;
  const f = await fixture(t, async (profile, options) => {
    original = fence(options, profile);
    assertInstalledSourcePublicationRequest(original.request, original.originals);
    await observeInstalledSourcePublicationCurrent(original.request, original.originals);
    const requestId = installedSourcePublicationRequestId(original.request);
    assert.match(requestId, /^[0-9a-f-]{36}$/u);
    const view = runtimeCore(options.moon).installationPreparationMetadata();
    const subject = view.prepareSubject({accountConfigurationCid: cid('a'),
      accountId: 'explicit-fixture-account', connection: profile.connection,
      connectorRegistration: options.installation.registration,
      connectorRevision: options.installation.revision,
      declarationSourceCid: cid('b'), installationRequestId: requestId,
      principal: options.principalId, runtimeBundleCid: options.runtimeBundleCid,
      siteGeneration: 1, siteKey: 'explicit-fixture-site'});
    assert.equal(view.subjectFields(subject).installationRequestId, requestId);
    const control = view.forSubject(subject);
    assert.equal(control.subject, subject);
    assert.equal(control.kind, 'installation-metadata');
    view.retireMetadataView();
    return Object.freeze({published: 'original'});
  });
  assert.deepEqual(await f.run(), {published: 'original'});
  assert.deepEqual(f.counters(), {publishes: 1, secrets: 0});
  assert.throws(() => installedSourcePublicationRequestId(original.request), foreign);
  assert.throws(() => assertInstalledSourcePublicationRequest(original.request, original.originals), foreign);
});

test('publication copied request or mixed original installation references refuse synchronously', async t => {
  const f = await fixture(t, (profile, options) => {
    const {request, originals} = fence(options, profile);
    for (const copy of [{...request}, Object.create(request), null, 'request-id']) {
      assert.throws(() => assertInstalledSourcePublicationRequest(copy, originals), foreign);
    }
    for (const key of ['root', 'principalId', 'moon', 'installation', 'profile',
      'resolveSecret', 'runtimeBundleCid']) {
      const replacement = typeof originals[key] === 'string' ? originals[key] + '-other'
        : typeof originals[key] === 'function' ? () => {} : {...originals[key]};
      assert.throws(() => assertInstalledSourcePublicationRequest(request,
        {...originals, [key]: replacement}), mismatched);
    }
    assertInstalledSourcePublicationRequest(request, originals);
  });
  await f.run();
});

test('publication pair checking snapshots own descriptors without invoking substitute getters', async t => {
  const f = await fixture(t, (profile, options) => {
    const {request, originals} = fence(options, profile);
    const substitute = {...originals};
    Object.defineProperty(substitute, 'profile', {get() {assert.fail('No getter');}});
    assert.throws(() => assertInstalledSourcePublicationRequest(request, substitute), mismatched);
    const inherited = Object.create(originals);
    assert.throws(() => assertInstalledSourcePublicationRequest(request, inherited), mismatched);
  });
  await f.run();
});

test('publication checked profile remains its original pair instead of an equal rechecked copy', async t => {
  const f = await fixture(t, (profile, options) => {
    const {request, originals} = fence(options, profile);
    const equal = f.module.check(profile);
    assert.notEqual(equal, profile);
    assert.throws(() => assertInstalledSourcePublicationRequest(request,
      {...originals, profile: equal}), mismatched);
    assertInstalledSourcePublicationRequest(request, originals);
  });
  await f.run();
});

test('publication equal configuration and runtime do not replace another original request', async t => {
  let first;
  const f = await fixture(t, async (profile, options) => {
    const original = fence(options, profile);
    if (first === undefined) {
      first = original;
      await f.run();
      assertInstalledSourcePublicationRequest(first.request, first.originals);
    } else {
      assert.notEqual(installedSourcePublicationRequestId(first.request),
        installedSourcePublicationRequestId(original.request));
      assert.throws(() => assertInstalledSourcePublicationRequest(original.request,
        first.originals), mismatched);
      assert.throws(() => assertInstalledSourcePublicationRequest(first.request,
        original.originals), mismatched);
    }
  });
  await f.run();
  assert.equal(f.counters().publishes, 2);
});

test('publication observed profile replacement closes admission without reconstructing an original', async t => {
  const f = await fixture(t, async (profile, options) => {
    const {request, originals} = fence(options, profile);
    await observeInstalledSourcePublicationCurrent(request, originals);
    await writeFile(f.path, JSON.stringify({...f.input, generation: 2}));
    await assert.rejects(observeInstalledSourcePublicationCurrent(request, originals),
      {code: 'InstalledSourcePublicationChanged'});
    await writeFile(f.path, JSON.stringify(f.input));
    assert.throws(() => assertInstalledSourcePublicationRequest(request, originals), closed);
    throw Object.assign(new Error('OriginalPublicationStopped'), {code: 'OriginalPublicationStopped'});
  });
  await assert.rejects(f.run(), {code: 'OriginalPublicationStopped'});
  assert.equal(f.counters().publishes, 1);
});

test('publication missing original profile remains failed rather than authorizing equal later data', async t => {
  const f = await fixture(t, async (profile, options) => {
    const {request, originals} = fence(options, profile);
    await rm(f.path);
    await assert.rejects(observeInstalledSourcePublicationCurrent(request, originals),
      {code: 'InvalidInstalledSourceProfile'});
    await writeFile(f.path, JSON.stringify(f.input));
    assert.throws(() => assertInstalledSourcePublicationRequest(request, originals), closed);
    throw new Error('OriginalProfileUnavailable');
  });
  await assert.rejects(f.run(), {message: 'OriginalProfileUnavailable'});
});

test('publication abort before callback performs no new publication or secret operation', async t => {
  const controller = new AbortController(), reason = new Error('OriginalAbort');
  controller.abort(reason);
  const f = await fixture(t, () => assert.fail('No publication'), {signal: controller.signal});
  await assert.rejects(f.run(), error => error === reason);
  assert.deepEqual(f.counters(), {publishes: 0, secrets: 0});
});

test('publication abort after an await refuses the same original pair', async t => {
  const controller = new AbortController(), reason = new Error('OriginalAbort');
  const f = await fixture(t, async (profile, options) => {
    const {request, originals} = fence(options, profile);
    assertInstalledSourcePublicationRequest(request, originals);
    await Promise.resolve(); controller.abort(reason);
    assert.throws(() => assertInstalledSourcePublicationRequest(request, originals), error => error === reason);
    throw reason;
  }, {signal: controller.signal});
  await assert.rejects(f.run(), error => error === reason);
  assert.deepEqual(f.counters(), {publishes: 1, secrets: 0});
});

test('publication failed physical cleanup holds the request but never reopens send admission', async t => {
  let original, allowClose = false, retries = 0, reads = 0;
  const cleanup = {status() {assert.equal(this, cleanup); return {pending: !allowClose};},
    retry() {assert.equal(this, cleanup); retries++;}};
  const primary = Object.assign(new Error('OriginalUnknown'), {
    code: 'OriginalUnknown', cleanupPending: true,
  });
  Object.defineProperty(primary, 'cleanupHandle', {get() {reads++; return cleanup;}});
  Object.freeze(primary);
  const f = await fixture(t, (profile, options) => {
    original = fence(options, profile);
    assertInstalledSourcePublicationRequest(original.request, original.originals);
    throw primary;
  });
  let failure;
  await assert.rejects(f.run(), error => {failure = error; return error.primaryFailure === primary;});
  assert.equal(reads, 1); assert.equal(retries, 0);
  const requestId = installedSourcePublicationRequestId(original.request);
  assert.throws(() => assertInstalledSourcePublicationRequest(original.request, original.originals), closed);
  cleanup.status = () => ({pending: false}); cleanup.retry = () => assert.fail('Original callback only');
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, true);
  assert.equal(installedSourcePublicationRequestId(original.request), requestId);
  allowClose = true;
  await failure.cleanupHandle.retry();
  assert.equal(failure.cleanupHandle.status().pending, false);
  // The same original status already acknowledges closure. Do not retry an
  // acknowledged child merely to retire the parent's reference.
  assert.equal(retries, 1); assert.equal(reads, 1);
  assert.throws(() => installedSourcePublicationRequestId(original.request), foreign);
  assert.equal(f.counters().publishes, 1);
});

test('publication cleanup without an original status cannot retire or manufacture an ACK', async t => {
  let original;
  const primary = Object.freeze(Object.assign(new Error('UnknownCleanup'), {
    cleanupPending: true, cleanupHandle: Object.freeze({retry() {assert.fail('No status');}}),
  }));
  const f = await fixture(t, (profile, options) => {original = fence(options, profile); throw primary;});
  let failure;
  await assert.rejects(f.run(), error => {failure = error; return error.primaryFailure === primary;});
  assert.equal(failure.cleanupHandle.status().pending, true);
  await assert.rejects(failure.cleanupHandle.retry(), error => error === failure);
  assert.match(installedSourcePublicationRequestId(original.request), /^[0-9a-f-]{36}$/u);
  assert.throws(() => assertInstalledSourcePublicationRequest(original.request, original.originals), closed);
});

test('publication final observed replacement refuses without a replacement publication call', async t => {
  const f = await fixture(t, async (profile, options) => {
    const {request, originals} = fence(options, profile);
    assertInstalledSourcePublicationRequest(request, originals);
    await writeFile(f.path, JSON.stringify({...f.input, generation: 2}));
    return {fixtureOnly: true};
  });
  await assert.rejects(f.run(), {code: 'InstalledSourcePublicationChanged'});
  assert.equal(f.counters().publishes, 1);
});

test('publication unused legacy seam retains old absence behavior with no post-call profile probe', async t => {
  const f = await fixture(t, async () => {await rm(f.path); return 'legacy';});
  assert.equal(await f.run(), 'legacy');
  assert.deepEqual(f.counters(), {publishes: 1, secrets: 0});
});

test('publication unsupported installation refuses before a request can escape', async t => {
  const f = await fixture(t, () => assert.fail('No publisher'), {sourcePublish: false});
  await assert.rejects(f.run(), {code: 'InstalledSourcePublicationUnsupported'});
  assert.deepEqual(f.counters(), {publishes: 0, secrets: 0});
});
