// Checkout-only actual GCS child/capture receiver and a fresh real FD. Prepare
// the selected normal Common target before importing it; historical whole-file
// digests do not identify a current runtime after other Common changes.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync, readFileSync} from 'node:fs';
import {open, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath, pathToFileURL} from 'node:url';
import * as moon from '../../../../_build/js/release/build/connectors/gcs/host_node/host_node.js';
import {runtimeCore} from '../../../host-common/runtime-core.mjs';
import {prepareInstalledRowCaptureChild, releaseInstalledRowCapture} from '../../../host-node/installed-row-capture-cleanup.mjs';
import {createOwnedScratch} from '../../../../scripts/owned-scratch.mjs';
import {createGcsMutationRequestChild, prepareGcsObjectBinding} from '../site/gcs-owned-object-request.mjs';

const root = fileURLToPath(new URL('../../../../', import.meta.url));
const cid = c => `sha256:${c.repeat(64)}`;
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
async function prepareCurrentCommon(t) {
  const artifact = join(root, '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
  const moon = process.env.MOON_HOME ? join(process.env.MOON_HOME, 'bin/moon') : 'moon';
  const recipe = ['build', '--target', 'js', '--release', '-j', '1', 'src/connectors_builtin_node'];
  // This is a conservative tracked-source correspondence, not a claim that
  // every listed file was read by the compiler or a new compiler trust proof.
  const inputs = () => {
    const paths = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard',
      '-z', '--', 'src', 'moon.mod', 'moon.mod.lock'], {cwd: root}).toString().split('\0').filter(Boolean).sort();
    assert(paths.includes('moon.mod') && paths.includes('src/run_publication/cleanup_progress.mbt'));
    const members = paths.map(path => [path, digest(readFileSync(join(root, path)))]);
    return {count: members.length, sha256: digest(JSON.stringify(members))};
  };
  const before = inputs();
  const toolchain = execFileSync(moon, ['version', '--all'], {cwd: root, encoding: 'utf8', timeout: 30000});
  const source = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim();
  execFileSync(moon, recipe, {cwd: root, stdio: 'inherit', timeout: 30000});
  assert.deepEqual(inputs(), before, 'compiler inputs must not change during normal preparation');
  assert.equal(execFileSync(moon, ['version', '--all'], {cwd: root, encoding: 'utf8', timeout: 30000}), toolchain);
  assert(lstatSync(artifact).isFile(), 'normal Common output must be a regular file');
  const bytes = readFileSync(artifact);
  const sha256 = digest(bytes);
  t.diagnostic(JSON.stringify({source, recipe, toolchain, inputs: before,
    artifact: {path: artifact, bytes: bytes.length, sha256},
    qualification: 'Selected normal checkout build; not installed/Provider/funding acceptance'}));
  t.after(() => {
    assert.deepEqual(inputs(), before, 'source correspondence must survive the real-FD case');
    assert.equal(digest(readFileSync(artifact)), sha256, 'the imported Common artifact must remain unchanged');
  });
  // Import only after normal preparation. Never let an earlier static import
  // cache a retained historical runtime from the ordinary output pathname.
  return import(`${pathToFileURL(artifact).href}?sha256=${sha256}`);
}
test('actual Common capture cleanup retains GCS original FD child before every parent until same close', async t => {
  const law = 'src/run_publication/cleanup_progress.mbt';
  assert.deepEqual(readFileSync(join(root, law)), execFileSync('git',
    ['show', `3dd85f9c70410f96f75efe532d00d010884e2631:${law}`], {cwd: root}));
  const common = await prepareCurrentCommon(t);
  const scratch = await createOwnedScratch({parent: join(root, '_build'),
    prefix: 'gcs-capture-child-', label: 'Actual GCS child/Common cleanup FD'});
  const path = join(scratch.path, 'original-read');await writeFile(path, 'original retained metadata');
  const fd = await open(path);let pending = true, allowClose = false, reads = 0;
  const events = [];
  t.after(async () => {await fd.close();scratch.passed();});
  const handle = Object.freeze({status: () => ({pending}), async retry() {
    assert.equal(this, handle);events.push('same-fd-close');
    if (!allowClose) return false;
    await fd.close();pending = false;
  }});
  const primary = Object.freeze(Object.assign(new Error('OriginalGcsReadFailed'),
    {cleanupHandle: handle, cleanupPending: false}));
  const scope = {issuerAuthority: 'fixture', principal: 'operator', namespaceId: 'fixture',
    environment: 'test', siteKey: 'site', siteGeneration: 1, runtimeBundleCid: cid('a'),
    connectorRegistration: 'gcs', connectorRevision: 'gcs/0.1', resourceOrigin: 'https://storage.googleapis.com',
    operation: 'gcs:file:read', runInvocationCid: cid('b'), taskAttempt: 1, dispatchRequestCid: cid('c')};
  const child = createGcsMutationRequestChild({moon, binding: prepareGcsObjectBinding(moon, {
    kind: 'patch_metadata', bucket: 'bucket', prefix: 'in/', catalogCid: cid('a'),
    installationCid: cid('b'), contractCid: cid('c'), permissions: ['storage.objects.update'],
    metadata: {maxBytes: 8192, maxNodes: 1000, maxDepth: 12, maxEntries: 16},
    maxPathBytes: 4096, maxBodyBytes: 8192, maxIdentityBytes: 16384}),
  kind: 'patch_metadata', name: 'in/a', value: {metadata: {}}, marker: cid('d'),
  maxRequestBytes: 4096, maxProjectionBytes: 8192, maxSecretBytes: 128,
  credential: {control: {identity: () => cid('a')}, journal: {claim() {}, authorize() {}, finish() {}},
    resolveSecret: async () => 'test-only'}, authorizationForRow: async () => ({scope, grant: {}, useId: 'original-read'}),
  assertCurrent() {}, callResource: async () => {reads++;throw primary;}});
  const children = [];
  await assert.rejects(prepareInstalledRowCaptureChild({children, create: () => child}), error => error === primary);
  assert.equal(children.length, 1);assert.equal(reads, 1);
  let sourcePending = true, outer;
  const source = {prepared: {status: () => ({pending: sourcePending}),
    async release() {events.push('source');sourcePending = false;},
    async retry() {events.push('source');sourcePending = false;}}};
  await assert.rejects(releaseInstalledRowCapture({children, payloads: [source],
    control: runtimeCore(common).publicationControl,
    releaseInputs() {events.push('inputs');}, releaseResults() {events.push('results');}}, primary), error => {
    outer = error;return error.primaryFailure === primary && error.cleanupPending === true;
  });
  await fd.stat();assert.equal(sourcePending, true);
  assert(events.every(event => event === 'same-fd-close'));
  const closedBefore = events.length;allowClose = true;
  assert.equal((await outer.cleanupHandle.retry()).pending, false);
  await assert.rejects(fd.stat(), {code: 'EBADF'});
  assert.deepEqual(events.slice(closedBefore), ['same-fd-close', 'inputs', 'results', 'source']);
  assert.equal(reads, 1);assert.equal(child.status().pending, false);
  assert.equal(children[0].prepared.status().pending, false);
});
