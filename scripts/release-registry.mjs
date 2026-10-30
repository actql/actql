// Public and explicitly supplied owner read observations are historical DATA, not
// owner approval, a publication lease, upload permission or public install.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {closeSync, fsyncSync, openSync, writeSync} from 'node:fs';
import {lstat, mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {publishedVersion, verifyPackageRelease} from './package-release.mjs';
import {nativeReleaseDraftRequest, resumeReleaseSet, verifyReleaseSet} from './release-set.mjs';

class RegistryUnavailable extends Error {}
class RegistryConflict extends Error {}
const unavailable = message => {throw new RegistryUnavailable(message);};
const conflict = message => {throw new RegistryConflict(message);};
const fields = (record, names) => Object.fromEntries(names.map(name => [name, record[name]]));
const identity = artifact => fields(artifact, ['name', 'version', 'bytes', 'sha256',
  ...(artifact.ecosystem === 'npm' ? ['integrity'] : [])]);
const normalizedName = value => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?$/u.test(value) || value !== value.trim())
    unavailable('Malformed PyPI project name');
  return value.toLowerCase().replace(/[-_.]+/gu, '-');
};

function publicUrl(value, origin) {
  if (typeof value !== 'string' || value !== value.trim() || /[\u0000-\u0020\u007f]/u.test(value))
    unavailable('Registry artifact URL must be literal public text');
  let url;
  try {url = new URL(value);} catch {unavailable('Malformed registry artifact URL');}
  if (url.origin !== origin || url.username || url.password || url.hash || url.search)
    unavailable('Artifact URL is outside the selected public registry origin');
  return url.href;
}

async function get(url, fetchResponse) {
  try {
    return await fetchResponse(url, {method: 'GET', credentials: 'omit', redirect: 'error',
      signal: AbortSignal.timeout(15_000), headers: {accept: 'application/json, application/octet-stream;q=0.8'}});
  } catch {unavailable('Registry GET failed or timed out');}
}

async function discard(response) {
  try {await response.body?.cancel();} catch {unavailable('Registry response cleanup failed');}
}

async function consume(response, maximum, visit, overflow = () => unavailable('Registry response exceeds its selected byte bound')) {
  if (!response.body || !Number.isSafeInteger(maximum) || maximum < 1) unavailable('Registry response body unavailable');
  const reader = response.body.getReader();
  let bytes = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      bytes += next.value.byteLength;
      if (bytes > maximum) overflow();
      visit(next.value);
    }
  } catch (failure) {
    if (failure instanceof RegistryUnavailable || failure instanceof RegistryConflict) throw failure;
    unavailable('Registry body was interrupted');
  } finally {
    // Cancel only this own reader; a completed stream is already settled.
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
  return bytes;
}

async function metadata(url, fetchResponse, requests, request = get) {
  const response = await request(url, fetchResponse);
  requests.push({url, status: response.status});
  if (response.status === 404) {await discard(response); return {status: 404};}
  if (response.status !== 200) {await discard(response); unavailable(`Registry metadata unavailable: HTTP ${response.status}`);}
  const chunks = [], sha = createHash('sha256');
  const bytes = await consume(response, 4 * 1024 * 1024, chunk => {chunks.push(Buffer.from(chunk)); sha.update(chunk);});
  Object.assign(requests.at(-1), {bytes, sha256: sha.digest('hex')});
  try {return {status: 200, body: JSON.parse(new TextDecoder('utf8', {fatal: true}).decode(Buffer.concat(chunks)))};}
  catch {unavailable('Registry metadata is not valid JSON');}
}

async function artifactBytes(url, artifact, fetchResponse, requests) {
  const response = await get(url, fetchResponse);
  requests.push({url, status: response.status});
  await artifactBody(response, artifact, requests.at(-1));
}

async function artifactBody(response, artifact, record, retain = () => {}) {
  // A missing download after positive metadata is not version absence.
  if (response.status !== 200) {await discard(response); unavailable(`Published artifact unavailable: HTTP ${response.status}`);}
  const sha = createHash('sha256'), sri = createHash('sha512');
  const bytes = await consume(response, artifact.bytes, chunk => {sha.update(chunk); sri.update(chunk); retain(chunk);},
    () => conflict(`Occupied artifact exceeds its fixed length: ${artifact.name}/${artifact.file}`));
  const actual = {bytes, sha256: sha.digest('hex'), integrity: `sha512-${sri.digest('base64')}`};
  Object.assign(record, actual);
  for (const field of ['bytes', 'sha256', ...(artifact.ecosystem === 'npm' ? ['integrity'] : [])]) {
    if (actual[field] !== artifact[field]) conflict(`Occupied artifact has different ${field}: ${artifact.name}/${artifact.file}`);
  }
}

