// Independently authored transport/cold-byte fixtures. They are not real
// archives, a normal producer, install acceptance or owner approval.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {releaseVersion} from './release-version.mjs';
import {observeReleaseSet} from './release-registry.mjs';
import {runRelease} from './release.mjs';

const sha = body => createHash('sha256').update(body).digest('hex');
const wire = body => Buffer.from(JSON.stringify(body));

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-release-http-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const source = 'a'.repeat(40), version = '0.0.7-rc.1';
  const payloads = [Buffer.from('Independent npm transport bytes\n'), Buffer.from('Independent wheel transport bytes\n')];
  const names = ['@actql/node', 'actql-sdk'];
  const files = ['actql-node-0.0.7-rc.1.tgz', 'actql_sdk-0.0.7rc1-py3-none-any.whl'];
  const targets = [{id: 'node', ecosystem: 'npm', packages: [names[0]], platforms: ['darwin-arm64'],
    profiles: ['local'], destination: 'https://registry.npmjs.org/', channels: ['candidate-synthetic']},
  {id: 'python', ecosystem: 'pypi', packages: [names[1]], platforms: ['darwin-arm64'],
    profiles: ['remote'], destination: 'https://upload.pypi.org/legacy/', channels: []}];
  const artifacts = targets.map((target, index) => ({targetId: target.id, ecosystem: target.ecosystem,
    name: names[index], version: index === 0 ? version : '0.0.7rc1', file: files[index],
    bytes: payloads[index].length, sha256: sha(payloads[index]), path: `${target.id}/${files[index]}`,
    ...(index === 0 ? {integrity: `sha512-${createHash('sha512').update(payloads[index]).digest('base64')}`} : {})}));
  const cohorts = [];
  for (const [index, target] of targets.entries()) {
    await mkdir(join(directory, target.id));
    const artifact = artifacts[index];
    await writeFile(join(directory, artifact.path), payloads[index]);
    const child = index === 0 ? {version: 'actql-package-release/0.1', sourceSha: source,
      cohort: {packageVersion: version, registry: target.destination, tag: 'candidate-synthetic'},
      packages: [{name: artifact.name, version: artifact.version, file: artifact.file,
        bytes: artifact.bytes, sha256: artifact.sha256, integrity: artifact.integrity}]}
      : {source_sha: source, package_version: artifact.version, platform: 'darwin-arm64',
        wheels: [{distribution: artifact.name, file: artifact.file, bytes: artifact.bytes, sha256: artifact.sha256}]};
    const bytes = wire(child), file = index === 0 ? 'release.json' : 'cohort.json';
    await writeFile(join(directory, target.id, file), bytes);
    cohorts.push({targetId: target.id, kind: index === 0 ? 'node-npm' : 'python-wheels',
      path: `${target.id}/${file}`, bytes: bytes.length, sha256: sha(bytes),
      verification: 'Independent cold-byte transport fixture only; no complete producer or install qualification'});
  }
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'synthetic-http-only', version,
    source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'}, targets,
    notes: {summary: 'Transport fixture, not a release candidate', breakingChanges: [], migration: [], knownLimitations: ['No engine or archive']}};
  const manifest = {schemaVersion: 'actql-release-set/0.1', release: releaseVersion(version), request,
    policy: {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'], publicationAuthority: 'external-owner-approval-required'},
    cohorts, artifacts, acceptance: 'unaccepted', qualification: 'Independent observer transport fixture'};
  const bytes = wire(manifest), digest = sha(bytes);
  await writeFile(join(directory, 'release-set.json'), bytes);
  await writeFile(join(directory, 'release-set.sha256'), `${digest}  release-set.json\n`);
  const urls = ['https://registry.npmjs.org/%40actql%2Fnode/0.0.7-rc.1',
    'https://registry.npmjs.org/@actql/node/-/node-0.0.7-rc.1.tgz',
    'https://pypi.org/pypi/actql-sdk/0.0.7rc1/json',
    `https://files.pythonhosted.org/packages/aa/${files[1]}`];
  const npm = {name: names[0], version, dist: {integrity: artifacts[0].integrity, tarball: urls[1]}};
  const python = {info: {name: names[1], version: '0.0.7rc1'}, urls: [{filename: files[1],
    digests: {sha256: artifacts[1].sha256}, size: artifacts[1].bytes, packagetype: 'bdist_wheel',
    yanked: false, url: urls[3]}]};
  const routes = new Map([[urls[0], () => Response.json(npm)], [urls[1], () => new Response(payloads[0])],
    [urls[2], () => Response.json(python)], [urls[3], () => new Response(payloads[1])]]);
  const calls = [];
  const fetchResponse = async (url, options) => {
    calls.push({url, options});
    assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit');
    assert.equal(options.redirect, 'error'); assert(options.signal instanceof AbortSignal);
    assert.equal(Object.hasOwn(options.headers, 'authorization'), false);
    assert.equal(Object.hasOwn(options, 'body'), false);
    assert(routes.has(url), `Unexpected or foreign request: ${url}`);
    return routes.get(url)();
  };
  return {directory, digest, artifacts, payloads, urls, npm, python, routes, calls, fetchResponse,
    observe: () => observeReleaseSet(directory, digest, {fetchResponse})};
}

