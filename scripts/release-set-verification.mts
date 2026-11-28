// The bytes of a fixed set and its original review are evidence. Verification
// does not turn either into runtime acceptance or publication authority.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import type {BinaryLike} from 'node:crypto';
import {constants} from 'node:fs';
import {lstat, open, readFile} from 'node:fs/promises';
import {basename, join, resolve} from 'node:path';
import {admitReleaseRequest} from './release-policy.mjs';
import type {ReleaseEcosystem, ReleasePolicy, ReleaseRequest} from './release-policy.mjs';
import type {releaseVersion} from './release-version.mjs';
import {readPythonReleasePair} from './release-python-wheel-pair.mjs';

type BoundedFile = {path: string; bytes?: number; sha256?: string};
type FileIdentity = Required<BoundedFile>;
type Cohort = FileIdentity & {targetId: string; verification: string} & (
  {kind: 'node-npm' | 'native-npm' | 'native-standalone' | 'python-wheels'; originalManifests?: never} |
  {kind: 'python-wheel-pair'; originalManifests: FileIdentity[]});
type ReleaseArtifact = FileIdentity & {
  targetId: string; ecosystem: ReleaseEcosystem; name: string; version: string; file: string; integrity?: string;
};
type Package = Pick<ReleaseArtifact, 'name' | 'version' | 'file' | 'bytes' | 'sha256'>;
type NpmCohort = {version: string; sourceSha: string; cohort: {packageVersion: string; registry: string; tag: string};
  packages: (Package & {integrity: string})[]};
type NativeCohort = {schemaVersion: string; sourceSha: string; packageVersion: string; platforms: string[];
  requestedProfiles: string[]; archives: Package[]; checksums: Package};
type PythonCohort = {source_sha: string; package_version: string; platform: string;
  wheels: (Pick<Package, 'file' | 'bytes' | 'sha256'> & {distribution: string})[]};
type ReviewBinding = {preparation: FileIdentity; request: FileIdentity; evidence: (FileIdentity & {id: string})[]};
export type FixedReleaseManifest = {
  schemaVersion: 'actql-release-set/0.1'; release: ReturnType<typeof releaseVersion>; request: ReleaseRequest;
  policy: ReleasePolicy; cohorts: Cohort[]; artifacts: ReleaseArtifact[]; acceptance: 'unaccepted';
  qualification: string; review?: ReviewBinding;
};
type Evidence = {id: string; kind: string; file: string; bytes: number; sha256: string};
type BuildEvidence = {kind: 'github-actions'; repository: string; runId: string; artifactId: string; attempt: number;
  artifactSha256: string; evidence: string} | {kind: 'local'; run: string; artifactId: null; evidence: string};
type ReleaseReviewRequest = {
  schemaVersion: string; manifestSha256: string; evidence: Evidence[];
  provenance: {targetId: string; recipeEvidence: string; toolchainEvidence: string; build: BuildEvidence}[];
  environments: {targetId: string; platforms: string[]; profiles: string[]; node: string | null; python: string | null;
    abi: string; limitations: string[]}[];
  acceptance: {targetId: string; phase: string; status: string; evidence: string[]; limitations: string[]}[];
  changes: {previousSource: string | null; diffEvidence: string | null};
  executionScope: {publish: string[]; promote: {targetId: string; channel: string}[]; resumeIdenticalMissing: string[]};
};

export const hash = (value: BinaryLike) => createHash('sha256').update(value).digest('hex');
const fileStamp = ['dev', 'ino', 'size', 'mtimeMs', 'mode'] as const;

export const exact = (value: object, keys: readonly string[]) => assert.deepEqual(Object.keys(value).sort(), [...keys].sort());
export const filename = (value: string) => {
  assert.equal(typeof value, 'string');
  assert(value && value === basename(value) && value !== '.' && value !== '..' &&
    !/[\\\u0000-\u001f\u007f]/u.test(value), 'Artifact filename must be a literal basename');
};