const githubApi = 'https://api.github.com/repos/actql/actql';
const githubHeaders = {accept: 'application/vnd.github+json', 'x-github-api-version': '2026-03-10'};
const positiveId = value => Number.isSafeInteger(value) && value > 0;
const gitObject = value => value && typeof value.sha === 'string' && /^[a-f0-9]{40}$/u.test(value.sha) && ['commit', 'tag'].includes(value.type);
const stageId = value => typeof value === 'string' && value.length === 36 && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu.test(value);

async function githubGet(url, fetchResponse, accept = githubHeaders.accept) {
  try {
    return await fetchResponse(url, {method: 'GET', credentials: 'omit', redirect: 'manual',
      signal: AbortSignal.timeout(15_000), headers: {...githubHeaders, accept}});
  } catch {unavailable('Public GitHub GET failed or timed out');}
}

async function githubMetadata(path, fetchResponse, requests) {
  const reply = await metadata(`${githubApi}${path}`, fetchResponse, requests, githubGet);
  // An anonymous 404 cannot rule out an existing draft or private resource.
  if (reply.status !== 200) unavailable('Public GitHub metadata unavailable; an invisible draft is not absence');
  return reply.body;
}

async function githubReleaseContext(fixed, fetchResponse, requests, selectedRelease = null) {
  const {manifest} = fixed, tag = manifest.release.gitTag;
  const release = selectedRelease ?? await githubMetadata(`/releases/tags/${encodeURIComponent(tag)}`, fetchResponse, requests);
  if (!release || !positiveId(release.id) || typeof release.draft !== 'boolean' ||
      typeof release.immutable !== 'boolean' || typeof release.prerelease !== 'boolean' || typeof release.tag_name !== 'string')
    unavailable('Incomplete public GitHub release identity');
  if (release.draft || !release.immutable || release.tag_name !== tag ||
      release.prerelease !== manifest.release.prerelease)
    conflict('Occupied GitHub release is draft, mutable or has a different tag/prerelease identity');
  // target_commitish can be a moving branch. Resolve the actual tag instead.
  await githubTagCommit(fixed, fetchResponse, requests);
  const assets = await githubReleaseAssets(fixed, release, fetchResponse, requests);
  if (assets.length !== manifest.artifacts.filter(value => value.ecosystem === 'native').length)
    conflict('An immutable public GitHub release is missing a selected asset; it cannot be appended to');
  return assets;
}

async function githubTagCommit(fixed, fetchResponse, requests, allowMissing = false) {
  const {manifest} = fixed, tag = manifest.release.gitTag;
  const reply = await metadata(`${githubApi}/git/ref/tags/${encodeURIComponent(tag)}`, fetchResponse, requests, githubGet);
  if (reply.status === 404 && allowMissing) return null;
  if (reply.status !== 200) unavailable('Exact public Git tag reference unavailable');
  const ref = reply.body;
  if (ref?.ref !== `refs/tags/${tag}` || !gitObject(ref.object)) unavailable('Exact public Git tag reference unavailable');
  let object = ref.object;
  const seen = new Set();
  for (let count = 0; object.type === 'tag'; count++) {
    if (count === 8 || seen.has(object.sha)) unavailable('Public annotated tag chain exceeds its finite bound or cycles');
    seen.add(object.sha);
    const tagged = await githubMetadata(`/git/tags/${object.sha}`, fetchResponse, requests);
    if (tagged?.sha !== object.sha || !gitObject(tagged.object)) unavailable('Incomplete public annotated tag object');
    object = tagged.object;
  }
  if (object.sha !== manifest.request.source.commit) conflict('Occupied GitHub release tag resolves to another source commit');
  return object.sha;
}

async function githubReleaseAssets(fixed, release, fetchResponse, requests) {
  const {manifest} = fixed, tag = manifest.release.gitTag;
  const expected = manifest.artifacts.filter(value => value.ecosystem === 'native');
  if (new Set(expected.map(value => value.file)).size !== expected.length)
    conflict('Selected standalone assets have duplicate names in the one GitHub release');
  const assets = [], ids = new Set(), names = new Set();
  for (let page = 1; ; page++) {
    if (page > 10) unavailable('Public GitHub asset inventory exceeds its finite page bound');
    const batch = await githubMetadata(`/releases/${release.id}/assets?per_page=100&page=${page}`, fetchResponse, requests);
    if (!Array.isArray(batch) || batch.length > 100) unavailable('Malformed public GitHub asset page');
    for (const item of batch) {
      if (!item || !positiveId(item.id) || typeof item.name !== 'string' || names.has(item.name) || ids.has(item.id))
        unavailable('Malformed or duplicate public GitHub asset identity');
      names.add(item.name); ids.add(item.id); assets.push(item);
    }
    if (batch.length < 100) break;
  }
  for (const item of assets) {
    const artifact = expected.find(value => value.file === item.name);
    if (!artifact) conflict(`Occupied GitHub release contains an unselected asset: ${item.name}`);
    if (item.state !== 'uploaded' || item.size !== artifact.bytes ||
        (item.digest !== undefined && item.digest !== null && item.digest !== `sha256:${artifact.sha256}`))
      conflict(`Occupied GitHub asset metadata differs: ${item.name}`);
    if (!release.draft && item.browser_download_url !== `https://github.com/actql/actql/releases/download/${tag}/${encodeURIComponent(item.name)}`)
      unavailable('Public GitHub asset download identity is outside the selected release');
  }
  return assets;
}