test('registry observation: actual npm identity owner and bounded remote bytes feed same-bytes resume without writing the fixed set', async t => {
  const f = await fixture(t), before = await readFile(join(f.directory, 'release-set.json'));
  const result = await f.observe();
  assert.deepEqual(result.plan.plan.map(item => item.action), ['reuse-identical', 'reuse-identical']);
  assert.equal(result.plan.blocked, false); assert.equal(result.issues.length, 0);
  assert.equal(result.requests.length, 4);
  assert.deepEqual(result.requests.filter(item => item.url === f.urls[1] || item.url === f.urls[3]).map(item => item.sha256),
    f.artifacts.map(item => item.sha256));
  assert.deepEqual(await readFile(join(f.directory, 'release-set.json')), before);
});

test('registry observation: only original version metadata 404 is absence and no binary is requested', async t => {
  const f = await fixture(t);
  for (const url of [f.urls[0], f.urls[2]]) f.routes.set(url, () => new Response('', {status: 404}));
  const result = await f.observe();
  assert.deepEqual(result.plan.plan.map(item => item.action), ['missing-same-bytes', 'missing-same-bytes']);
  assert.equal(result.plan.blocked, false); assert.equal(f.calls.length, 2);
});

test('registry observation: metadata HTTP failure and timeout are unknown, never missing or permission to send', async t => {
  const f = await fixture(t);
  f.routes.set(f.urls[0], () => new Response('unavailable', {status: 503}));
  f.routes.set(f.urls[2], () => {throw new Error('Own request timed out');});
  const result = await f.observe();
  assert.deepEqual(result.plan.plan.map(item => item.action), ['stop-unknown', 'stop-unknown']);
  assert.equal(result.plan.blocked, true); assert.equal(f.calls.length, 2);
});

test('registry observation: occupied npm integrity mismatch remains a conflict at the existing identity owner', async t => {
  const f = await fixture(t); f.npm.dist.integrity = 'sha512-foreign';
  const result = await f.observe();
  assert.equal(result.observations[0].state, 'conflict');
  assert.equal(result.plan.plan[0].action, 'stop-conflict'); assert.equal(result.plan.blocked, true);
  assert.equal(f.calls.some(item => item.url === f.urls[1]), false);
});

test('registry observation: published binary bytes cannot inherit matching metadata with another digest', async t => {
  const f = await fixture(t);
  f.routes.set(f.urls[1], () => new Response(Buffer.alloc(f.artifacts[0].bytes, 65)));
  const result = await f.observe();
  assert.equal(result.observations[0].state, 'conflict'); assert.equal(result.plan.blocked, true);
  assert.match(result.issues[0].reason, /different sha256/u);
});

test('registry observation: missing artifact after positive version metadata stays unknown rather than absent', async t => {
  const f = await fixture(t); f.routes.set(f.urls[1], () => new Response('', {status: 404}));
  const result = await f.observe();
  assert.equal(result.observations[0].state, 'unknown');
  assert.equal(result.plan.plan[0].action, 'stop-unknown'); assert.equal(result.plan.blocked, true);
});