export async function digest(path: string) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const before = await handle.stat(); assert(before.isFile(), 'Artifact must be a regular file');
    const sha = createHash('sha256'), sri = createHash('sha512');
    const buffer = Buffer.allocUnsafe(1024 * 1024);
    let position = 0;
    while (true) {
      const {bytesRead} = await handle.read(buffer, 0, buffer.length, position);
      if (!bytesRead) break;
      const chunk = buffer.subarray(0, bytesRead); sha.update(chunk); sri.update(chunk); position += bytesRead;
    }
    assert.equal(position, before.size, 'Artifact length changed while hashing');
    const after = await handle.stat();
    for (const key of fileStamp) assert.equal(after[key], before[key], 'Artifact changed while hashing');
    return {bytes: before.size, sha256: sha.digest('hex'), integrity: `sha512-${sri.digest('base64')}`};
  } finally {await handle.close();}
}

export async function originalFile(directory: string, relative: string) {
  const parent = await lstat(directory); assert(parent.isDirectory() && !parent.isSymbolicLink(), 'Original directory cannot be a symlink');
  const parts = relative.split('/'); assert(parts.every(part => part && !['.', '..'].includes(part)));
  let path = directory;
  for (const part of parts) {
    filename(part); path = join(path, part);
    const stat = await lstat(path); assert(!stat.isSymbolicLink(), 'Release input path cannot contain a symlink');
  }
  return path;
}