function githubCdnUrl(value) {
  if (typeof value !== 'string' || value !== value.trim() || /[\u0000-\u0020\u007f]/u.test(value))
    unavailable('Malformed GitHub asset redirect');
  let url;
  try {url = new URL(value);} catch {unavailable('Malformed GitHub asset redirect URL');}
  if (!['https://release-assets.githubusercontent.com', 'https://objects.githubusercontent.com'].includes(url.origin) ||
      url.username || url.password || url.hash) unavailable('GitHub asset redirect is outside the selected public CDN origins');
  return url;
}

async function githubArtifactBytes(item, artifact, fetchResponse, requests, retain, fetchCdn = fetchResponse) {
  let url = `${githubApi}/releases/assets/${item.id}`;
  const seen = new Set();
  for (let redirects = 0; ; redirects++) {
    if (redirects > 3 || seen.has(url)) unavailable('Public GitHub asset redirect limit or cycle');
    seen.add(url);
    let response;
    if (redirects === 0) response = await githubGet(url, fetchResponse, 'application/octet-stream');
    else {
      try {response = await fetchCdn(url, {method: 'GET', credentials: 'omit', redirect: 'manual',
        signal: AbortSignal.timeout(15_000), headers: {accept: 'application/octet-stream'}});}
      catch {unavailable('Public GitHub asset CDN GET failed or timed out');}
    }
    // Signed CDN queries are needed for the GET but never retained in a receipt.
    const observed = new URL(url);
    requests.push({url: `${observed.origin}${observed.pathname}`, status: response.status});
    if (response.status === 302) {
      const next = response.headers.get('location'); await discard(response);
      url = githubCdnUrl(next).href;
    } else {
      await artifactBody(response, artifact, requests.at(-1), retain);
      return;
    }
  }
}

