// Anonymous registry read evidence and exact streamed byte comparison.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {lstat, readFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {publishedVersion, verifyPackageRelease} from './package-release.mjs';
import {verifyNativeCliRelease} from './native-cli-release.mjs';

type RegistryArtifact = {
  name: string;
  version: string;
  bytes: number;
  sha256: string;
  ecosystem: string;
  file: string;
  integrity?: string;
};
type NpmPackage = RegistryArtifact & {ecosystem: 'npm'; integrity: string};
type ManifestPackage = Omit<NpmPackage, 'ecosystem'>;
type VerifiedCohort = {sourceSha: string; packages: readonly ManifestPackage[]};
type VerifyCohort = (directory: string) => Promise<VerifiedCohort>;
type RequestEvidence = {url: string; status: number; bytes?: number; sha256?: string; integrity?: string};
type FetchResponse = typeof fetch;
type RegistryRequest = (url: string, fetchResponse: FetchResponse) => Promise<Response>;
type MetadataReply = {status: 404; body?: never} | {status: 200; body: unknown};
type NpmMetadata = {name?: unknown; version?: unknown; dist?: {integrity?: unknown; tarball?: unknown}};
type ObservationBase = {name: string; version: string; file: string};
type Observation = ObservationBase & {state: 'present' | 'absent' | 'conflict' | 'unknown';
  identity?: ReturnType<typeof identity>};
type Issue = ObservationBase & {state: 'conflict' | 'unknown'; reason: string};

export class RegistryUnavailable extends Error {}
export class RegistryConflict extends Error {}
export function unavailable(message: string): never {
  throw new RegistryUnavailable(message);
}
export function conflict(message: string): never {
  throw new RegistryConflict(message);
}
export function fields<Value extends object, Key extends keyof Value>(record: Value, names: readonly Key[]): Pick<Value, Key> {
  return Object.fromEntries(names.map(name => [name, record[name]])) as Pick<Value, Key>;
}
export const identity = (artifact: RegistryArtifact) => fields(artifact, ['name', 'version', 'bytes', 'sha256',
  ...(artifact.ecosystem === 'npm' ? ['integrity'] as const : [])]);
export function publicUrl(value: unknown, origin: string) {
  if (typeof value !== 'string' || value !== value.trim() || /[\u0000-\u0020\u007f]/u.test(value))
    unavailable('Registry artifact URL must be literal public text');
  let url;
  try {url = new URL(value);} catch {unavailable('Malformed registry artifact URL');}
  if (url.origin !== origin || url.username || url.password || url.hash || url.search)
    unavailable('Artifact URL is outside the selected public registry origin');
  return url.href;
}

async function get(url: string, fetchResponse: FetchResponse) {
  try {
    return await fetchResponse(url, {method: 'GET', credentials: 'omit', redirect: 'error',
      signal: AbortSignal.timeout(15_000), headers: {accept: 'application/json, application/octet-stream;q=0.8'}});
  } catch {unavailable('Registry GET failed or timed out');}
}

export async function discard(response: Response) {
  try {await response.body?.cancel();} catch {unavailable('Registry response cleanup failed');}
}