export async function verifyReleaseSet(directory: string, {expectedSha256}: {expectedSha256?: string} = {}) {
  directory = resolve(directory);
  const bytes = await readFile(await originalFile(directory, 'release-set.json'));
  const manifestSha256 = hash(bytes);
  if (expectedSha256 !== undefined) {assert.match(expectedSha256, /^[a-f0-9]{64}$/u); assert.equal(manifestSha256, expectedSha256, 'Release set differs from the externally retained digest');}
  const manifest = JSON.parse(bytes.toString('utf8')) as FixedReleaseManifest; exact(manifest, ['schemaVersion', 'release', 'request', 'policy', 'cohorts', 'artifacts', 'acceptance', 'qualification',
    ...(Object.hasOwn(manifest, 'review') ? ['review'] : [])]);
  assert.equal(manifest.schemaVersion, 'actql-release-set/0.1');
  assert.equal(manifest.acceptance, 'unaccepted', 'Local byte verification cannot promote acceptance');
  const selected = admitReleaseRequest(manifest.request, manifest.policy);
  assert.deepEqual(manifest.release, selected.version, 'Release header differs from the complete original version');
  assert.deepEqual(manifest.cohorts.map(value => value.targetId), selected.request.targets.map(value => value.id));
  const keys = new Set();
  for (const cohort of manifest.cohorts) {
    exact(cohort, ['targetId', 'kind', 'path', 'bytes', 'sha256', 'verification',
      ...(cohort.kind === 'python-wheel-pair' ? ['originalManifests'] : [])]);
    assert(cohort.path.startsWith(`${cohort.targetId}/`));
    const actual = await digest(await originalFile(directory, cohort.path));
    assert.equal(actual.bytes, cohort.bytes); assert.equal(actual.sha256, cohort.sha256);
    const target = selected.request.targets.find(value => value.id === cohort.targetId);
    assert(target, 'Missing original cohort target');
    const child: unknown = cohort.kind === 'python-wheel-pair' ? undefined :
      JSON.parse(await readFile(await originalFile(directory, cohort.path), 'utf8'));
    let identities: ReleaseArtifact[];
    if (cohort.kind === 'node-npm' || cohort.kind === 'native-npm') {
      const npm = child as NpmCohort;
      assert.equal(target.ecosystem, 'npm');
      assert.equal(npm.version, cohort.kind === 'node-npm' ? 'actql-package-release/0.1' : 'actql-native-cli-release/0.1');
      assert.equal(npm.sourceSha, selected.request.source.commit);
      assert.equal(npm.cohort.packageVersion, selected.version.version);
      assert.equal(npm.cohort.registry, target.destination);
      assert(target.channels.includes(npm.cohort.tag), 'Original cohort tag is not explicitly selected');
      identities = npm.packages.map(item => ({targetId: target.id, ecosystem: 'npm', name: item.name,
        version: item.version, file: item.file, bytes: item.bytes, sha256: item.sha256, integrity: item.integrity,
        path: `${target.id}/${item.file}`}));
    } else if (cohort.kind === 'native-standalone') {
      const native = child as NativeCohort;
      assert.equal(target.ecosystem, 'native'); assert.equal(native.schemaVersion, 'actql-native-standalone/0.1');
      assert.equal(native.sourceSha, selected.request.source.commit); assert.equal(native.packageVersion, selected.version.version);
      assert.deepEqual(native.platforms, target.platforms); assert.deepEqual(native.requestedProfiles, target.profiles);
      identities = [...native.archives, native.checksums].map(item => ({targetId: target.id, ecosystem: 'native', name: item.name,
        version: item.version, file: item.file, bytes: item.bytes, sha256: item.sha256, path: `${target.id}/${item.file}`}));
    } else if (cohort.kind === 'python-wheel-pair') {
      assert.equal(cohort.path, `${target.id}/python-release-pair.json`);
      const original = await checkedBytes(directory, cohort, 4 * 1024 * 1024);
      const {receipts, wheels} = readPythonReleasePair(original, selected.request.source.commit, selected.version.version, target);
      assert(Array.isArray(cohort.originalManifests) && cohort.originalManifests.length === receipts.length,
        'Both original Python cohort manifests must be retained');
      for (const [index, receipt] of receipts.entries()) {
        const originalManifest: FileIdentity | undefined = cohort.originalManifests[index];
        assert(originalManifest);
        exact(originalManifest, ['path', 'bytes', 'sha256']);
        assert.equal(originalManifest.path, `${target.id}/${receipt.platform}/cohort.json`);
        assert.equal(originalManifest.sha256, receipt.manifestSha256, 'Foreign original Python cohort digest');
        await checkedBytes(directory, originalManifest, 4 * 1024 * 1024);
      }
      identities = wheels.map(({distribution, ...item}) => ({...item, targetId: target.id, ecosystem: 'pypi',
        name: distribution, version: selected.version.pythonVersion, path: `${target.id}/${item.file}`}));
    } else {
      const python = child as PythonCohort;
      assert.equal(cohort.kind, 'python-wheels'); assert.equal(target.ecosystem, 'pypi');
      assert(selected.version.version !== '0.0.3', 'v0.0.3 Python release requires the original two-platform pair');
      assert.equal(python.source_sha, selected.request.source.commit);
      assert.equal(python.package_version, selected.version.pythonVersion);
      assert(target.platforms.includes(python.platform));
      identities = python.wheels.map(item => ({targetId: target.id, ecosystem: 'pypi', name: item.distribution,
        version: selected.version.pythonVersion, file: item.file, bytes: item.bytes, sha256: item.sha256,
        path: `${target.id}/${item.file}`}));
    }
    assert.deepEqual(manifest.artifacts.filter(value => value.targetId === target.id), identities,
      'Upper artifact identities differ from the complete original child manifest');
  }
  for (const target of selected.request.targets) {
    const records = manifest.artifacts.filter(value => value.targetId === target.id);
    const names = records.map(value => value.name);
    const pair = manifest.cohorts.find(value => value.targetId === target.id)?.kind === 'python-wheel-pair';
    assert.deepEqual(pair ? [...new Set(names)] : names, target.packages);
    for (const record of records) {
      exact(record, ['targetId', 'ecosystem', 'name', 'version', 'file', 'bytes', 'sha256', 'path',
        ...(target.ecosystem === 'npm' ? ['integrity'] : [])]);
      assert.equal(record.ecosystem, target.ecosystem); filename(record.file);
      assert.equal(record.path, `${target.id}/${record.file}`);
      assert(!keys.has(record.path), 'Duplicate artifact path'); keys.add(record.path);
      assert.equal(record.version, target.ecosystem === 'pypi' ? selected.version.pythonVersion : selected.version.version);
      const actual = await digest(await originalFile(directory, record.path));
      assert.equal(actual.bytes, record.bytes); assert.equal(actual.sha256, record.sha256);
      if (target.ecosystem === 'npm') assert.equal(actual.integrity, record.integrity);
    }
  }
  assert.equal(keys.size, manifest.artifacts.length, 'Unknown target artifact');
  assert.equal(await readFile(await originalFile(directory, 'release-set.sha256'), 'utf8'), `${manifestSha256}  release-set.json\n`);
  const review = Object.hasOwn(manifest, 'review') ? await verifyReview(directory, manifest as FixedReleaseManifest & {review: ReviewBinding}) : null;
  return {manifest, sha256: manifestSha256, ...(review ? {review} : {})};
}