// This supplied API-only owner reader must have actual complete draft visibility
// and Administration-read permission. Its presence/JSON cannot prove those
// permissions, owner approval or exclusive execution. Anonymous 404 is never
// used as draft absence. API credentials must never reach the separate CDN port.
export async function observeNativePublicationTarget(directory, expectedSha256, targetId,
  {fetchOwner, fetchCdn = fetch} = {}) {
  assert.equal(typeof fetchOwner, 'function', 'A separate protected Native owner read port is required');
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const spec = nativeReleaseDraftRequest(fixed, targetId), artifacts = fixed.manifest.artifacts.filter(value => value.targetId === targetId);
  const requests = [], startedAt = new Date().toISOString();
  const result = {schemaVersion: 'actql-native-publication-observation/0.1', manifestSha256: fixed.sha256, targetId,
    startedAt, state: 'unknown', releaseId: null, observations: [], requests,
    qualification: 'historical owner-port settings/draft/actual-byte observation only; not permission, approval, exclusive execution, signature, public install or CAS'};
  try {
    const setting = await githubMetadata('/immutable-releases', fetchOwner, requests);
    if (setting?.enabled !== true || typeof setting.enforced_by_owner !== 'boolean')
      unavailable('Original immutable-release setting is unavailable or disabled');
    result.immutableSetting = setting;
    const matches = [], ids = new Set();
    for (let page = 1; ; page++) {
      if (page > 10) unavailable('Owner release inventory exceeds its finite page bound');
      const batch = await githubMetadata(`/releases?per_page=100&page=${page}`, fetchOwner, requests);
      if (!Array.isArray(batch) || batch.length > 100) unavailable('Incomplete original owner release page');
      for (const release of batch) {
        if (!positiveId(release?.id) || ids.has(release.id) || typeof release.tag_name !== 'string')
          unavailable('Malformed or duplicated owner release identity');
        ids.add(release.id); if (release.tag_name === spec.tag_name) matches.push(release);
      }
      if (batch.length < 100) break;
    }
    if (matches.length > 1) conflict('Multiple original releases occupy the selected tag');
    if (!matches.length) {
      await githubTagCommit(fixed, fetchOwner, requests, true);
      result.state = 'absent';
      result.observations = artifacts.map(item => ({file: item.file, state: 'absent'}));
    } else {
      const release = await githubMetadata(`/releases/${matches[0].id}`, fetchOwner, requests);
      if (!release || release.id !== matches[0].id || release.tag_name !== spec.tag_name ||
          release.prerelease !== spec.prerelease || typeof release.draft !== 'boolean' || typeof release.immutable !== 'boolean')
        unavailable('Original selected release identity changed or is incomplete');
      if (release.name !== spec.name || release.body !== spec.body)
        conflict('Occupied release presentation belongs to a different fixed candidate');
      result.releaseId = release.id;
      let assets;
      if (release.draft) {
        if (release.immutable || release.target_commitish !== spec.target_commitish)
          conflict('Draft source/immutability differs from the original candidate');
        await githubTagCommit(fixed, fetchOwner, requests, true);
        assets = await githubReleaseAssets(fixed, release, fetchOwner, requests);
        result.state = 'draft';
      } else {
        assets = await githubReleaseContext(fixed, fetchOwner, requests, release);
        result.state = 'published';
      }
      for (const item of artifacts) {
        const asset = assets.find(value => value.name === item.file);
        if (!asset) {result.observations.push({file: item.file, state: 'absent'}); continue;}
        await githubArtifactBytes(asset, item, fetchOwner, requests, undefined, fetchCdn);
        result.observations.push({file: item.file, state: 'present', assetId: asset.id, identity: identity(item)});
      }
      // Mutable Draft assets and presentation must be reobserved after their
      // streams, against the exact original selected release id, not just tag.
      const after = await githubMetadata(`/releases/${release.id}`, fetchOwner, requests);
      for (const field of ['id', 'tag_name', 'draft', 'immutable', 'prerelease', 'name', 'body', 'target_commitish'])
        if (after[field] !== release[field]) unavailable('Original release changed during byte observation');
      const afterAssets = await githubReleaseAssets(fixed, release, fetchOwner, requests);
      const pin = values => values.map(value => fields(value, ['id', 'name', 'state', 'size', 'digest', 'browser_download_url']))
        .sort((a,b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
      if (JSON.stringify(pin(afterAssets)) !== JSON.stringify(pin(assets))) unavailable('Original asset inventory changed during byte observation');
      await githubTagCommit(fixed, fetchOwner, requests, release.draft);
    }
    const finalSetting = await githubMetadata('/immutable-releases', fetchOwner, requests);
    if (finalSetting?.enabled !== true || finalSetting.enforced_by_owner !== setting.enforced_by_owner)
      unavailable('Original immutable-release setting changed during observation');
  } catch (failure) {
    if (!(failure instanceof RegistryUnavailable || failure instanceof RegistryConflict)) throw failure;
    result.state = failure instanceof RegistryConflict ? 'conflict' : 'unknown';
    result.reason = failure.message;
    result.observations = artifacts.map(item => ({file: item.file, state: result.state}));
  }
  await verifyReleaseSet(directory, {expectedSha256}); result.endedAt = new Date().toISOString();
  return result;
}

async function npmObservation(artifact, fetchResponse, requests) {
  const registry = 'https://registry.npmjs.org/';
  const reply = await metadata(`${registry}${encodeURIComponent(artifact.name)}/${artifact.version}`, fetchResponse, requests);
  if (reply.status === 200 && (typeof reply.body?.name !== 'string' || typeof reply.body?.version !== 'string' ||
      typeof reply.body?.dist?.integrity !== 'string')) unavailable('Incomplete npm version metadata');
  let state;
  try {
    // Preserve the existing exact name/version/SRI owner; no alternate npm
    // identity comparison or command output interpretation is introduced here.
    state = await publishedVersion(artifact, registry, async () => ({status: reply.status, json: async () => reply.body}));
  } catch {conflict(`Occupied npm version differs from its fixed original: ${artifact.name}`);}
  if (state === 'absent') return 'absent';
  let tarball = reply.body.dist.tarball;
  // The official npm publisher may record http metadata for its own registry;
  // npm's consumer upgrades that exact host to HTTPS. Never issue an HTTP GET
  // or broaden this into a redirect/foreign-origin/credential exception.
  if (typeof tarball === 'string' && tarball.startsWith('http://registry.npmjs.org/'))
    tarball = `https://${tarball.slice('http://'.length)}`;
  const url = publicUrl(tarball, 'https://registry.npmjs.org');
  await artifactBytes(url, artifact, fetchResponse, requests);
  return 'present';
}

async function pypiObservation(artifact, siblings, fetchResponse, requests) {
  const name = normalizedName(artifact.name);
  const reply = await metadata(`https://pypi.org/pypi/${encodeURIComponent(name)}/${encodeURIComponent(artifact.version)}/json`, fetchResponse, requests);
  if (reply.status === 404) return 'absent';
  const body = reply.body;
  if (!body || typeof body !== 'object' || !Array.isArray(body.urls) ||
      typeof body.info?.name !== 'string' || typeof body.info?.version !== 'string') unavailable('Incomplete PyPI release metadata');
  if (normalizedName(body.info.name) !== name || body.info.version !== artifact.version)
    conflict(`Occupied PyPI release has different name/version: ${artifact.name}`);
  if (body.urls.length === 0) conflict('Occupied empty PyPI release cannot establish an original same-bytes resume');
  // Inspect all files in this immutable version. A different old placeholder or
  // unselected platform must not become permission to append a new product.
  const seen = new Set();
  for (const item of body.urls) {
    if (!item || typeof item.filename !== 'string' || seen.has(item.filename)) unavailable('Malformed or duplicate PyPI file record');
    seen.add(item.filename);
    const expected = siblings.find(value => value.file === item.filename);
    if (!expected) conflict(`Occupied PyPI release contains an unselected file: ${item.filename}`);
    if (item.digests?.sha256 !== expected.sha256 || item.size !== expected.bytes ||
        item.packagetype !== 'bdist_wheel' || item.yanked !== false)
      conflict(`Occupied PyPI file differs or is yanked: ${item.filename}`);
  }
  const item = body.urls.find(value => value.filename === artifact.file);
  if (!item) return 'absent';
  const url = publicUrl(item.url, 'https://files.pythonhosted.org');
  let filename;
  try {filename = decodeURIComponent(new URL(url).pathname.split('/').at(-1));}
  catch {unavailable('Malformed PyPI file URL encoding');}
  if (filename !== artifact.file)
    unavailable('PyPI download URL does not name the original file');
  await artifactBytes(url, artifact, fetchResponse, requests);
  return 'present';
}

// The existing Node install harness has its complete original RC (including
// development originals), not a newly assembled upper set. Reuse the exact
// same npm identity and streamed-byte owner before its explicit public mode.
export async function observeNpmPackageRelease(directory, expectedSha256, {fetchResponse = fetch} = {}) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u);
  directory = resolve(directory); const path = join(directory, 'release.json');
  const root = await lstat(directory); assert(root.isDirectory() && !root.isSymbolicLink());
  const stat = await lstat(path); assert(stat.isFile() && !stat.isSymbolicLink());
  const original = await readFile(path), sha256 = createHash('sha256').update(original).digest('hex');
  assert.equal(sha256, expectedSha256, 'Node cohort differs from its externally retained manifest digest');
  const manifest = await verifyPackageRelease(directory);
  assert.deepEqual(await readFile(path), original, 'Node cohort changed during original verification');
  const startedAt = new Date().toISOString(), observations = [], issues = [], requests = [];
  for (const item of manifest.packages) {
    const artifact = {...item, ecosystem: 'npm'}, base = {name: item.name, version: item.version, file: item.file};
    try {
      const state = await npmObservation(artifact, fetchResponse, requests);
      observations.push({...base, state, ...(state === 'present' ? {identity: identity(artifact)} : {})});
    } catch (failure) {
      if (!(failure instanceof RegistryUnavailable || failure instanceof RegistryConflict)) throw failure;
      const state = failure instanceof RegistryConflict ? 'conflict' : 'unknown';
      observations.push({...base, state}); issues.push({...base, state, reason: failure.message});
    }
  }
  await verifyPackageRelease(directory);
  assert.deepEqual(await readFile(path), original, 'Node cohort changed during public observation');
  const after = await lstat(path); assert(after.isFile() && !after.isSymbolicLink());
  return {schemaVersion: 'actql-npm-public-observation/0.1', manifestSha256: sha256, sourceSha: manifest.sourceSha,
    startedAt, endedAt: new Date().toISOString(), observations, issues, requests,
    qualification: 'anonymous historical npm byte observations only; no install, publisher authority, approval, lock or CAS'};
}