async function consume(response: Response, maximum: number, visit: (chunk: Uint8Array) => void,
  overflow: () => never = () => unavailable('Registry response exceeds its selected byte bound')) {
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

export async function metadata(url: string, fetchResponse: FetchResponse, requests: RequestEvidence[],
  request: RegistryRequest = get): Promise<MetadataReply> {
  const response = await request(url, fetchResponse);
  const record: RequestEvidence = {url, status: response.status};
  requests.push(record);
  if (response.status === 404) {await discard(response); return {status: 404};}
  if (response.status !== 200) {await discard(response); unavailable(`Registry metadata unavailable: HTTP ${response.status}`);}
  const chunks: Buffer[] = [], sha = createHash('sha256');
  const bytes = await consume(response, 4 * 1024 * 1024, chunk => {chunks.push(Buffer.from(chunk)); sha.update(chunk);});
  Object.assign(record, {bytes, sha256: sha.digest('hex')});
  try {return {status: 200, body: JSON.parse(new TextDecoder('utf8', {fatal: true}).decode(Buffer.concat(chunks))) as unknown};}
  catch {unavailable('Registry metadata is not valid JSON');}
}

export async function artifactBytes(url: string, artifact: RegistryArtifact, fetchResponse: FetchResponse, requests: RequestEvidence[]) {
  const response = await get(url, fetchResponse);
  const record: RequestEvidence = {url, status: response.status};
  requests.push(record);
  await artifactBody(response, artifact, record);
}

export async function artifactBody(response: Response, artifact: RegistryArtifact, record: RequestEvidence,
  retain: (chunk: Uint8Array) => void = () => {}) {
  // A missing download after positive metadata is not version absence.
  if (response.status !== 200) {await discard(response); unavailable(`Published artifact unavailable: HTTP ${response.status}`);}
  const sha = createHash('sha256'), sri = createHash('sha512');
  const bytes = await consume(response, artifact.bytes, chunk => {sha.update(chunk); sri.update(chunk); retain(chunk);},
    () => conflict(`Occupied artifact exceeds its fixed length: ${artifact.name}/${artifact.file}`));
  const actual = {bytes, sha256: sha.digest('hex'), integrity: `sha512-${sri.digest('base64')}`};
  Object.assign(record, actual);
  for (const field of ['bytes', 'sha256', ...(artifact.ecosystem === 'npm' ? ['integrity'] as const : [])] as const) {
    if (actual[field] !== artifact[field]) conflict(`Occupied artifact has different ${field}: ${artifact.name}/${artifact.file}`);
  }
}

export async function npmObservation(artifact: NpmPackage, fetchResponse: FetchResponse, requests: RequestEvidence[]) {
  const registry = 'https://registry.npmjs.org/';
  const reply = await metadata(`${registry}${encodeURIComponent(artifact.name)}/${artifact.version}`, fetchResponse, requests);
  const body = reply.body as NpmMetadata | null | undefined;
  if (reply.status === 200 && (typeof body?.name !== 'string' || typeof body?.version !== 'string' ||
      typeof body?.dist?.integrity !== 'string')) unavailable('Incomplete npm version metadata');
  let state;
  try {
    // Preserve the existing exact name/version/SRI owner; no alternate npm
    // identity comparison or command output interpretation is introduced here.
    state = await publishedVersion(artifact, registry, async () => ({status: reply.status, json: async () => reply.body}));
  } catch {conflict(`Occupied npm version differs from its fixed original: ${artifact.name}`);}
  if (state === 'absent') return 'absent';
  let tarball = body?.dist?.tarball;
  // The official npm publisher may record http metadata for its own registry;
  // npm's consumer upgrades that exact host to HTTPS. Never issue an HTTP GET
  // or broaden this into a redirect/foreign-origin/credential exception.
  if (typeof tarball === 'string' && tarball.startsWith('http://registry.npmjs.org/'))
    tarball = `https://${tarball.slice('http://'.length)}`;
  const url = publicUrl(tarball, 'https://registry.npmjs.org');
  await artifactBytes(url, artifact, fetchResponse, requests);
  return 'present';
}

// The existing Node install harness has its complete original RC (including
// development originals), not a newly assembled upper set. Reuse the exact
// same npm identity and streamed-byte owner before its explicit public mode.
export async function observeNpmPackageRelease(directory: string, expectedSha256: string, {fetchResponse = fetch} = {}) {
  return observeNpmCohort(directory, expectedSha256, verifyPackageRelease, 'Node', fetchResponse);
}

export async function observeNativeCliNpmRelease(directory: string, expectedSha256: string, {fetchResponse = fetch} = {}) {
  return observeNpmCohort(directory, expectedSha256, verifyNativeCliRelease, 'Native CLI', fetchResponse);
}

async function observeNpmCohort(directory: string, expectedSha256: string, verify: VerifyCohort, label: string,
  fetchResponse: FetchResponse) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u);
  directory = resolve(directory); const path = join(directory, 'release.json');
  const root = await lstat(directory); assert(root.isDirectory() && !root.isSymbolicLink());
  const stat = await lstat(path); assert(stat.isFile() && !stat.isSymbolicLink());
  const original = await readFile(path), sha256 = createHash('sha256').update(original).digest('hex');
  assert.equal(sha256, expectedSha256, `${label} cohort differs from its externally retained manifest digest`);
  const manifest = await verify(directory);
  assert.deepEqual(await readFile(path), original, `${label} cohort changed during original verification`);
  const startedAt = new Date().toISOString();
  const observations: Observation[] = [], issues: Issue[] = [], requests: RequestEvidence[] = [];
  for (const item of manifest.packages) {
    const artifact: NpmPackage = {...item, ecosystem: 'npm'}, base = {name: item.name, version: item.version, file: item.file};
    try {
      const state = await npmObservation(artifact, fetchResponse, requests);
      observations.push({...base, state, ...(state === 'present' ? {identity: identity(artifact)} : {})});
    } catch (failure) {
      if (!(failure instanceof RegistryUnavailable || failure instanceof RegistryConflict)) throw failure;
      const state = failure instanceof RegistryConflict ? 'conflict' : 'unknown';
      observations.push({...base, state}); issues.push({...base, state, reason: failure.message});
    }
  }
  await verify(directory);
  assert.deepEqual(await readFile(path), original, `${label} cohort changed during public observation`);
  const after = await lstat(path); assert(after.isFile() && !after.isSymbolicLink());
  return {schemaVersion: 'actql-npm-public-observation/0.1', manifestSha256: sha256, sourceSha: manifest.sourceSha,
    startedAt, endedAt: new Date().toISOString(), observations, issues, requests,
    qualification: 'anonymous historical npm byte observations only; no install, publisher authority, approval, lock or CAS'};
}
