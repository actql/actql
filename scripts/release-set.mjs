// Bind existing ecosystem outputs; this layer never builds, authenticates,
// uploads or turns a local record into owner approval.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {copyFile, lstat, mkdir, open, readFile, writeFile} from 'node:fs/promises';
import {basename, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {admitReleaseRequest} from './release-policy.mjs';
import {releaseVersion} from './release-version.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const hash = value => createHash('sha256').update(value).digest('hex');
const json = value => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
const exact = (value, keys) => assert.deepEqual(Object.keys(value).sort(), [...keys].sort());
const filename = value => {
  assert.equal(typeof value, 'string');
  assert(value && value === basename(value) && value !== '.' && value !== '..' &&
    !/[\\\u0000-\u001f\u007f]/u.test(value), 'Artifact filename must be a literal basename');
};

async function digest(path) {
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
    for (const key of ['dev', 'ino', 'size', 'mtimeMs', 'mode']) assert.equal(after[key], before[key], 'Artifact changed while hashing');
    return {bytes: before.size, sha256: sha.digest('hex'), integrity: `sha512-${sri.digest('base64')}`};
  } finally {await handle.close();}
}

async function originalFile(directory, relative) {
  const parent = await lstat(directory); assert(parent.isDirectory() && !parent.isSymbolicLink(), 'Original directory cannot be a symlink');
  const parts = relative.split('/'); assert(parts.every(part => part && !['.', '..'].includes(part)));
  let path = directory;
  for (const part of parts) {
    filename(part); path = join(path, part);
    const stat = await lstat(path); assert(!stat.isSymbolicLink(), 'Release input path cannot contain a symlink');
  }
  return path;
}

async function readCohort(descriptor, target, request, python) {
  exact(descriptor, ['targetId', 'kind', 'directory']);
  const directory = resolve(descriptor.directory);
  assert((await lstat(directory)).isDirectory() && !(await lstat(directory)).isSymbolicLink());
  let manifest, manifestFile, records, qualification;
  if (descriptor.kind === 'node-npm' || descriptor.kind === 'native-npm') {
    assert.equal(target.ecosystem, 'npm', 'Native npm launchers are not standalone Native archives');
    manifestFile = 'release.json';
    const bytes = await readFile(await originalFile(directory, manifestFile));
    manifest = descriptor.kind === 'node-npm'
      ? await (await import('./package-release.mjs')).verifyPackageRelease(directory)
      : await (await import('./native-cli-release.mjs')).verifyNativeCliRelease(directory);
    assert.deepEqual(await readFile(await originalFile(directory, manifestFile)), bytes, 'Cohort changed during its existing verifier');
    assert.equal(manifest.sourceSha, request.source.commit);
    assert.equal(manifest.cohort.packageVersion, request.version);
    assert.equal(manifest.cohort.registry, target.destination);
    assert(target.channels.includes(manifest.cohort.tag), 'Original cohort tag is not explicitly selected');
    records = manifest.packages.map(item => ({name: item.name, version: item.version, file: item.file,
      sourceFile: item.file, bytes: item.bytes, sha256: item.sha256, integrity: item.integrity}));
    qualification = 'existing complete ecosystem release verifier; install/platform/public acceptance remains separate';
  } else if (descriptor.kind === 'python-wheels') {
    assert.equal(target.ecosystem, 'pypi'); manifestFile = 'cohort.json';
    const expected = releaseVersion(request.version);
    const output = JSON.parse(execFileSync(python, [join(root, 'scripts/python_release_cohort.py'),
      '--verify-directory', directory, '--source', request.source.commit, '--version', expected.pythonVersion],
    {encoding: 'utf8', timeout: 60_000, maxBuffer: 4 * 1024 * 1024}));
    manifest = output.cohort; qualification = output.qualification;
    assert.equal(hash(await readFile(await originalFile(directory, manifestFile))), output.manifest_sha256);
    assert(target.platforms.includes(manifest.platform), 'Python platform differs from selected target');
    records = manifest.wheels.map(item => ({name: item.distribution, version: expected.pythonVersion,
      file: item.file, sourceFile: `wheels/${item.file}`, bytes: item.bytes, sha256: item.sha256}));
  } else if (descriptor.kind === 'native-standalone') {
    assert.equal(target.ecosystem, 'native'); manifestFile = 'native-standalone.json';
    manifest = await (await import('./native-standalone-release.mjs')).verifyNativeStandalone(directory);
    assert.equal(manifest.sourceSha, request.source.commit); assert.equal(manifest.packageVersion, request.version);
    assert.deepEqual(manifest.platforms, target.platforms); assert.deepEqual(manifest.requestedProfiles, target.profiles);
    records = [...manifest.archives, manifest.checksums].map(item => ({name: item.name, version: item.version,
      file: item.file, sourceFile: item.file, bytes: item.bytes, sha256: item.sha256}));
    qualification = manifest.qualification;
  } else throw new Error('No selected existing verifier for this cohort kind');
  assert.deepEqual(records.map(item => item.name), target.packages, 'Target package order must equal the existing complete cohort');
  for (const record of records) {
    filename(record.file); assert(Number.isSafeInteger(record.bytes) && record.bytes > 0);
    assert.match(record.sha256, /^[a-f0-9]{64}$/u);
    const actual = await digest(await originalFile(directory, record.sourceFile));
    assert.equal(actual.bytes, record.bytes); assert.equal(actual.sha256, record.sha256);
    if (target.ecosystem === 'npm') assert.equal(actual.integrity, record.integrity);
  }
  return {directory, manifestFile, bytes: await readFile(await originalFile(directory, manifestFile)), records, qualification};
}