function stagedIdentity(body, artifact, tag, id) {
  if (!body || !stageId(body.id) || typeof body.packageName !== 'string' || typeof body.version !== 'string' ||
      typeof body.tag !== 'string' || typeof body.status !== 'string') unavailable('Incomplete owner stage observation');
  if (body.id !== id || body.packageName !== artifact.name || body.version !== artifact.version || body.tag !== tag)
    conflict('Occupied stage has another original name/version/tag/id');
  if (body.status !== 'awaiting_approval') conflict('Selected stage is no longer awaiting owner approval');
  return fields(body, ['id', 'packageName', 'version', 'tag', 'status']);
}

async function pendingStage(artifact, tag, fetchStage, requests) {
  const matches = [], ids = new Set(); let observed = 0, total;
  for (let page = 0; ; page++) {
    if (page === 10) unavailable('Owner stage inventory exceeds its finite page bound');
    const reply = await metadata(`https://registry.npmjs.org/-/stage?page=${page}&perPage=100&package=${encodeURIComponent(artifact.name)}`,
      fetchStage, requests);
    // Neither an anonymous nor authenticated error establishes no pending stage.
    if (reply.status !== 200 || !reply.body || !Array.isArray(reply.body.items) || reply.body.items.length > 100 ||
        !Number.isSafeInteger(reply.body.total) || reply.body.total < 0)
      unavailable('Complete owner stage inventory unavailable');
    if (total !== undefined && total !== reply.body.total) unavailable('Owner stage inventory changed during pagination');
    total = reply.body.total; observed += reply.body.items.length;
    if (observed > total) unavailable('Owner stage inventory count differs');
    for (const item of reply.body.items) {
      if (!item || !stageId(item.id) || ids.has(item.id) || typeof item.packageName !== 'string' || typeof item.version !== 'string')
        unavailable('Malformed or duplicated owner stage inventory');
      ids.add(item.id);
      if (item.packageName === artifact.name && item.version === artifact.version) matches.push(item);
    }
    if (observed === total) break;
    if (reply.body.items.length !== 100) unavailable('Incomplete owner stage inventory page');
  }
  if (matches.length > 1) conflict('More than one stage occupies the exact selected version');
  if (matches.length === 0) return null;
  const id = matches[0].id;
  stagedIdentity(matches[0], artifact, tag, id);
  const url = `https://registry.npmjs.org/-/stage/${id}`;
  const before = await metadata(url, fetchStage, requests);
  if (before.status !== 200) unavailable('Exact owner stage unavailable');
  const original = stagedIdentity(before.body, artifact, tag, id);
  // View/list shasum is insufficient: stream the exact pending tarball through
  // the existing full length/SHA256/SRI owner, with the same finite byte bound.
  await artifactBytes(`${url}/tarball`, artifact, fetchStage, requests);
  const after = await metadata(url, fetchStage, requests);
  if (after.status !== 200) unavailable('Exact owner stage unavailable after byte read');
  if (JSON.stringify(stagedIdentity(after.body, artifact, tag, id)) !== JSON.stringify(original))
    unavailable('Owner stage changed during byte observation');
  return id;
}

