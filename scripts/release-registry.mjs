// Anonymous read-only registry observations. These are historical DATA, not
// owner approval, a publication lease, upload permission or public install.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {publishedVersion} from './package-release.mjs';
import {resumeReleaseSet, verifyReleaseSet} from './release-set.mjs';

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

async function metadata(url, fetchResponse, requests) {
  const response = await get(url, fetchResponse);
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
  // A missing download after positive metadata is not version absence.
  if (response.status !== 200) {await discard(response); unavailable(`Published artifact unavailable: HTTP ${response.status}`);}
  const sha = createHash('sha256'), sri = createHash('sha512');
  const bytes = await consume(response, artifact.bytes, chunk => {sha.update(chunk); sri.update(chunk);},
    () => conflict(`Occupied artifact exceeds its fixed length: ${artifact.name}/${artifact.file}`));
  const actual = {bytes, sha256: sha.digest('hex'), integrity: `sha512-${sri.digest('base64')}`};
  Object.assign(requests.at(-1), actual);
  for (const field of ['bytes', 'sha256', ...(artifact.ecosystem === 'npm' ? ['integrity'] : [])]) {
    if (actual[field] !== artifact[field]) conflict(`Occupied artifact has different ${field}: ${artifact.name}/${artifact.file}`);
  }
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
  const url = publicUrl(reply.body.dist.tarball, 'https://registry.npmjs.org');
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

export async function observeReleaseSet(directory, expectedSha256, {fetchResponse = fetch} = {}) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u, 'Supply the externally retained fixed manifest digest');
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const startedAt = new Date().toISOString(), observations = [], issues = [], requests = [];
  for (const artifact of fixed.manifest.artifacts) {
    const base = fields(artifact, ['targetId', 'file']);
    try {
      let state;
      if (artifact.ecosystem === 'npm') state = await npmObservation(artifact, fetchResponse, requests);
      else if (artifact.ecosystem === 'pypi') state = await pypiObservation(artifact,
        fixed.manifest.artifacts.filter(value => value.ecosystem === 'pypi' &&
          normalizedName(value.name) === normalizedName(artifact.name) && value.version === artifact.version), fetchResponse, requests);
      else unavailable('No selected existing standalone Native observation route');
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