export async function freezeReleaseSet({request, policy, cohorts, destination, python = 'python3'}) {
  const selected = admitReleaseRequest(request, policy);
  assert(Array.isArray(cohorts)); assert.equal(cohorts.length, request.targets.length, 'Every selected target needs its original cohort');
  assert.equal(new Set(cohorts.map(value => value.targetId)).size, cohorts.length);
  const inputs = [];
  // Full existing verification completes BEFORE creating output or copying.
  for (const target of request.targets) {
    const descriptor = cohorts.find(value => value.targetId === target.id); assert(descriptor, 'Missing selected cohort');
    inputs.push({target, kind: descriptor.kind, ...(await readCohort(descriptor, target, selected.request, python))});
  }
  destination = resolve(destination); await mkdir(destination);
  const groups = [], artifacts = [];
  for (const input of inputs) {
    const {target, kind, directory, records, bytes, manifestFile, qualification} = input;
    const group = join(destination, target.id); await mkdir(group);
    await writeFile(join(group, manifestFile), bytes, {flag: 'wx'});
    groups.push({targetId: target.id, kind, path: `${target.id}/${manifestFile}`, bytes: bytes.length,
      sha256: hash(bytes), verification: qualification});
    for (const record of records) {
      const output = join(group, record.file);
      await copyFile(await originalFile(directory, record.sourceFile), output, constants.COPYFILE_EXCL);
      const actual = await digest(output);
      assert.equal(actual.bytes, record.bytes); assert.equal(actual.sha256, record.sha256);
      if (target.ecosystem === 'npm') assert.equal(actual.integrity, record.integrity);
      const {sourceFile, ...identity} = record;
      artifacts.push({targetId: target.id, ecosystem: target.ecosystem, ...identity, path: `${target.id}/${record.file}`});
    }
    assert.deepEqual(await readFile(await originalFile(directory, manifestFile)), bytes, 'Original cohort changed while freezing');
  }
  const manifest = {schemaVersion: 'actql-release-set/0.1', release: selected.version,
    request: selected.request, policy: structuredClone(policy),
    cohorts: groups, artifacts, acceptance: 'unaccepted',
    qualification: 'frozen existing cohort/artifact identities only; no owner approval, runtime/profile/public install or publication authority'};
  const bytes = json(manifest), manifestSha256 = hash(bytes);
  await writeFile(join(destination, 'release-set.json'), bytes, {flag: 'wx'});
  // Detached digest avoids a self-reference. It is not an approval record.
  await writeFile(join(destination, 'release-set.sha256'), `${manifestSha256}  release-set.json\n`, {flag: 'wx'});
  return {manifest, sha256: manifestSha256};
}