const reviewKinds = ['recipe', 'toolchain', 'build', 'acceptance', 'diff', 'signing'];
export const literal = (value: unknown) => assert(typeof value === 'string' && value.length && value.length <= 4096 &&
  value === value.trim() && !/[\u0000-\u001f\u007f]/u.test(value), 'Expected bounded literal review text');
export const uniqueList = (value: unknown[]) => {assert(Array.isArray(value)); assert.equal(new Set(value).size, value.length);};
export const digestText = (value: string) => {assert.equal(typeof value, 'string'); assert.match(value, /^[a-f0-9]{64}$/u);};
export const commitText = (value: string) => {assert.equal(typeof value, 'string'); assert.match(value, /^[a-f0-9]{40}$/u);};

export function admitReview(request: ReleaseReviewRequest, manifest: FixedReleaseManifest, originalSha256: string) {
  exact(request, ['schemaVersion', 'manifestSha256', 'evidence', 'provenance', 'environments', 'acceptance', 'changes', 'executionScope']);
  assert.equal(request.schemaVersion, 'actql-release-review-request/0.1');
  assert.equal(request.manifestSha256, originalSha256, 'Review request selects another preparation manifest');
  assert(Array.isArray(request.evidence) && request.evidence.length > 0 && request.evidence.length <= 128);
  const evidence = new Map<string, Evidence>(); let total = 0;
  for (const item of request.evidence) {
    exact(item, ['id', 'kind', 'file', 'bytes', 'sha256']);
    assert.equal(typeof item.id, 'string'); assert.match(item.id, /^[a-z][a-z0-9-]{0,63}$/u);
    assert(!evidence.has(item.id), 'Duplicate evidence id'); evidence.set(item.id, item);
    assert(reviewKinds.includes(item.kind)); literal(item.file);
    assert(!item.file.startsWith('/') && item.file.split('/').every(part => part && !['.', '..'].includes(part)));
    assert(Number.isSafeInteger(item.bytes) && item.bytes > 0 && item.bytes <= 64 * 1024 * 1024);
    total += item.bytes; assert(total <= 256 * 1024 * 1024); digestText(item.sha256);
  }
  const reference = (id: string, kind: string) => assert(evidence.get(id)?.kind === kind, `Missing ${kind} evidence: ${id}`);
  const targets = manifest.request.targets, ids = targets.map(value => value.id);
  for (const field of ['provenance', 'environments'] as const) {
    assert(Array.isArray(request[field]));
    assert.deepEqual(request[field].map(value => value.targetId), ids, `Review ${field} must follow every original target`);
  }
  for (const item of request.provenance) {
    exact(item, ['targetId', 'recipeEvidence', 'toolchainEvidence', 'build']);
    reference(item.recipeEvidence, 'recipe'); reference(item.toolchainEvidence, 'toolchain');
    const build = item.build;
    if (build.kind === 'github-actions') {
      exact(build, ['kind', 'repository', 'runId', 'attempt', 'artifactId', 'artifactSha256', 'evidence']);
      assert.equal(build.repository, manifest.request.source.repository);
      for (const key of ['runId', 'artifactId'] as const) {assert.equal(typeof build[key], 'string'); assert.match(build[key], /^[1-9][0-9]*$/u);}
      assert(Number.isSafeInteger(build.attempt) && build.attempt > 0); digestText(build.artifactSha256);
    } else {
      exact(build, ['kind', 'run', 'artifactId', 'evidence']); assert.equal(build.kind, 'local'); literal(build.run);
      assert.equal(build.artifactId, null, 'A local receipt cannot invent a hosted immutable artifact id');
    }
    reference(build.evidence, 'build');
  }
  for (const [index, item] of request.environments.entries()) {
    exact(item, ['targetId', 'platforms', 'profiles', 'node', 'python', 'abi', 'limitations']);
    assert.deepEqual(item.platforms, targets[index].platforms); assert.deepEqual(item.profiles, targets[index].profiles);
    for (const field of ['node', 'python'] as const) if (item[field] !== null) literal(item[field]);
    literal(item.abi); assert(Array.isArray(item.limitations)); item.limitations.forEach(literal);
  }
  assert(Array.isArray(request.acceptance));
  assert.deepEqual(request.acceptance.map(value => [value.targetId, value.phase]),
    ids.flatMap(id => [[id, 'prepublication-install'], [id, 'public-install']]));
  for (const item of request.acceptance) {
    exact(item, ['targetId', 'phase', 'status', 'evidence', 'limitations']);
    assert(['not-run', 'passed', 'failed'].includes(item.status)); uniqueList(item.evidence);
    assert.equal(item.evidence.length > 0, item.status !== 'not-run', 'Executed acceptance needs its original evidence');
    item.evidence.forEach(id => reference(id, 'acceptance'));
    assert(Array.isArray(item.limitations)); item.limitations.forEach(literal);
  }
  exact(request.changes, ['previousSource', 'diffEvidence']);
  if (request.changes.previousSource === null) assert.equal(request.changes.diffEvidence, null);
  else {commitText(request.changes.previousSource); reference(request.changes.diffEvidence as string, 'diff');}
  const scope = request.executionScope;
  exact(scope, ['publish', 'promote', 'resumeIdenticalMissing']);
  for (const field of ['publish', 'resumeIdenticalMissing'] as const) {
    uniqueList(scope[field]); assert(scope[field].every(id => ids.includes(id)), 'Unselected execution target');
  }
  assert(scope.resumeIdenticalMissing.every(id => scope.publish.includes(id)), 'Resume scope exceeds proposed publication');
  assert(Array.isArray(scope.promote)); const moves = new Set();
  for (const item of scope.promote) {
    exact(item, ['targetId', 'channel']); const target = targets.find(value => value.id === item.targetId);
    assert(target && target.channels.includes(item.channel), 'Unselected promotion channel');
    const key = `${item.targetId}/${item.channel}`; assert(!moves.has(key), 'Duplicate promotion'); moves.add(key);
  }
  assert(scope.publish.length || scope.promote.length, 'Select the proposed execution scope explicitly');
  // These are supplied review claims and raw evidence bindings, never a proof
  // of the claims, an accepted support row, owner approval or an execution lease.
  return structuredClone(request);
}

