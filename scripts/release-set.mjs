// Bind existing ecosystem outputs; this layer never builds, authenticates,
// uploads or turns a local record into owner approval.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {copyFile, lstat, mkdir, open, readFile, realpath, writeFile} from 'node:fs/promises';
import {basename, dirname, join, resolve, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {admitReleaseRequest} from './release-policy.mjs';
import {releaseVersion} from './release-version.mjs';
import {requireNativeCohortPackageVersions} from './native-cli-artifact-reader.mjs';
import {promotionPlan, nativeLatestPromotionPlan} from './release-channels.mjs';

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
    if (descriptor.kind === 'native-npm') requireNativeCohortPackageVersions(manifest);
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
    requireNativeCohortPackageVersions(JSON.parse(manifest.origin.manifest));
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
  const manifest = JSON.parse(bytes); exact(manifest, ['schemaVersion', 'release', 'request', 'policy', 'cohorts', 'artifacts', 'acceptance', 'qualification',
    ...(Object.hasOwn(manifest, 'review') ? ['review'] : [])]);
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
  const review = Object.hasOwn(manifest, 'review') ? await verifyReview(directory, manifest) : null;
  return {manifest, sha256: manifestSha256, ...(review ? {review} : {})};
}

const reviewKinds = ['recipe', 'toolchain', 'build', 'acceptance', 'diff', 'signing'];
const literal = value => assert(typeof value === 'string' && value.length && value.length <= 4096 &&
  value === value.trim() && !/[\u0000-\u001f\u007f]/u.test(value), 'Expected bounded literal review text');
const uniqueList = value => {assert(Array.isArray(value)); assert.equal(new Set(value).size, value.length);};
const digestText = value => {assert.equal(typeof value, 'string'); assert.match(value, /^[a-f0-9]{64}$/u);};
const commitText = value => {assert.equal(typeof value, 'string'); assert.match(value, /^[a-f0-9]{40}$/u);};