test('registry observation: old foreign or empty PyPI releases cannot acquire a new platform/product by append', async t => {
  const f = await fixture(t);
  for (const records of [[{...f.python.urls[0], filename: 'old-placeholder.whl'}], []]) {
    f.python.urls = records;
    const result = await f.observe();
    assert.equal(result.observations[1].state, 'conflict'); assert.equal(result.plan.blocked, true);
  }
});

test('registry observation: PyPI filename digest size and yanked facts are exact while standard project-name normalization is retained', async t => {
  const f = await fixture(t); f.python.info.name = 'ActQL_SDK';
  assert.equal((await f.observe()).observations[1].state, 'present');
  const original = structuredClone(f.python.urls[0]);
  for (const change of [{digests: {sha256: 'a'.repeat(64)}}, {size: original.size + 1}, {yanked: true}]) {
    f.python.urls[0] = {...original, ...change};
    assert.equal((await f.observe()).observations[1].state, 'conflict');
  }
});

test('registry observation: registry download origin redirects and credential-bearing URLs are not followed', async t => {
  const f = await fixture(t);
  f.npm.dist.tarball = 'https://other.invalid/foreign.tgz';
  f.python.urls[0].url = 'https://owner:secret@files.pythonhosted.org/private.whl';
  const result = await f.observe();
  assert.deepEqual(result.observations.map(item => item.state), ['unknown', 'unknown']);
  assert.equal(f.calls.length, 2); assert.equal(result.plan.blocked, true);
  f.routes.set(f.urls[0], () => new Response('', {status: 302, headers: {location: f.urls[1]}}));
  assert.equal((await f.observe()).observations[0].state, 'unknown');
});

test('registry observation: interrupted streams stay unknown and excess artifact bytes are a bounded conflict', async t => {
  const f = await fixture(t);
  f.routes.set(f.urls[1], () => new Response(new ReadableStream({start(controller) {controller.error(new Error('Interrupted own GET'));}})));
  assert.equal((await f.observe()).observations[0].state, 'unknown');
  let cancelled = false;
  f.routes.set(f.urls[1], () => new Response(new ReadableStream({
    start(controller) {controller.enqueue(Buffer.alloc(f.artifacts[0].bytes + 1));}, cancel() {cancelled = true;},
  })));
  assert.equal((await f.observe()).observations[0].state, 'conflict');
  assert.equal(cancelled, true);
});

test('registry observation: malformed oversized or non-UTF8 registry metadata cannot supply absence', async t => {
  const f = await fixture(t);
  for (const bytes of [Buffer.from('{'), Buffer.alloc(4 * 1024 * 1024 + 1, 32), Buffer.from([0xff])]) {
    f.routes.set(f.urls[0], () => new Response(bytes));
    const result = await f.observe();
    assert.equal(result.observations[0].state, 'unknown'); assert.equal(result.plan.blocked, true);
  }
});

test('registry observation: a local fixed artifact change during registry observation invalidates the complete result', async t => {
  const f = await fixture(t);
  f.routes.set(f.urls[0], async () => {
    await writeFile(join(f.directory, f.artifacts[0].path), 'Changed local artifact');
    return Response.json(f.npm);
  });
  await assert.rejects(f.observe());
});

test('registry observation: CLI observe validates exact original manifest before any anonymous network request', async t => {
  const f = await fixture(t), calls = [];
  t.mock.method(globalThis, 'fetch', async (...args) => {calls.push(args); throw new Error('Unexpected network');});
  await assert.rejects(runRelease(['observe', f.directory, 'a'.repeat(64)]), /externally retained digest/u);
  await assert.rejects(runRelease(['observe', f.directory]), /usage/u);
  assert.deepEqual(calls, []);
});

test('registry observation: positive public CLI dispatch composes exact fixed bytes and anonymous GET classification', async t => {
  const f = await fixture(t);
  t.mock.method(globalThis, 'fetch', f.fetchResponse);
  const result = await runRelease(['observe', f.directory, f.digest]);
  assert.equal(result.manifestSha256, f.digest);
  assert.deepEqual(result.plan.plan.map(item => item.action), ['reuse-identical', 'reuse-identical']);
  assert.equal(f.calls.length, 4);
  assert.equal(result.plan.blocked, false);
});