export async function checkedBytes(directory: string, record: BoundedFile, maximum: number) {
  const path = await originalFile(directory, record.path);
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const before = await handle.stat();
    assert(before.isFile() && before.size > 0 && before.size <= maximum, 'Review file exceeds its explicit byte bound');
    const bytes = await handle.readFile();
    const after = await handle.stat();
    for (const key of fileStamp) assert.equal(after[key], before[key]);
    assert.equal(bytes.length, before.size);
    if (record.bytes !== undefined) assert.equal(bytes.length, record.bytes);
    if (record.sha256 !== undefined) assert.equal(hash(bytes), record.sha256);
    return bytes;
  } finally {await handle.close();}
}

async function verifyReview(directory: string, manifest: FixedReleaseManifest & {review: ReviewBinding}) {
  const binding = manifest.review; exact(binding, ['preparation', 'request', 'evidence']);
  const verify = async (record: FileIdentity, path: string, maximum: number) => {
    exact(record, ['path', 'bytes', 'sha256']); assert.equal(record.path, path); digestText(record.sha256);
    return checkedBytes(directory, record, maximum);
  };
  const preparation = await verify(binding.preparation, 'review/preparation.json', 4 * 1024 * 1024);
  const {review, ...original} = manifest;
  assert.deepEqual(JSON.parse(preparation.toString('utf8')), original, 'Review enrichment changed the original preparation body');
  const request = admitReview(JSON.parse((await verify(binding.request, 'review/request.json', 1024 * 1024)).toString('utf8')) as ReleaseReviewRequest, original, binding.preparation.sha256);
  assert(Array.isArray(binding.evidence));
  assert.deepEqual(binding.evidence.map(item => item.id), request.evidence.map(item => item.id));
  for (const [index, item] of binding.evidence.entries()) {
    exact(item, ['id', 'path', 'bytes', 'sha256']);
    const {id, ...record} = item, supplied = request.evidence[index];
    assert.equal(record.bytes, supplied.bytes); assert.equal(record.sha256, supplied.sha256);
    await verify(record, `review/evidence/${id}`, 64 * 1024 * 1024);
  }
  return request;
}