function admitReview(request, manifest, originalSha256) {
  exact(request, ['schemaVersion', 'manifestSha256', 'evidence', 'provenance', 'environments', 'acceptance', 'changes', 'executionScope']);
  assert.equal(request.schemaVersion, 'actql-release-review-request/0.1');
  assert.equal(request.manifestSha256, originalSha256, 'Review request selects another preparation manifest');
  assert(Array.isArray(request.evidence) && request.evidence.length > 0 && request.evidence.length <= 128);
  const evidence = new Map(); let total = 0;
  for (const item of request.evidence) {
    exact(item, ['id', 'kind', 'file', 'bytes', 'sha256']);
    assert.equal(typeof item.id, 'string'); assert.match(item.id, /^[a-z][a-z0-9-]{0,63}$/u);
    assert(!evidence.has(item.id), 'Duplicate evidence id'); evidence.set(item.id, item);
    assert(reviewKinds.includes(item.kind)); literal(item.file);
    assert(!item.file.startsWith('/') && item.file.split('/').every(part => part && !['.', '..'].includes(part)));
    assert(Number.isSafeInteger(item.bytes) && item.bytes > 0 && item.bytes <= 64 * 1024 * 1024);
    total += item.bytes; assert(total <= 256 * 1024 * 1024); digestText(item.sha256);
  }
  const reference = (id, kind) => assert(evidence.has(id) && evidence.get(id).kind === kind, `Missing ${kind} evidence: ${id}`);
  const targets = manifest.request.targets, ids = targets.map(value => value.id);
  for (const field of ['provenance', 'environments']) {
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
      for (const key of ['runId', 'artifactId']) {assert.equal(typeof build[key], 'string'); assert.match(build[key], /^[1-9][0-9]*$/u);}
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
    for (const field of ['node', 'python']) if (item[field] !== null) literal(item[field]);
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
  else {commitText(request.changes.previousSource); reference(request.changes.diffEvidence, 'diff');}
  const scope = request.executionScope;
  exact(scope, ['publish', 'promote', 'resumeIdenticalMissing']);
  for (const field of ['publish', 'resumeIdenticalMissing']) {
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

async function checkedBytes(directory, record, maximum) {
  const path = await originalFile(directory, record.path);
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const before = await handle.stat();
    assert(before.isFile() && before.size > 0 && before.size <= maximum, 'Review file exceeds its explicit byte bound');
    const bytes = await handle.readFile();
    const after = await handle.stat();
    for (const key of ['dev', 'ino', 'size', 'mtimeMs', 'mode']) assert.equal(after[key], before[key]);
    assert.equal(bytes.length, before.size);
    if (record.bytes !== undefined) assert.equal(bytes.length, record.bytes);
    if (record.sha256 !== undefined) assert.equal(hash(bytes), record.sha256);
    return bytes;
  } finally {await handle.close();}
}

async function verifyReview(directory, manifest) {
  const binding = manifest.review; exact(binding, ['preparation', 'request', 'evidence']);
  const verify = async (record, path, maximum) => {
    exact(record, ['path', 'bytes', 'sha256']); assert.equal(record.path, path); digestText(record.sha256);
    return checkedBytes(directory, record, maximum);
  };
  const preparation = await verify(binding.preparation, 'review/preparation.json', 4 * 1024 * 1024);
  const {review, ...original} = manifest;
  assert.deepEqual(JSON.parse(preparation), original, 'Review enrichment changed the original preparation body');
  const request = admitReview(JSON.parse(await verify(binding.request, 'review/request.json', 1024 * 1024)), original, binding.preparation.sha256);
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

export async function prepareReleaseReview({directory, expectedSha256, reviewFile, destination}) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u);
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  assert(!Object.hasOwn(fixed.manifest, 'review'), 'A review-enriched set cannot be silently enriched again');
  directory = resolve(directory); reviewFile = resolve(reviewFile); destination = resolve(destination);
  const preparation = await checkedBytes(directory, {path: 'release-set.json', sha256: expectedSha256}, 4 * 1024 * 1024);
  const requestBytes = await checkedBytes(dirname(reviewFile), {path: basename(reviewFile)}, 1024 * 1024);
  const request = admitReview(JSON.parse(requestBytes), fixed.manifest, expectedSha256), payloads = [];
  for (const item of request.evidence) payloads.push({item, bytes: await checkedBytes(dirname(reviewFile),
    {path: item.file, bytes: item.bytes, sha256: item.sha256}, 64 * 1024 * 1024)});
  // Every supplied file and the original set validate before any destination is
  // created. Partial output on an I/O failure stays original failed evidence.
  await verifyReleaseSet(directory, {expectedSha256});
  await mkdir(destination);
  for (const item of [...fixed.manifest.cohorts, ...fixed.manifest.artifacts]) {
    const output = join(destination, item.path); await mkdir(dirname(output), {recursive: true});
    await copyFile(await originalFile(directory, item.path), output, constants.COPYFILE_EXCL);
    const actual = await digest(output); assert.equal(actual.bytes, item.bytes); assert.equal(actual.sha256, item.sha256);
  }
  await mkdir(join(destination, 'review/evidence'), {recursive: true});
  const put = async (path, bytes) => {await writeFile(join(destination, path), bytes, {flag: 'wx'}); return {path, bytes: bytes.length, sha256: hash(bytes)};};
  const review = {preparation: await put('review/preparation.json', preparation), request: await put('review/request.json', requestBytes), evidence: []};
  for (const {item, bytes} of payloads) review.evidence.push({id: item.id, ...await put(`review/evidence/${item.id}`, bytes)});
  const manifest = {...fixed.manifest, review}, bytes = json(manifest), sha256 = hash(bytes);
  await writeFile(join(destination, 'release-set.json'), bytes, {flag: 'wx'});
  await writeFile(join(destination, 'release-set.sha256'), `${sha256}  release-set.json\n`, {flag: 'wx'});
  await verifyReleaseSet(directory, {expectedSha256});
  return verifyReleaseSet(destination, {expectedSha256: sha256});
}

function admitPromotionReviewRequest(request, fixed, plan) {
  exact(request, ['schemaVersion', 'manifestSha256', 'publicInstallEvidence', 'limitations']);
  assert.equal(request.schemaVersion, 'actql-release-promotion-review-request/0.1');
  assert.equal(request.manifestSha256, fixed.sha256);
  assert(fixed.review, 'Original proposed promotion scope must already be bound');
  for (const transition of plan.transitions) assert(fixed.review.executionScope.promote.some(value =>
    value.targetId === transition.targetId && value.channel === transition.channel), 'Promotion exceeds the original proposed scope');
  const targets = [...new Set(plan.transitions.map(value => value.targetId))], ids = new Set(), covered = new Set();
  assert(Array.isArray(request.publicInstallEvidence) && request.publicInstallEvidence.length > 0 && request.publicInstallEvidence.length <= 128);
  let total = 0;
  for (const item of request.publicInstallEvidence) {
    exact(item, ['id', 'targetId', 'kind', 'file', 'bytes', 'sha256']);
    assert(typeof item.id === 'string' && /^[a-z][a-z0-9-]{0,63}$/u.test(item.id) && !ids.has(item.id), 'Invalid/duplicate public evidence id');
    ids.add(item.id); assert(targets.includes(item.targetId), 'Public evidence belongs to an unselected promotion target'); covered.add(item.targetId);
    // Each receipt stays with its actual public consumer and child kind.
    // There is no Native-npm/Python-to-Node or generic passed-flag conversion.
    const cohortKind=fixed.manifest.cohorts.find(value=>value.targetId===item.targetId)?.kind;
    assert((item.kind==='node-public-install'&&cohortKind==='node-npm')||
      (item.kind==='native-public-install'&&cohortKind==='native-standalone'),'No matching original public consumer receipt adapter for this evidence kind');
    literal(item.file);
    assert(!item.file.startsWith('/') && !item.file.includes('\\') && item.file.split('/').every(part => part && !['.', '..'].includes(part)));
    assert(Number.isSafeInteger(item.bytes) && item.bytes > 0 && item.bytes <= 64 * 1024 * 1024); digestText(item.sha256);
    total += item.bytes; assert(total <= 256 * 1024 * 1024, 'Public promotion evidence exceeds its existing review byte bound');
  }
  assert.deepEqual([...covered].sort(), targets.sort(), 'Every promoted target needs its original public install evidence');
  assert(Array.isArray(request.limitations)); request.limitations.forEach(literal);
  return structuredClone(request);
}

function nodePromotionReceiptIdentity(bytes, item, fixed) {
  const body = JSON.parse(bytes), target = fixed.manifest.request.targets.find(value => value.id === item.targetId);
  const cohort = fixed.manifest.cohorts.find(value => value.targetId === target.id);
  const artifacts = fixed.manifest.artifacts.filter(value => value.targetId === target.id), binding = body.releaseSetBinding;
  assert.deepEqual(artifacts.map(value => value.name), ['@actql/client-wire', '@actql/sdk', '@actql/local-node', '@actql/node'],
    'This receipt adapter is the actual original four-package Node consumer');
  assert.equal(body.version, 'actql-release-install-acceptance/0.1');
  assert.equal(body.sourceSha, fixed.manifest.request.source.commit);
  assert.equal(body.registry, 'https://registry.npmjs.org/');
  assert.equal(body.publicRegistryPublication, 'exact-original-bytes-observed-anonymously');
  assert(binding, 'Legacy child-only receipt cannot claim an upper release-set binding');
  assert.equal(binding.manifestSha256, fixed.sha256); assert.equal(binding.targetId, target.id);
  assert.equal(binding.cohortManifestSha256, cohort.sha256); assert.equal(body.cohortManifestSha256, cohort.sha256);
  assert.equal(binding.sourceSha, body.sourceSha); assert.equal(binding.version, fixed.manifest.release.version);
  assert.deepEqual(binding.requestedPlatforms, target.platforms); assert.deepEqual(binding.requestedProfiles, target.profiles);
  assert.deepEqual(binding.artifacts, artifacts.map(({name, version, file, bytes, sha256, integrity}) => ({name, version, file, bytes, sha256, integrity})));
  assert.deepEqual(body.artifacts, artifacts.map(({name, version, sha256, integrity}) => ({name, version, sha256, integrity})));
  for (const field of ['publicObservationFile', 'publicObservationAfterFile', 'publicRuntimeScope', 'node', 'platform', 'arch']) literal(body[field]);
  assert(body.approvalAcceptance && typeof body.approvalAcceptance === 'object'); literal(body.approvalAcceptance.status);
  return {id: item.id, targetId: item.targetId, kind: item.kind, manifestSha256: binding.manifestSha256,
    cohortManifestSha256: binding.cohortManifestSha256, node: body.node, platform: body.platform, arch: body.arch,
    publicRuntimeScope: body.publicRuntimeScope, declaredApprovalAcceptance: structuredClone(body.approvalAcceptance),
    qualification: 'original receipt identity correspondence only; actual trusted job, install, rows/current/close/profile and owner acceptance remain unproved'};
}

async function promotionReceiptIdentity(bytes,item,fixed,directory) {
  if(item.kind==='node-public-install')return nodePromotionReceiptIdentity(bytes,item,fixed);
  assert.equal(item.kind,'native-public-install');
  const body=JSON.parse(bytes),target=fixed.manifest.request.targets.find(value=>value.id===item.targetId);
  const cohort=fixed.manifest.cohorts.find(value=>value.targetId===target.id);assert.equal(cohort.kind,'native-standalone');
  assert.equal(body.schemaVersion,'actql-native-public-install/0.1');assert.equal(body.manifestSha256,fixed.sha256);assert.equal(body.targetId,target.id);
  const host=fixed.manifest.request.targets.find(value=>value.id===body.hostTargetId);
  assert(host?.ecosystem==='npm'&&host.id!==target.id);assert.equal(fixed.manifest.cohorts.find(value=>value.targetId===host.id)?.kind,'node-npm');
  assert(target.platforms.includes(body.platform));
  const {verifyNativeStandalone}=await import('./native-standalone-release.mjs');
  const standalone=await verifyNativeStandalone(dirname(join(directory,cohort.path)));
  assert.equal(standalone.sourceSha,fixed.manifest.request.source.commit);assert.equal(standalone.packageVersion,fixed.manifest.release.version);
  const artifact=JSON.parse(standalone.origin.manifest).artifacts.find(value=>value.platform===body.platform);
  const archive=standalone.archives.find(value=>value.platform===body.platform);assert(artifact&&archive);
  const artifacts=fixed.manifest.artifacts.filter(value=>value.targetId===target.id);
  assert.equal(body.download?.schemaVersion,'actql-native-public-download/0.1');assert.equal(body.download.manifestSha256,fixed.sha256);
  assert.equal(body.download.targetId,target.id);assert.equal(body.download.status,'verified');
  assert.deepEqual(body.download.files.map(value=>value.file),artifacts.map(value=>value.file));
  for(const [index,value]of body.download.files.entries()){
    assert.equal(value.expectedBytes,artifacts[index].bytes);assert.equal(value.retainedBytes,artifacts[index].bytes);
    assert.equal(value.expectedSha256,artifacts[index].sha256);assert.equal(value.status,'verified');
  }
  assert.equal(body.installed?.binarySha256,artifact.binarySha256);assert.equal(body.installed.binaryBytes,artifact.binaryBytes);
  assert.equal(body.installed.payloadFiles,archive.files.length);assert.equal(body.nativeEnvironment?.PATH,'');
  literal(body.nodeSupervisor);assert(Array.isArray(body.records)&&body.records.length);
  const version=body.records[0];assert.deepEqual(version.args,['--version']);assert.equal(version.stdout,`${standalone.packageVersion}\n`);
  assert.equal(version.code,0);assert.equal(version.signal,null);
  const {nativeStandaloneAcceptanceScope}=await import('./release-native-install.mjs');
  const scope=nativeStandaloneAcceptanceScope();assert.equal(body.acceptedScope,scope.acceptedScope);assert.deepEqual(body.unverified,scope.unverified);
  return {id:item.id,targetId:item.targetId,kind:item.kind,manifestSha256:fixed.sha256,cohortManifestSha256:cohort.sha256,
    hostTargetId:host.id,platform:body.platform,nodeSupervisor:body.nodeSupervisor,nativeBinarySha256:artifact.binarySha256,
    acceptedScope:body.acceptedScope,unverified:structuredClone(body.unverified),
    qualification:'Native public consumer identity/scope correspondence DATA only; actual trusted run, install, close and owner acceptance remain unproved'};
}

function checkedPromotionReviewPlan(fixed, plan, report, reportSha256) {
  assert(Array.isArray(plan.transitions));
  if(plan.schemaVersion==='actql-native-latest-promotion-plan/0.1'){
    assert.equal(plan.transitions.length,1);const {targetId,before}=plan.transitions[0];
    assert.deepEqual(nativeLatestPromotionPlan(fixed,{targetId,before},report,reportSha256),plan,'Native Latest plan changed from its exact original report/transition');
    return plan;
  }
  const moves = plan.transitions.map(({targetId, name, channel, expectedVersion}) => ({targetId, name, channel, expectedVersion}));
  assert.deepEqual(promotionPlan(fixed, moves, report, reportSha256), plan,
    'Promotion plan differs from its exact original fixed set, channel report or transition');
  return plan;
}

// Post-publication evidence cannot be inserted into the SAME manifest whose
// digest that receipt names. Keep a distinct external review bundle instead:
// original fixed SHA + exact plan/report + raw public receipts. This supplies
// no approval, current channel proof, CAS, credential or mutation route.
export async function prepareReleasePromotionReview({directory, expectedSha256, planFile, channelReportFile, reviewFile, destination}) {
  digestText(expectedSha256); directory = resolve(directory); destination = resolve(destination);
  const originalRoot = await realpath(directory), output = join(await realpath(dirname(destination)), basename(destination));
  assert(output !== originalRoot && !output.startsWith(`${originalRoot}${sep}`), 'Post-freeze promotion review must be outside the original fixed set');
  destination = output;
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const read = (file, maximum) => checkedBytes(dirname(resolve(file)), {path: basename(file)}, maximum);
  const planBytes = await read(planFile, 4 * 1024 * 1024), reportBytes = await read(channelReportFile, 4 * 1024 * 1024);
  const plan = checkedPromotionReviewPlan(fixed, JSON.parse(planBytes), JSON.parse(reportBytes), hash(reportBytes));
  const requestBytes = await read(reviewFile, 1024 * 1024);
  const request = admitPromotionReviewRequest(JSON.parse(requestBytes), fixed, plan), payloads = [];
  for (const item of request.publicInstallEvidence) {
    const bytes = await checkedBytes(dirname(resolve(reviewFile)), {path: item.file, bytes: item.bytes, sha256: item.sha256}, 64 * 1024 * 1024);
    await promotionReceiptIdentity(bytes, item, fixed, directory); payloads.push({item, bytes});
  }
  await verifyReleaseSet(directory, {expectedSha256});
  await mkdir(destination); await mkdir(join(destination, 'evidence'));
  const put = async (path, bytes) => {await writeFile(join(destination, path), bytes, {flag: 'wx'}); return {path, bytes: bytes.length, sha256: hash(bytes)};};
  const header = {schemaVersion: 'actql-release-promotion-review/0.1', manifestSha256: fixed.sha256,
    plan: await put('plan.json', planBytes), channelReport: await put('channel-report.json', reportBytes),
    request: await put('request.json', requestBytes), evidence: [], acceptance: 'unaccepted'};
  for (const {item, bytes} of payloads) header.evidence.push({id: item.id, ...await put(`evidence/${item.id}`, bytes)});
  const bytes = json(header), sha256 = hash(bytes);
  await writeFile(join(destination, 'promotion-review.json'), bytes, {flag: 'wx'});
  await writeFile(join(destination, 'promotion-review.sha256'), `${sha256}  promotion-review.json\n`, {flag: 'wx'});
  await verifyReleaseSet(directory, {expectedSha256});
  return verifyReleasePromotionReview({directory, expectedSha256, reviewDirectory: destination, expectedReviewSha256: sha256});
}

export async function verifyReleasePromotionReview({directory, expectedSha256, reviewDirectory, expectedReviewSha256}) {
  digestText(expectedSha256); digestText(expectedReviewSha256); reviewDirectory = resolve(reviewDirectory);
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const original = await checkedBytes(reviewDirectory, {path: 'promotion-review.json', sha256: expectedReviewSha256}, 4 * 1024 * 1024);
  const header = JSON.parse(original);
  exact(header, ['schemaVersion', 'manifestSha256', 'plan', 'channelReport', 'request', 'evidence', 'acceptance']);
  assert.equal(header.schemaVersion, 'actql-release-promotion-review/0.1'); assert.equal(header.manifestSha256, fixed.sha256);
  assert.equal(header.acceptance, 'unaccepted');
  const read = async (record, path, maximum) => {
    exact(record, ['path', 'bytes', 'sha256']); assert.equal(record.path, path); digestText(record.sha256);
    assert(Number.isSafeInteger(record.bytes) && record.bytes > 0 && record.bytes <= maximum);
    return checkedBytes(reviewDirectory, record, maximum);
  };
  const planBytes = await read(header.plan, 'plan.json', 4 * 1024 * 1024), reportBytes = await read(header.channelReport, 'channel-report.json', 4 * 1024 * 1024);
  const plan = checkedPromotionReviewPlan(fixed, JSON.parse(planBytes), JSON.parse(reportBytes), hash(reportBytes));
  const request = admitPromotionReviewRequest(JSON.parse(await read(header.request, 'request.json', 1024 * 1024)), fixed, plan);
  assert.deepEqual(header.evidence.map(value => value.id), request.publicInstallEvidence.map(value => value.id));
  const publicEvidence = [];
  for (const [index, item] of request.publicInstallEvidence.entries()) {
    const {id, ...record} = header.evidence[index]; assert.equal(record.bytes, item.bytes); assert.equal(record.sha256, item.sha256);
    publicEvidence.push(await promotionReceiptIdentity(await read(record, `evidence/${id}`, 64 * 1024 * 1024), item, fixed, directory));
  }
  const detached = await checkedBytes(reviewDirectory, {path: 'promotion-review.sha256'}, 128);
  assert.equal(detached.toString('utf8'), `${expectedReviewSha256}  promotion-review.json\n`);
  assert.deepEqual(await checkedBytes(reviewDirectory, {path: 'promotion-review.json', sha256: expectedReviewSha256}, 4 * 1024 * 1024), original);
  await verifyReleaseSet(directory, {expectedSha256});
  return {fixed, header, sha256: expectedReviewSha256, plan, request, publicEvidence, acceptance: 'unaccepted'};
}

export function releasePromotionReviewSummary(checked) {
  const escape = value => String(value).replace(/[\\`*_[\]<>|]/gu, '\\$&');
  const candidate = releaseSetSummary(checked.fixed), lines = [candidate.markdown,
    '## Separate post-freeze promotion review', '', `Promotion review SHA256: ${checked.sha256}`,
    `Original fixed manifest SHA256: ${checked.fixed.sha256}`,
    `Plan SHA256: ${checked.header.plan.sha256}`,
    `Channel report SHA256: ${checked.header.channelReport.sha256}`,
    `Request SHA256: ${checked.header.request.sha256}`, 'Acceptance: unaccepted', '',
    'Public receipts refer to the original frozen set; no artifact or original review field was changed.',
    'All receipt claims and identity correspondence remain DATA. No trusted job, actual public install, current value, owner approval, lease or mutation is certified.', '',
    '| Target | Package | Channel | Expected prior version | Proposed version |', '| --- | --- | --- | --- | --- |'];
  for (const item of checked.plan.transitions) lines.push(`| ${escape(item.targetId)} | ${escape(item.name)} | ${escape(item.channel)} | ${escape(item.before?.state==='unassigned-or-selected'?`conditional: unassigned or release ${item.before.releaseId}`:item.expectedVersion ?? '(absent)')} | ${escape(item.toVersion)} |`);
  lines.push('', '| Public receipt | Target | Kind | Bytes | SHA256 |', '| --- | --- | --- | ---: | --- |');
  for (const item of checked.request.publicInstallEvidence) lines.push(`| ${escape(item.id)} | ${escape(item.targetId)} | ${escape(item.kind)} | ${item.bytes} | ${item.sha256} |`);
  for (const item of checked.publicEvidence) {
    if(item.kind==='native-public-install'){
      lines.push('',`Public Native receipt ${escape(item.id)} (${escape(item.targetId)}):`,
        `Child SHA256: ${item.cohortManifestSha256}; Native binary SHA256: ${item.nativeBinarySha256}`,
        `Declared supervisor/platform/Host: ${escape(JSON.stringify([item.nodeSupervisor,item.platform,item.hostTargetId]))}`,
        `Declared completed scope: ${escape(item.acceptedScope)}`,...item.unverified.map(value=>`- Unverified: ${escape(value)}`));
      continue;
    }
    lines.push('', `Public receipt ${escape(item.id)} (${escape(item.targetId)}):`,
    `Child SHA256: ${item.cohortManifestSha256}; observed Node/OS: ${escape(JSON.stringify([item.node, item.platform, item.arch]))}`,
    `Declared business scope: ${escape(JSON.stringify(item.publicRuntimeScope))}`,
    `Declared approval acceptance (not promoted): ${escape(JSON.stringify(item.declaredApprovalAcceptance))}`);
  }
  lines.push('', 'Post-freeze limitations (supplied DATA):',
    ...checked.request.limitations.map(value => `- ${escape(value)}`));
  lines.push('', 'A separate protected owner decision must bind this bundle and the original fixed set. Actual channel values must be checked under the exclusive executor before any later mutation.');
  return {manifestSha256: checked.fixed.sha256, promotionReviewSha256: checked.sha256,
    acceptance: 'unaccepted', header: structuredClone(checked.header),
    plan: structuredClone(checked.plan), request: structuredClone(checked.request),
    publicEvidence: structuredClone(checked.publicEvidence), candidate, markdown: `${lines.join('\n')}\n`};
}

export async function readFrozenReleaseArtifact(directory, expectedSha256, targetId, file) {
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const artifact = fixed.manifest.artifacts.find(value => value.targetId === targetId && value.file === file);
  assert(artifact, 'Select one exact frozen release artifact');
  const bytes = await checkedBytes(resolve(directory), {path: artifact.path, bytes: artifact.bytes, sha256: artifact.sha256}, artifact.bytes);
  await verifyReleaseSet(directory, {expectedSha256});
  return {artifact: structuredClone(artifact), bytes};
}

// Deterministic proposed Draft metadata from the same fixed presentation DATA.
// This is neither owner approval nor a publication/channel operation.
export function nativeReleaseDraftRequest(fixed, targetId) {
  const {manifest} = fixed, target = manifest.request.targets.find(value => value.id === targetId);
  assert.equal(target?.ecosystem, 'native'); assert.equal(target.destination, 'https://github.com/actql/actql');
  assert.equal(manifest.request.targets.filter(value => value.ecosystem === 'native').length, 1,
    'One GitHub release must contain its complete selected Native target');
  const artifacts = manifest.artifacts.filter(value => value.targetId === targetId);
  const lines = [`ActQL ${manifest.release.version}`, '', manifest.request.notes.summary, '',
    `Source: ${manifest.request.source.repository}/commit/${manifest.request.source.commit}`,
    `Release-set SHA256: ${fixed.sha256}`, `Platforms: ${target.platforms.join(', ')}`,
    `Requested profiles: ${target.profiles.join(', ')}`, '',
    'Profile/platform availability is limited to the exact bound acceptance evidence; artifact presence alone does not certify support.'];
  for (const field of ['breakingChanges', 'migration', 'knownLimitations']) {
    lines.push('', `${field}:`, ...manifest.request.notes[field].map(value => `- ${value}`));
  }
  lines.push('', 'Artifact SHA256:');
  for (const artifact of artifacts) lines.push(`${artifact.sha256}  ${artifact.file} (${artifact.bytes} bytes)`);
  if (fixed.review) for (const item of fixed.review.acceptance.filter(value => value.targetId === targetId))
    lines.push('', `Supplied ${item.phase}: ${item.status}; original evidence: ${item.evidence.join(', ') || '(none)'}`,
      ...item.limitations.map(value => `- ${value}`));
  const body = `${lines.join('\n')}\n`;
  assert(Buffer.byteLength(body) <= 65536, 'Native release presentation exceeds its finite bound');
  return {tag_name: manifest.release.gitTag, target_commitish: manifest.request.source.commit,
    name: `ActQL ${manifest.release.version}`, body, draft: true, prerelease: manifest.release.prerelease,
    generate_release_notes: false, make_latest: 'false'};
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
  if (fixed.review) {
    const supplied = fixed.review;
    lines.push('', '## Bound review evidence and proposed scope', '',
      `Original preparation SHA256: ${supplied.manifestSha256}`, '',
      'All provenance, environment and result labels below are supplied review DATA, not independently verified claims or owner approval.',
      'A local build has no hosted immutable artifact ID. A passed label does not promote acceptance. The protected reviewer must inspect the bound original evidence.', '',
      `Proposed publish targets: ${supplied.executionScope.publish.map(escape).join(', ') || '(none)'}`,
      `Proposed identical-missing resume targets: ${supplied.executionScope.resumeIdenticalMissing.map(escape).join(', ') || '(none)'}`,
      `Proposed promotion: ${supplied.executionScope.promote.map(item => `${escape(item.targetId)}/${escape(item.channel)}`).join(', ') || '(none)'}`, '',
      `Previous source: ${supplied.changes.previousSource || '(none supplied)'}`, `Diff evidence: ${escape(supplied.changes.diffEvidence || '(none supplied)')}`);
    for (const item of supplied.provenance) lines.push('', `Build provenance ${escape(item.targetId)} (supplied):`,
      `Recipe: ${escape(item.recipeEvidence)}; toolchain: ${escape(item.toolchainEvidence)}`,
      `Build: ${escape(JSON.stringify(item.build))}`);
    for (const item of supplied.environments) lines.push('', `Environment ${escape(item.targetId)} (declared, not certified):`,
      `Platforms: ${item.platforms.map(escape).join(', ')}; profiles: ${item.profiles.map(escape).join(', ')}`,
      `Node: ${escape(item.node ?? '(not declared)')}; Python: ${escape(item.python ?? '(not declared)')}; ABI: ${escape(item.abi)}`,
      ...item.limitations.map(value => `- ${escape(value)}`));
    for (const item of supplied.acceptance) lines.push('',
      `Reported ${escape(item.targetId)}/${escape(item.phase)}: ${escape(item.status)}; evidence: ${item.evidence.map(escape).join(', ') || '(none)'}`,
      ...item.limitations.map(value => `- ${escape(value)}`));
    lines.push('', '| Evidence | Kind | Bytes | SHA256 |', '| --- | --- | ---: | --- |');
    for (const item of supplied.evidence) lines.push(`| ${escape(item.id)} | ${escape(item.kind)} | ${item.bytes} | ${item.sha256} |`);
    lines.push('', 'Execution remains unavailable without independent owner approval, protected validator/policy and actual current execution checks.');
  } else lines.push('', 'Review evidence and explicit execution scope are not bound. This preparation alone is not a complete approval presentation.');
  return {manifestSha256: fixed.sha256, request: structuredClone(request), artifacts: structuredClone(artifacts),
    acceptance, review: fixed.review ? structuredClone(fixed.review) : null, markdown: `${lines.join('\n')}\n`};
}