// fetchStage is a separately supplied protected read port. Stage-only trust
// tokens cannot list/view/download, so there is deliberately no default reader
// and no environment/token discovery or anonymous-404 absence inference.
export async function observeNpmStageTarget(directory, expectedSha256, targetId,
  {fetchStage, fetchResponse = fetch, file = null} = {}) {
  assert.equal(typeof fetchStage, 'function', 'A separate original owner stage reader is required');
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === targetId);
  assert(target?.ecosystem === 'npm', 'Select an original npm target');
  const cohort = fixed.manifest.cohorts.find(value => value.targetId === targetId);
  assert(['node-npm', 'native-npm'].includes(cohort.kind));
  const child = JSON.parse(await readFile(join(directory, cohort.path))), tag = child.cohort.tag;
  assert(target.channels.includes(tag));
  const artifacts = fixed.manifest.artifacts.filter(value => value.targetId === targetId && (file === null || value.file === file));
  assert(artifacts.length && (file === null || artifacts.length === 1), 'Select exact original npm files');
  const startedAt = new Date().toISOString(), observations = [], issues = [], requests = [];
  for (const artifact of artifacts) {
    const base = fields(artifact, ['targetId', 'file', 'name', 'version']);
    try {
      const published = await npmObservation(artifact, fetchResponse, requests);
      if (published === 'present') {observations.push({...base, state: 'published', identity: identity(artifact)}); continue;}
      const pending = await pendingStage(artifact, tag, fetchStage, requests);
      if (pending) {observations.push({...base, state: 'pending', stageId: pending, tag, identity: identity(artifact)}); continue;}
      const namespace = await metadata(`https://registry.npmjs.org/${encodeURIComponent(artifact.name)}`, fetchResponse, requests);
      if (namespace.status === 200 && (namespace.body?.name !== artifact.name || !namespace.body.versions ||
          typeof namespace.body.versions !== 'object' || Array.isArray(namespace.body.versions) || Object.keys(namespace.body.versions).length === 0))
        unavailable('Exact active public package namespace unavailable');
      if (namespace.status === 200) {
        const tags = namespace.body['dist-tags'];
        if (!tags || typeof tags !== 'object' || Array.isArray(tags)) unavailable('Current staging tag map unavailable');
        if (Object.hasOwn(tags, tag)) conflict('Selected staging tag is already occupied; no implicit channel move');
      }
      observations.push({...base, state: 'missing', namespace: namespace.status === 404 ? 'absent' : 'present'});
    } catch (failure) {
      if (!(failure instanceof RegistryUnavailable || failure instanceof RegistryConflict)) throw failure;
      const state = failure instanceof RegistryConflict ? 'conflict' : 'unknown';
      observations.push({...base, state}); issues.push({...base, state, reason: failure.message});
    }
  }
  await verifyReleaseSet(directory, {expectedSha256});
  return {schemaVersion: 'actql-npm-stage-observation/0.1', manifestSha256: fixed.sha256, targetId,
    files: artifacts.map(value => value.file), startedAt, endedAt: new Date().toISOString(), observations, issues, requests,
    qualification: 'historical original public/owner-read-port observations only; no owner approval, stage send, exclusive execution, lock or CAS'};
}

