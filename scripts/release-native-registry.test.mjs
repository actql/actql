// Independent cold-byte HTTP fixtures only. No real Native archive, GitHub
// release, authenticated draft, publisher or public install is exercised.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {releaseVersion} from './release-version.mjs';
import {observeReleaseSet} from './release-registry.mjs';
import {runRelease} from './release.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const wire = value => Buffer.from(JSON.stringify(value));
const api = 'https://api.github.com/repos/actql/actql';

async function fixture(t, {version = '0.0.7-rc.1', platforms = ['darwin-arm64']} = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'actql-native-release-http-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const source = 'a'.repeat(40), tag = `v${version}`;
  const payloads = platforms.map(platform => Buffer.from(`Independent inert Native HTTP bytes for ${platform}\n`));
  const files = platforms.map(platform => `actql-${version}-${platform}.tar.gz`);
  payloads.push(Buffer.from('Independent checksum HTTP bytes, not a complete packaging fixture\n')); files.push('SHA256SUMS');
  const names = [...platforms.map(platform => `actql-${platform}`), 'actql-checksums'];
  const target = {id: 'native', ecosystem: 'native', packages: names, platforms,
    profiles: ['remote'], destination: 'https://github.com/actql/actql', channels: ['candidate-synthetic']};
  const artifacts = files.map((file, index) => ({targetId: target.id, ecosystem: 'native', name: names[index], version, file,
    bytes: payloads[index].length, sha256: sha(payloads[index]), path: `native/${file}`}));
  await mkdir(join(directory, 'native'));
  for (const [index, artifact] of artifacts.entries()) await writeFile(join(directory, artifact.path), payloads[index]);
  const child = {schemaVersion: 'actql-native-standalone/0.1', sourceSha: source, packageVersion: version, platforms,
    requestedProfiles: ['remote'], archives: artifacts.slice(0, -1), checksums: artifacts.at(-1)};
  const childBytes = wire(child);
  await writeFile(join(directory, 'native/native-standalone.json'), childBytes);
  const manifest = {schemaVersion: 'actql-release-set/0.1', release: releaseVersion(version),
    request: {schemaVersion: 'actql-release-request/0.1', releaseId: 'synthetic-native-http-only', version,
      source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'}, targets: [target],
      notes: {summary: 'Independent HTTP fixture, not a release candidate', breakingChanges: [], migration: [], knownLimitations: ['Inert bytes']}},
    policy: {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'], publicationAuthority: 'external-owner-approval-required'},
    cohorts: [{targetId: 'native', kind: 'native-standalone', path: 'native/native-standalone.json', bytes: childBytes.length,
      sha256: sha(childBytes), verification: 'Independent HTTP bytes only; no full producer or install'}], artifacts,
    acceptance: 'unaccepted', qualification: 'Independent Native observer transport fixture'};
  const original = wire(manifest), digest = sha(original);
  await writeFile(join(directory, 'release-set.json'), original);
  await writeFile(join(directory, 'release-set.sha256'), `${digest}  release-set.json\n`);
  const releaseUrl = `${api}/releases/tags/${tag}`, refUrl = `${api}/git/ref/tags/${tag}`;
  const assetsUrl = `${api}/releases/71/assets?per_page=100&page=1`;
  const release = {id: 71, tag_name: tag, target_commitish: 'moving-branch-is-not-proof',
    draft: false, immutable: true, prerelease: version.includes('-')};
  const ref = {ref: `refs/tags/${tag}`, object: {type: 'commit', sha: source}};
  const assets = artifacts.map((artifact, index) => ({id: index + 81, name: artifact.file, state: 'uploaded',
    size: artifact.bytes, digest: `sha256:${artifact.sha256}`,
    browser_download_url: `https://github.com/actql/actql/releases/download/${tag}/${artifact.file}`}));
  const routes = new Map([[releaseUrl, () => Response.json(release)], [refUrl, () => Response.json(ref)],
    [assetsUrl, () => Response.json(assets)]]);
  for (const [index, item] of assets.entries()) routes.set(`${api}/releases/assets/${item.id}`, () => new Response(payloads[index]));
  const calls = [];
  const fetchResponse = async (url, options) => {
    calls.push({url, options});
    assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit');
    assert.equal(options.redirect, 'manual'); assert(options.signal instanceof AbortSignal);
    assert.equal(Object.hasOwn(options.headers, 'authorization'), false);
    assert.equal(Object.hasOwn(options.headers, 'cookie'), false); assert.equal(Object.hasOwn(options, 'body'), false);
    if (url.startsWith(api)) assert.equal(options.headers['x-github-api-version'], '2026-03-10');
    else assert.deepEqual(options.headers, {accept: 'application/octet-stream'});
    assert(routes.has(url), `Unexpected or foreign request: ${url}`);
    return routes.get(url)();
  };
  return {directory, digest, original, source, tag, artifacts, payloads, release, ref, assets, routes, calls,
    releaseUrl, refUrl, assetsUrl, fetchResponse, observe: () => observeReleaseSet(directory, digest, {fetchResponse})};
}

test('Native observation: visible immutable tag/source and actual asset bytes use one complete inventory without changing fixed bytes', async t => {
  const f = await fixture(t), result = await f.observe();
  assert.deepEqual(result.plan.plan.map(value => value.action), ['reuse-identical', 'reuse-identical']);
  assert.equal(result.plan.blocked, false); assert.deepEqual(result.issues, []);
  assert.equal(f.calls.length, 5); assert.equal(f.calls.filter(value => value.url === f.releaseUrl).length, 1);
  assert.deepEqual(result.requests.slice(-2).map(value => value.sha256), f.artifacts.map(value => value.sha256));
  assert.deepEqual(await readFile(join(f.directory, 'release-set.json')), f.original);
  const final = await fixture(t, {version: '0.0.8'});
  assert.equal((await final.observe()).plan.blocked, false);
});

test('Native observation: anonymous release 404, rate limit and malformed metadata stay unknown, never missing/send', async t => {
  const f = await fixture(t);
  for (const response of [() => new Response('', {status: 404}), () => new Response('', {status: 403}),
    () => new Response('{'), () => Response.json({...f.release, immutable: undefined})]) {
    f.routes.set(f.releaseUrl, response);
    const result = await f.observe();
    assert.deepEqual(result.observations.map(value => value.state), ['unknown', 'unknown']);
    assert(result.plan.plan.every(value => value.action === 'stop-unknown')); assert.equal(result.plan.blocked, true);
  }
  assert.equal(f.calls.length, 4); // Even the failed release context is shared within one observation.
});

test('Native observation: occupied draft, mutable, tag and prerelease mismatches cannot be adopted or repaired', async t => {
  const f = await fixture(t), original = structuredClone(f.release);
  for (const changed of [{draft: true}, {immutable: false}, {tag_name: 'v0.0.1'}, {prerelease: false}]) {
    Object.assign(f.release, original, changed);
    const result = await f.observe();
    assert(result.observations.every(value => value.state === 'conflict')); assert.equal(result.plan.blocked, true);
  }
  assert.equal(f.calls.length, 4);
});

test('Native observation: actual lightweight/annotated tag commit is required rather than target_commitish', async t => {
  const f = await fixture(t), outer = 'b'.repeat(40), inner = 'c'.repeat(40);
  f.ref.object = {type: 'tag', sha: outer};
  f.routes.set(`${api}/git/tags/${outer}`, () => Response.json({sha: outer, object: {type: 'tag', sha: inner}}));
  f.routes.set(`${api}/git/tags/${inner}`, () => Response.json({sha: inner, object: {type: 'commit', sha: f.source}}));
  assert.equal((await f.observe()).plan.blocked, false);
  f.routes.set(`${api}/git/tags/${inner}`, () => Response.json({sha: inner, object: {type: 'commit', sha: 'd'.repeat(40)}}));
  assert((await f.observe()).observations.every(value => value.state === 'conflict'));
  f.routes.set(`${api}/git/tags/${inner}`, () => Response.json({sha: inner, object: {type: 'tag', sha: outer}}));
  assert((await f.observe()).observations.every(value => value.state === 'unknown'));
});

test('Native observation: complete paginated asset inventory is required even when embedded release assets are misleading', async t => {
  const platforms = Array.from({length: 100}, (_, index) => `synthetic-os-${index}`), f = await fixture(t, {platforms});
  f.release.assets = []; // This convenience field is deliberately not the inventory owner.
  f.routes.set(f.assetsUrl, () => Response.json(f.assets.slice(0, 100)));
  f.routes.set(`${api}/releases/71/assets?per_page=100&page=2`, () => Response.json(f.assets.slice(100)));
  const result = await f.observe();
  assert.equal(result.observations.length, 101); assert.equal(result.plan.blocked, false);
  assert.equal(f.calls.filter(value => value.url.includes('/71/assets?')).length, 2);
});

test('Native observation: foreign, missing and duplicate asset inventories block before any download', async t => {
  const f = await fixture(t), original = structuredClone(f.assets);
  for (const values of [[...original, {...original[0], id: 900, name: 'old-placeholder.zip'}], [original[0]],
    [original[0], original[0]], [{...original[0], digest: `sha256:${'f'.repeat(64)}`}, original[1]]]) {
    f.routes.set(f.assetsUrl, () => Response.json(values));
    const result = await f.observe();
    assert.equal(result.plan.blocked, true);
    assert(result.observations.every(value => ['conflict', 'unknown'].includes(value.state)));
  }
  assert.equal(f.calls.some(value => /\/releases\/assets\//u.test(value.url)), false);
});

test('Native observation: optional missing API digest still requires the actual bytes and same-size corruption remains conflict', async t => {
  const f = await fixture(t); delete f.assets[0].digest;
  assert.equal((await f.observe()).plan.blocked, false);
  f.routes.set(`${api}/releases/assets/81`, () => new Response(Buffer.alloc(f.artifacts[0].bytes, 65)));
  const result = await f.observe();
  assert.equal(result.observations[0].state, 'conflict'); assert.match(result.issues[0].reason, /different sha256/u);
  assert.equal(result.plan.blocked, true);
});

test('Native observation: bounded signed public CDN redirect reads bytes but never records the signed query', async t => {
  const f = await fixture(t), signed = 'https://release-assets.githubusercontent.com/asset/81?signature=fixture-only-secret';
  f.routes.set(`${api}/releases/assets/81`, () => new Response('', {status: 302, headers: {location: signed}}));
  f.routes.set(signed, () => new Response(f.payloads[0]));
  const result = await f.observe();
  assert.equal(result.plan.blocked, false);
  assert.equal(result.requests.find(value => value.url === 'https://release-assets.githubusercontent.com/asset/81').sha256, f.artifacts[0].sha256);
  assert.equal(JSON.stringify(result).includes('fixture-only-secret'), false);
  assert.equal(f.calls.find(value => value.url === signed).options.headers.authorization, undefined);
});

test('Native observation: foreign credential/HTTP redirect origins and redirect cycles are unknown with no foreign GET', async t => {
  const f = await fixture(t);
  for (const location of ['https://other.invalid/file', 'http://release-assets.githubusercontent.com/file',
    'https://owner:secret@release-assets.githubusercontent.com/file']) {
    f.routes.set(`${api}/releases/assets/81`, () => new Response('', {status: 302, headers: {location}}));
    assert.equal((await f.observe()).observations[0].state, 'unknown');
  }
  const cycle = 'https://objects.githubusercontent.com/same?signature=fixture';
  f.routes.set(`${api}/releases/assets/81`, () => new Response('', {status: 302, headers: {location: cycle}}));
  f.routes.set(cycle, () => new Response('', {status: 302, headers: {location: cycle}}));
  assert.equal((await f.observe()).observations[0].state, 'unknown');
  assert(f.calls.every(value => value.url.startsWith(api) || value.url === cycle));
});

test('Native observation: missing or interrupted download after public metadata is unknown rather than asset absence', async t => {
  const f = await fixture(t);
  for (const response of [() => new Response('', {status: 404}),
    () => new Response(new ReadableStream({start(controller) {controller.error(new Error('Own interrupted body'));}}))]) {
    f.routes.set(`${api}/releases/assets/81`, response);
    const result = await f.observe();
    assert.equal(result.observations[0].state, 'unknown'); assert.equal(result.plan.plan[0].action, 'stop-unknown');
    assert.equal(result.plan.blocked, true);
  }
});

test('Native observation: distinct annotated-tag, inventory-page and CDN redirect bounds stop without unbounded work', async t => {
  const tagged = await fixture(t), tagShas = Array.from({length: 9}, (_, index) => (index + 1).toString(16).repeat(40));
  tagged.ref.object = {type: 'tag', sha: tagShas[0]};
  for (let index = 0; index < 8; index++) tagged.routes.set(`${api}/git/tags/${tagShas[index]}`,
    () => Response.json({sha: tagShas[index], object: {type: 'tag', sha: tagShas[index + 1]}}));
  const tagResult = await tagged.observe();
  assert(tagResult.observations.every(value => value.state === 'unknown'));
  assert.equal(tagged.calls.filter(value => value.url.includes('/git/tags/')).length, 8);
  assert.equal(tagged.calls.some(value => value.url === tagged.assetsUrl), false);

  const paged = await fixture(t);
  for (let page = 1; page <= 10; page++) paged.routes.set(`${api}/releases/71/assets?per_page=100&page=${page}`,
    () => Response.json(Array.from({length: 100}, (_, index) => ({id: page * 1000 + index + 1, name: `unselected-${page}-${index}`}))));
  const pageResult = await paged.observe();
  assert(pageResult.observations.every(value => value.state === 'unknown'));
  assert.equal(paged.calls.filter(value => value.url.includes('/71/assets?')).length, 10);
  assert.equal(paged.calls.some(value => /\/releases\/assets\//u.test(value.url)), false);

  const redirected = await fixture(t);
  redirected.routes.set(`${api}/releases/assets/81`, () => new Response('', {status: 302,
    headers: {location: 'https://release-assets.githubusercontent.com/first?signature=not-retained'}}));
  const paths = ['first', 'second', 'third', 'fourth'];
  for (let index = 0; index < 3; index++) redirected.routes.set(`https://release-assets.githubusercontent.com/${paths[index]}?signature=not-retained`,
    () => new Response('', {status: 302, headers: {location: `https://release-assets.githubusercontent.com/${paths[index + 1]}?signature=not-retained`}}));
  const redirectResult = await redirected.observe();
  assert.equal(redirectResult.observations[0].state, 'unknown');
  assert.equal(redirected.calls.filter(value => value.url.startsWith('https://release-assets.')).length, 3);
  assert.equal(JSON.stringify(redirectResult).includes('not-retained'), false);
});

test('Native observation: CLI observe uses the existing fixed-manifest route and never publishes or authenticates', async t => {
  const f = await fixture(t); t.mock.method(globalThis, 'fetch', f.fetchResponse);
  const result = await runRelease(['observe', f.directory, f.digest]);
  assert.equal(result.manifestSha256, f.digest); assert.equal(result.plan.blocked, false); assert.equal(f.calls.length, 5);
  await assert.rejects(runRelease(['publish', f.directory]), /publication authority/u);
  assert.equal(f.calls.length, 5);
});