export async function verifyReleaseSet(directory, {expectedSha256} = {}) {
  directory = resolve(directory);
  const bytes = await readFile(await originalFile(directory, 'release-set.json'));
  const manifestSha256 = hash(bytes);
  if (expectedSha256 !== undefined) {assert.match(expectedSha256, /^[a-f0-9]{64}$/u); assert.equal(manifestSha256, expectedSha256, 'Release set differs from the externally retained digest');}
  const manifest = JSON.parse(bytes); exact(manifest, ['schemaVersion', 'release', 'request', 'policy', 'cohorts', 'artifacts', 'acceptance', 'qualification']);
  assert.equal(manifest.schemaVersion, 'actql-release-set/0.1');
  assert.equal(manifest.acceptance, 'unaccepted', 'Local byte verification cannot promote acceptance');
  const selected = admitReleaseRequest(manifest.request, manifest.policy);
  assert.deepEqual(manifest.release, selected.version, 'Release header differs from the complete original version');
  assert.deepEqual(manifest.cohorts.map(value => value.targetId), selected.request.targets.map(value => value.id));
  const keys = new Set();
  for (const cohort of manifest.cohorts) {
    exact(cohort, ['targetId', 'kind', 'path', 'bytes', 'sha256', 'verification']);
    assert(cohort.path.startsWith(`${cohort.targetId}/`));
    const actual = await digest(await originalFile(directory, cohort.path));
    assert.equal(actual.bytes, cohort.bytes); assert.equal(actual.sha256, cohort.sha256);
    const child = JSON.parse(await readFile(await originalFile(directory, cohort.path)));
    const target = selected.request.targets.find(value => value.id === cohort.targetId);
    let identities;
    if (cohort.kind === 'node-npm' || cohort.kind === 'native-npm') {
      assert.equal(target.ecosystem, 'npm');
      assert.equal(child.version, cohort.kind === 'node-npm' ? 'actql-package-release/0.1' : 'actql-native-cli-release/0.1');
      assert.equal(child.sourceSha, selected.request.source.commit);
      assert.equal(child.cohort.packageVersion, selected.version.version);
      assert.equal(child.cohort.registry, target.destination);
      assert(target.channels.includes(child.cohort.tag), 'Original cohort tag is not explicitly selected');
      identities = child.packages.map(item => ({targetId: target.id, ecosystem: 'npm', name: item.name,
        version: item.version, file: item.file, bytes: item.bytes, sha256: item.sha256, integrity: item.integrity,
        path: `${target.id}/${item.file}`}));
    } else if (cohort.kind === 'native-standalone') {
      assert.equal(target.ecosystem, 'native'); assert.equal(child.schemaVersion, 'actql-native-standalone/0.1');
      assert.equal(child.sourceSha, selected.request.source.commit); assert.equal(child.packageVersion, selected.version.version);
      assert.deepEqual(child.platforms, target.platforms); assert.deepEqual(child.requestedProfiles, target.profiles);
      identities = [...child.archives, child.checksums].map(item => ({targetId: target.id, ecosystem: 'native', name: item.name,
        version: item.version, file: item.file, bytes: item.bytes, sha256: item.sha256, path: `${target.id}/${item.file}`}));
    } else {
      assert.equal(cohort.kind, 'python-wheels'); assert.equal(target.ecosystem, 'pypi');
      assert.equal(child.source_sha, selected.request.source.commit);
      assert.equal(child.package_version, selected.version.pythonVersion);
      assert(target.platforms.includes(child.platform));
      identities = child.wheels.map(item => ({targetId: target.id, ecosystem: 'pypi', name: item.distribution,
        version: selected.version.pythonVersion, file: item.file, bytes: item.bytes, sha256: item.sha256,
        path: `${target.id}/${item.file}`}));
    }
    assert.deepEqual(manifest.artifacts.filter(value => value.targetId === target.id), identities,
      'Upper artifact identities differ from the complete original child manifest');
  }
  for (const target of selected.request.targets) {
    const records = manifest.artifacts.filter(value => value.targetId === target.id);
    assert.deepEqual(records.map(value => value.name), target.packages);
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
  return {manifest, sha256: manifestSha256};
}

// Registry observations are DATA, not approval/currentness or a publication
// command. Real ecosystem reobservation adapters still own their HTTP/auth
// semantics. A timeout/unavailable response cannot be supplied as absence.
export function resumeReleaseSet(fixed, observations) {
  assert.match(fixed.sha256, /^[a-f0-9]{64}$/u);
  assert(Array.isArray(observations) && observations.length === fixed.manifest.artifacts.length);
  const seen = new Set(), plan = [];
  for (const artifact of fixed.manifest.artifacts) {
    const key = `${artifact.targetId}/${artifact.file}`;
    const matches = observations.filter(value => value.targetId === artifact.targetId && value.file === artifact.file);
    assert.equal(matches.length, 1, 'Missing or duplicated original registry observation');
    const value = matches[0]; assert(!seen.has(key)); seen.add(key);
    assert(['absent', 'present', 'unknown', 'conflict'].includes(value.state), 'Unknown observation state');
    exact(value, ['targetId', 'file', 'state', ...(value.state === 'present' ? ['identity'] : [])]);
    if (value.state === 'present') {
      exact(value.identity, ['name', 'version', 'bytes', 'sha256', ...(artifact.ecosystem === 'npm' ? ['integrity'] : [])]);
      for (const field of Object.keys(value.identity)) assert.deepEqual(value.identity[field], artifact[field],
        `Occupied original artifact differs: ${key}/${field}`);
    }
    plan.push({targetId: artifact.targetId, file: artifact.file,
      action: value.state === 'present' ? 'reuse-identical' : value.state === 'absent' ? 'missing-same-bytes' : `stop-${value.state}`});
  }
  return {manifestSha256: fixed.sha256, blocked: plan.some(value => value.action.startsWith('stop-')), plan,
    qualification: 'supplied registry observation classification only; no upload, approval, retry or version selection'};
}

export function releaseSetSummary(fixed) {
  const escape = value => String(value).replace(/[\\`*_[\]<>]/gu, '\\$&');
  const {request, artifacts, acceptance} = fixed.manifest;
  const lines = [`# Candidate release ${escape(request.version)}`, '',
    `Source: ${request.source.commit} (${escape(request.source.branch)})`,
    `Manifest SHA256: ${fixed.sha256}`, `Acceptance: ${acceptance}`, '',
    'This is a fixed local candidate. No owner approval, public install, stage, upload or channel change is established.', '',
    escape(request.notes.summary), '', '| Target | Package | Version | File | Bytes | SHA256 |',
    '| --- | --- | --- | --- | ---: | --- |'];
  for (const item of artifacts) lines.push(`| ${escape(item.targetId)} | ${escape(item.name)} | ${escape(item.version)} | ${escape(item.file)} | ${item.bytes} | ${item.sha256} |`);
  for (const target of request.targets) lines.push('', `Target ${escape(target.id)}: ${escape(target.destination)}`,
    `Platforms: ${target.platforms.map(escape).join(', ')}; profiles: ${target.profiles.map(escape).join(', ')}; channels: ${target.channels.map(escape).join(', ') || '(none)'}`);
  for (const field of ['breakingChanges', 'migration', 'knownLimitations']) {
    lines.push('', `${field}:`);
    for (const value of request.notes[field]) lines.push(`- ${escape(value)}`);
  }
  return {manifestSha256: fixed.sha256, request: structuredClone(request), artifacts: structuredClone(artifacts),
    acceptance, markdown: `${lines.join('\n')}\n`};
}