export async function observeReleaseSet(directory, expectedSha256, {fetchResponse = fetch} = {}) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u, 'Supply the externally retained fixed manifest digest');
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const startedAt = new Date().toISOString(), observations = [], issues = [], requests = [];
  let nativeContext;
  for (const artifact of fixed.manifest.artifacts) {
    const base = fields(artifact, ['targetId', 'file']);
    try {
      let state;
      if (artifact.ecosystem === 'npm') state = await npmObservation(artifact, fetchResponse, requests);
      else if (artifact.ecosystem === 'pypi') state = await pypiObservation(artifact,
        fixed.manifest.artifacts.filter(value => value.ecosystem === 'pypi' &&
          normalizedName(value.name) === normalizedName(artifact.name) && value.version === artifact.version), fetchResponse, requests);
      else {
        nativeContext ??= githubReleaseContext(fixed, fetchResponse, requests);
        const assets = await nativeContext;
        await githubArtifactBytes(assets.find(value => value.name === artifact.file), artifact, fetchResponse, requests);
        state = 'present';
      }
      observations.push({...base, state, ...(state === 'present' ? {identity: identity(artifact)} : {})});
    } catch (failure) {
      if (!(failure instanceof RegistryUnavailable || failure instanceof RegistryConflict)) throw failure;
      const state = failure instanceof RegistryConflict ? 'conflict' : 'unknown';
      observations.push({...base, state});
      issues.push({...base, state, reason: failure.message});
    }
  }
  // Registry operations cannot mutate or repair the candidate, and a local
  // change during the read window invalidates this observation's binding.
  await verifyReleaseSet(directory, {expectedSha256});
  return {schemaVersion: 'actql-release-observation/0.1', manifestSha256: fixed.sha256,
    startedAt, endedAt: new Date().toISOString(), observations, issues, requests,
    plan: resumeReleaseSet(fixed, observations),
    qualification: 'anonymous bounded public HTTP byte observations only; no credentials, upload, approval, lock/CAS or public consumer acceptance; reobserve at the actual execution boundary'};
}

export async function observePythonReleaseTarget(directory, expectedSha256, targetId, {fetchResponse = fetch} = {}) {
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === targetId);
  assert(target?.ecosystem === 'pypi', 'Select one complete original Python target');
  const cohort = fixed.manifest.cohorts.find(value => value.targetId === targetId);
  assert.equal(cohort.kind, 'python-wheels');
  const artifacts = fixed.manifest.artifacts.filter(value => value.targetId === targetId);
  const startedAt = new Date().toISOString(), observations = [], issues = [], requests = [];
  for (const artifact of artifacts) {
    const base = fields(artifact, ['targetId', 'file', 'name', 'version']);
    try {
      const state = await pypiObservation(artifact, artifacts.filter(value => value.name === artifact.name), fetchResponse, requests);
      observations.push({...base, state, ...(state === 'present' ? {identity: identity(artifact)} : {})});
    } catch (failure) {
      if (!(failure instanceof RegistryUnavailable || failure instanceof RegistryConflict)) throw failure;
      const state = failure instanceof RegistryConflict ? 'conflict' : 'unknown';
      observations.push({...base, state}); issues.push({...base, state, reason: failure.message});
    }
  }
  await verifyReleaseSet(directory, {expectedSha256});
  return {schemaVersion: 'actql-python-public-observation/0.1', manifestSha256: fixed.sha256, targetId,
    startedAt, endedAt: new Date().toISOString(), observations, issues, requests,
    qualification: 'anonymous selected Python target byte observations only; no public install, runtime, approval or publisher authority'};
}

// The same original bounded reader can retain the bytes it actually checked.
// There is no second downloader, local-archive substitute or publisher here.
export async function downloadNativeReleaseTarget(directory, expectedSha256, targetId, destination,
  {fetchResponse = fetch} = {}) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u, 'Supply the externally retained fixed manifest digest');
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === targetId);
  assert.equal(target?.ecosystem, 'native');
  const cohort = fixed.manifest.cohorts.find(value => value.targetId === targetId);
  assert.equal(cohort.kind, 'native-standalone');
  const {verifyNativeStandalone} = await import('./native-standalone-release.mjs');
  const {requireNativeCohortPackageVersions} = await import('./native-cli-artifact-reader.mjs');
  const standalone = await verifyNativeStandalone(dirname(join(directory, cohort.path)));
  requireNativeCohortPackageVersions(JSON.parse(standalone.origin.manifest));
  destination = resolve(destination); await mkdir(destination, {mode: 0o700});
  const record = {schemaVersion: 'actql-native-public-download/0.1', manifestSha256: fixed.sha256, targetId,
    startedAt: new Date().toISOString(), status: 'incomplete', files: [], requests: [],
    qualification: 'actual bounded public bytes only; installation/profile/approval/publication remain separate'};
  try {
    const before = await githubReleaseContext(fixed, fetchResponse, record.requests);
    for (const artifact of fixed.manifest.artifacts.filter(value => value.targetId === targetId)) {
      const path = join(destination, artifact.file), fd = openSync(path, 'wx', 0o600);
      const file = {file: artifact.file, path, expectedBytes: artifact.bytes, expectedSha256: artifact.sha256,
        status: 'incomplete', retainedBytes: 0}; record.files.push(file);
      try {
        await githubArtifactBytes(before.find(value => value.name === artifact.file), artifact, fetchResponse, record.requests, chunk => {
          for (let offset = 0; offset < chunk.byteLength;) {
            const count = writeSync(fd, chunk, offset, chunk.byteLength - offset);
            assert(count > 0, 'Public Native download made no file progress'); offset += count; file.retainedBytes += count;
          }
        });
        fsyncSync(fd); file.status = 'verified';
      } finally {closeSync(fd);}
    }
    const after = await githubReleaseContext(fixed, fetchResponse, record.requests);
    const identity = items => items.map(item => fields(item,
      ['id', 'name', 'state', 'size', 'digest', 'browser_download_url']))
      .sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    assert.deepEqual(identity(after), identity(before), 'Public immutable Native asset identity changed during download');
    await verifyReleaseSet(directory, {expectedSha256}); record.status = 'verified';
    return {download: record, standalone};
  } catch (failure) {
    record.failure = failure instanceof RegistryConflict ? 'conflict' : 'unavailable-or-incomplete';
    throw failure;
  } finally {
    record.endedAt = new Date().toISOString();
    // Failed and partial bytes stay owned evidence. No success record, cleanup,
    // automatic retry or alternative source can make them usable.
    await writeFile(join(destination, 'download.json'), `${JSON.stringify(record, null, 2)}\n`, {flag: 'wx', mode: 0o600});
  }
}

export async function observeNpmReleaseTarget(directory, expectedSha256, targetId, {fetchResponse = fetch} = {}) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u);
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === targetId);
  assert.equal(target?.ecosystem, 'npm');
  const observations = [], requests = [], issues = [], startedAt = new Date().toISOString();
  for (const artifact of fixed.manifest.artifacts.filter(value => value.targetId === targetId)) {
    const base = fields(artifact, ['targetId', 'file', 'name', 'version']);
    try {
      const state = await npmObservation(artifact, fetchResponse, requests);
      observations.push({...base, state, ...(state === 'present' ? {identity: identity(artifact)} : {})});
    } catch (failure) {
      if (!(failure instanceof RegistryUnavailable || failure instanceof RegistryConflict)) throw failure;
      const state = failure instanceof RegistryConflict ? 'conflict' : 'unknown';
      observations.push({...base, state}); issues.push({...base, state, reason: failure.message});
    }
  }
  await verifyReleaseSet(directory, {expectedSha256});
  return {schemaVersion: 'actql-npm-public-target-observation/0.1', manifestSha256: fixed.sha256, targetId,
    startedAt, endedAt: new Date().toISOString(), observations, issues, requests,
    qualification: 'selected original public npm byte observation; no consumer, approval or publisher authority'};
}

export async function observeReleaseChannels(directory, expectedSha256, {fetchResponse = fetch} = {}) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u);
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const startedAt = new Date().toISOString(), observations = [], issues = [], requests = [];
  for (const artifact of fixed.manifest.artifacts.filter(value => value.ecosystem === 'npm')) {
    const target = fixed.manifest.request.targets.find(value => value.id === artifact.targetId);
    let tags;
    try {
      const reply = await metadata(`https://registry.npmjs.org/-/package/${encodeURIComponent(artifact.name)}/dist-tags`, fetchResponse, requests);
      if (reply.status !== 200 || !reply.body || typeof reply.body !== 'object' || Array.isArray(reply.body))
        unavailable('Current npm channel map is unavailable');
      tags = reply.body;
    } catch (failure) {
      if (!(failure instanceof RegistryUnavailable)) throw failure;
      issues.push({targetId: target.id, name: artifact.name, reason: failure.message});
    }
    for (const channel of target.channels) {
      const base = {targetId: target.id, name: artifact.name, channel};
      if (!tags) observations.push({...base, state: 'unknown'});
      else if (!Object.hasOwn(tags, channel)) observations.push({...base, state: 'absent'});
      else if (typeof tags[channel] === 'string' && tags[channel] && tags[channel] === tags[channel].trim())
        observations.push({...base, state: 'present', version: tags[channel]});
      else observations.push({...base, state: 'unknown'});
    }
  }
  await verifyReleaseSet(directory, {expectedSha256});
  return {schemaVersion: 'actql-release-channels/0.1', manifestSha256: fixed.sha256,
    startedAt, endedAt: new Date().toISOString(), observations, issues, requests,
    qualification: 'anonymous historical channel GETs only; no promotion, approval, public-install acceptance, lock or CAS'};
}
