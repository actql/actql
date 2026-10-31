// Cold inert bytes and supplied review claims only; no build, executable,
// product install, trusted approval or external publication is exercised.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile, rm, symlink, lstat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {releaseVersion} from './release-version.mjs';
import {prepareReleaseReview, releaseSetSummary, verifyReleaseSet} from './release-set.mjs';
import {runRelease} from './release.mjs';

const sha = value => createHash('sha256').update(value).digest('hex');
const wire = value => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'actql-release-review-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const directory = join(root, 'preparation'), inputs = join(root, 'inputs'), destination = join(root, 'reviewed');
  await mkdir(join(directory, 'node'), {recursive: true}); await mkdir(inputs);
  const source = 'a'.repeat(40), version = '0.0.7-rc.1', payload = Buffer.from('Independent inert release review fixture\n');
  const artifact = {targetId: 'node', ecosystem: 'npm', name: '@actql/node', version,
    file: 'actql-node-0.0.7-rc.1.tgz', bytes: payload.length, sha256: sha(payload),
    integrity: `sha512-${createHash('sha512').update(payload).digest('base64')}`, path: 'node/actql-node-0.0.7-rc.1.tgz'};
  await writeFile(join(directory, artifact.path), payload);
  const child = wire({version: 'actql-package-release/0.1', sourceSha: source,
    cohort: {packageVersion: version, registry: 'https://registry.npmjs.org/', tag: 'candidate-synthetic'}, packages: [artifact]});
  await writeFile(join(directory, 'node/release.json'), child);
  const manifest = {schemaVersion: 'actql-release-set/0.1', release: releaseVersion(version),
    request: {schemaVersion: 'actql-release-request/0.1', releaseId: 'synthetic-review-only', version,
      source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'},
      targets: [{id: 'node', ecosystem: 'npm', packages: ['@actql/node'], platforms: ['darwin-arm64'], profiles: ['local'],
        destination: 'https://registry.npmjs.org/', channels: ['candidate-synthetic']}],
      notes: {summary: 'Not a product release choice', breakingChanges: [], migration: [], knownLimitations: ['Inert fixture only']}},
    policy: {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'], publicationAuthority: 'external-owner-approval-required'},
    cohorts: [{targetId: 'node', kind: 'node-npm', path: 'node/release.json', bytes: child.length, sha256: sha(child),
      verification: 'Independent cold-byte fixture, not full producer acceptance'}], artifacts: [artifact],
    acceptance: 'unaccepted', qualification: 'Independent review transport fixture only'};
  const original = wire(manifest), digest = sha(original);
  await writeFile(join(directory, 'release-set.json'), original);
  await writeFile(join(directory, 'release-set.sha256'), `${digest}  release-set.json\n`);
  const evidence = [];
  for (const kind of ['recipe', 'toolchain', 'build', 'acceptance', 'diff']) {
    const bytes = Buffer.from(`Independent original ${kind} evidence, not product acceptance\n`), file = `${kind}.txt`;
    await writeFile(join(inputs, file), bytes);
    evidence.push({id: `${kind}-original`, kind, file, bytes: bytes.length, sha256: sha(bytes)});
  }
  const request = {schemaVersion: 'actql-release-review-request/0.1', manifestSha256: digest, evidence,
    provenance: [{targetId: 'node', recipeEvidence: 'recipe-original', toolchainEvidence: 'toolchain-original',
      build: {kind: 'local', run: 'synthetic-local-run', artifactId: null, evidence: 'build-original'}}],
    environments: [{targetId: 'node', platforms: ['darwin-arm64'], profiles: ['local'], node: '>=22.14.0 <23', python: null,
      abi: 'Synthetic ABI declaration only', limitations: ['No real executable or platform acceptance']}],
    acceptance: [{targetId: 'node', phase: 'prepublication-install', status: 'passed', evidence: ['acceptance-original'],
      limitations: ['Supplied label only, deliberately not an independently accepted condition']},
    {targetId: 'node', phase: 'public-install', status: 'not-run', evidence: [], limitations: ['No public version selected']}],
    changes: {previousSource: 'b'.repeat(40), diffEvidence: 'diff-original'},
    executionScope: {publish: ['node'], promote: [{targetId: 'node', channel: 'candidate-synthetic'}], resumeIdenticalMissing: ['node']}};
  const reviewFile = join(inputs, 'review-request.json');
  const save = async () => writeFile(reviewFile, wire(request)); await save();
  return {root, directory, inputs, destination, manifest, original, digest, request, reviewFile, save,
    prepare: (output = destination) => prepareReleaseReview({directory, expectedSha256: digest, reviewFile, destination: output})};
}

async function absent(path) {await assert.rejects(lstat(path), {code: 'ENOENT'});}

test('release review: CLI creates a distinct bound evidence set and both summaries without mutating or approving preparation', async t => {
  const f = await fixture(t), input = await readFile(f.reviewFile);
  const result = await runRelease(['review', f.directory, f.digest, f.reviewFile, f.destination]);
  assert.notEqual(result.sha256, f.digest); assert.equal(result.manifest.acceptance, 'unaccepted');
  assert.deepEqual(await readFile(join(f.directory, 'release-set.json')), f.original);
  assert.deepEqual(await readFile(f.reviewFile), input);
  assert.deepEqual(await readFile(join(f.destination, 'review/preparation.json')), f.original);
  assert.deepEqual(await readFile(join(f.destination, 'review/request.json')), input);
  const {review, ...base} = result.manifest; assert.deepEqual(base, f.manifest);
  for (const item of f.request.evidence) assert.deepEqual(await readFile(join(f.inputs, item.file)),
    await readFile(join(f.destination, `review/evidence/${item.id}`)));
  const summary = await runRelease(['summary', f.destination, result.sha256]);
  assert.deepEqual(summary.review, f.request); assert.equal(summary.acceptance, 'unaccepted');
  assert.match(summary.markdown, /not independently verified claims or owner approval/u);
  assert.match(summary.markdown, /local build has no hosted immutable artifact ID/u);
  assert.match(summary.markdown, /Reported node\/public-install: not-run/u);
  assert.match(summary.markdown, /Proposed identical-missing resume targets: node/u);
  assert(summary.markdown.includes(f.request.evidence[0].sha256));
  await assert.rejects(verifyReleaseSet(f.destination, {expectedSha256: f.digest}), /externally retained digest/u);
  await assert.rejects(runRelease(['publish', f.destination]), /publication authority/u);
});

test('release review: explicit build identity, complete environment/result inventory and exact evidence references are required before output', async t => {
  const f = await fixture(t), original = structuredClone(f.request);
  const variants = [value => {delete value.provenance[0].recipeEvidence;},
    value => {value.provenance[0].build.artifactId = 'invented-hosted-id';},
    value => {value.environments = [];}, value => {value.environments[0].platforms = ['linux-x64-gnu'];},
    value => {value.acceptance.pop();}, value => {value.acceptance[0].evidence = [];},
    value => {value.acceptance[0].evidence = ['recipe-original'];}, value => {value.provenance[0].toolchainEvidence = 'missing';}];
  for (const [index, change] of variants.entries()) {
    const value = structuredClone(original); change(value); await writeFile(f.reviewFile, wire(value));
    const output = join(f.root, `invalid-${index}`); await assert.rejects(f.prepare(output)); await absent(output);
  }
});

test('release review: hosted run attempt and immutable artifact identity are bound claims, not approval or API verification', async t => {
  const f = await fixture(t);
  f.request.provenance[0].build = {kind: 'github-actions', repository: 'https://github.com/actql/actql',
    runId: '12345', attempt: 2, artifactId: '67890', artifactSha256: 'c'.repeat(64), evidence: 'build-original'};
  await f.save();
  const result = await f.prepare(); assert.equal(result.manifest.acceptance, 'unaccepted');
  assert.deepEqual(result.review.provenance[0].build, f.request.provenance[0].build);
  f.request.provenance[0].build.attempt = 0; await f.save();
  await assert.rejects(f.prepare(join(f.root, 'bad-attempt'))); await absent(join(f.root, 'bad-attempt'));
  f.request.provenance[0].build.attempt = 2; f.request.provenance[0].build.repository = 'https://github.com/foreign/repo'; await f.save();
  await assert.rejects(f.prepare(join(f.root, 'foreign-build'))); await absent(join(f.root, 'foreign-build'));
});

test('release review: proposed publish/promotion/resume scope cannot exceed the original selected target and channel', async t => {
  const f = await fixture(t), original = structuredClone(f.request);
  for (const [index, scope] of [
    {publish: ['foreign'], promote: [], resumeIdenticalMissing: []},
    {publish: ['node'], promote: [{targetId: 'node', channel: 'latest'}], resumeIdenticalMissing: []},
    {publish: [], promote: [{targetId: 'node', channel: 'candidate-synthetic'}], resumeIdenticalMissing: ['node']},
    {publish: [], promote: [], resumeIdenticalMissing: []},
  ].entries()) {
    f.request.executionScope = scope; await f.save(); const output = join(f.root, `scope-${index}`);
    await assert.rejects(f.prepare(output)); await absent(output);
  }
  Object.assign(f.request, original, {approved: true}); await f.save();
  await assert.rejects(f.prepare()); await absent(f.destination);
});

test('release review: missing, changed and symlinked original evidence are refused without creating a review set', async t => {
  const f = await fixture(t), file = join(f.inputs, 'recipe.txt'), bytes = await readFile(file);
  await writeFile(file, Buffer.alloc(bytes.length, 65)); await assert.rejects(f.prepare()); await absent(f.destination);
  await rm(file); await assert.rejects(f.prepare()); await absent(f.destination);
  const keeper = join(f.inputs, 'exact-recipe-keeper.txt'); await writeFile(keeper, bytes); await symlink(keeper, file);
  await assert.rejects(f.prepare(), /symlink/u); await absent(f.destination);
});

test('release review: final raw request/evidence and original preparation bindings are reobserved on cold verification', async t => {
  const f = await fixture(t), result = await f.prepare();
  for (const path of ['review/request.json', 'review/preparation.json', 'review/evidence/recipe-original']) {
    const absolute = join(f.destination, path), original = await readFile(absolute);
    await writeFile(absolute, Buffer.alloc(original.length, 65));
    await assert.rejects(verifyReleaseSet(f.destination, {expectedSha256: result.sha256}));
    await writeFile(absolute, original);
  }
  assert.equal((await verifyReleaseSet(f.destination, {expectedSha256: result.sha256})).sha256, result.sha256);
});

test('release review: changed evidence or execution proposal receives a new final digest, and recursive enrichment is refused', async t => {
  const f = await fixture(t), first = await f.prepare();
  f.request.executionScope.resumeIdenticalMissing = []; await f.save();
  const second = await f.prepare(join(f.root, 'different-proposal')); assert.notEqual(second.sha256, first.sha256);
  assert.equal(first.manifest.artifacts[0].sha256, second.manifest.artifacts[0].sha256);
  const output = join(f.root, 'recursive');
  await assert.rejects(prepareReleaseReview({directory: f.destination, expectedSha256: first.sha256, reviewFile: f.reviewFile, destination: output}), /enriched again/u);
  await absent(output);
  await assert.rejects(f.prepare(f.destination), {code: 'EEXIST'});
  assert.equal((await verifyReleaseSet(f.destination, {expectedSha256: first.sha256})).sha256, first.sha256);
});

test('release review: legacy fixed preparation remains readable but explicitly lacks a complete approval presentation', async t => {
  const f = await fixture(t), fixed = await verifyReleaseSet(f.directory, {expectedSha256: f.digest});
  const summary = releaseSetSummary(fixed);
  assert.equal(summary.review, null); assert.match(summary.markdown, /not a complete approval presentation/u);
  assert.equal(fixed.manifest.acceptance, 'unaccepted');
});

test('release review: existing anonymous observer consumes the new digest and rejects evidence mutation during its original read window', async t => {
  const f = await fixture(t), fixed = await f.prepare(), artifact = fixed.manifest.artifacts[0];
  const payload = await readFile(join(f.directory, artifact.path)); let mutate = false;
  const metadata = 'https://registry.npmjs.org/%40actql%2Fnode/0.0.7-rc.1';
  const binary = 'https://registry.npmjs.org/@actql/node/-/node-0.0.7-rc.1.tgz';
  const calls = [];
  t.mock.method(globalThis, 'fetch', async (url, options) => {
    calls.push(url); assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit');
    assert.equal(options.headers.authorization, undefined);
    if (url === metadata) {
      if (mutate) await writeFile(join(f.destination, 'review/evidence/build-original'), 'Changed evidence during HTTP observation');
      return Response.json({name: artifact.name, version: artifact.version, dist: {integrity: artifact.integrity, tarball: binary}});
    }
    assert.equal(url, binary); return new Response(payload);
  });
  const observation = await runRelease(['observe', f.destination, fixed.sha256]);
  assert.equal(observation.manifestSha256, fixed.sha256); assert.equal(observation.plan.blocked, false);
  assert.deepEqual(calls, [metadata, binary]); mutate = true;
  await assert.rejects(runRelease(['observe', f.destination, fixed.sha256]));
});

test('release review: request and evidence bounds, traversal and invalid ids stop before output without altering inputs', async t => {
  const f = await fixture(t), original = await readFile(f.reviewFile);
  await writeFile(f.reviewFile, Buffer.alloc(1024 * 1024 + 1, 32)); await assert.rejects(f.prepare()); await absent(f.destination);
  await writeFile(f.reviewFile, original);
  for (const [index, changes] of [{file: '../recipe.txt'}, {id: '../foreign'}, {bytes: 64 * 1024 * 1024 + 1}].entries()) {
    const value = structuredClone(f.request); Object.assign(value.evidence[0], changes);
    await writeFile(f.reviewFile, wire(value)); const output = join(f.root, `bounded-${index}`);
    await assert.rejects(f.prepare(output)); await absent(output);
  }
  assert.deepEqual(await readFile(join(f.directory, 'release-set.json')), f.original);
});

test('release review: one coherent Node/Python/standalone set preserves each original child and all ordered evidence scopes', async t => {
  const f = await fixture(t), source = f.manifest.request.source.commit, version = f.manifest.request.version;
  const groups = [
    {id: 'python', ecosystem: 'pypi', packages: ['actql-sdk'], platforms: ['darwin-arm64'], profiles: ['remote'],
      destination: 'https://upload.pypi.org/legacy/', channels: []},
    {id: 'native', ecosystem: 'native', packages: ['actql-linux-x64-gnu', 'actql-checksums'], platforms: ['linux-x64-gnu'], profiles: ['remote'],
      destination: 'https://github.com/actql/actql', channels: ['candidate-synthetic']},
  ];
  for (const target of groups) {
    await mkdir(join(f.directory, target.id));
    const files = target.id === 'python' ? ['actql_sdk-0.0.7rc1-py3-none-any.whl'] : ['actql-0.0.7-rc.1-linux-x64-gnu.tar.gz', 'SHA256SUMS'];
    const artifacts = [];
    for (const [index, file] of files.entries()) {
      const bytes = Buffer.from(`Independent inert ${target.id}/${file} review bytes only\n`);
      const artifact = {targetId: target.id, ecosystem: target.ecosystem, name: target.packages[index],
        version: target.id === 'python' ? '0.0.7rc1' : version, file, bytes: bytes.length, sha256: sha(bytes), path: `${target.id}/${file}`};
      await writeFile(join(f.directory, artifact.path), bytes); artifacts.push(artifact);
    }
    const child = target.id === 'python' ? {source_sha: source, package_version: '0.0.7rc1', platform: 'darwin-arm64',
      wheels: artifacts.map(item => ({distribution: item.name, file: item.file, bytes: item.bytes, sha256: item.sha256}))}
      : {schemaVersion: 'actql-native-standalone/0.1', sourceSha: source, packageVersion: version, platforms: target.platforms,
        requestedProfiles: target.profiles, archives: artifacts.slice(0, -1), checksums: artifacts.at(-1)};
    const path = `${target.id}/${target.id === 'python' ? 'cohort.json' : 'native-standalone.json'}`, bytes = wire(child);
    await writeFile(join(f.directory, path), bytes);
    f.manifest.request.targets.push(target); f.manifest.artifacts.push(...artifacts);
    f.manifest.cohorts.push({targetId: target.id, kind: target.id === 'python' ? 'python-wheels' : 'native-standalone',
      path, bytes: bytes.length, sha256: sha(bytes), verification: 'Inert multi-entry cold-byte fixture only'});
    f.request.provenance.push({...structuredClone(f.request.provenance[0]), targetId: target.id});
    f.request.environments.push({targetId: target.id, platforms: target.platforms, profiles: target.profiles, node: null,
      python: target.id === 'python' ? '>=3.12 <3.13' : null, abi: 'Supplied inert declaration, not Linux or runtime support', limitations: ['No executable/install']});
    f.request.acceptance.push(...f.request.acceptance.slice(0, 2).map(item => ({...structuredClone(item), targetId: target.id})));
    f.request.executionScope.publish.push(target.id); f.request.executionScope.resumeIdenticalMissing.push(target.id);
  }
  const original = wire(f.manifest), digest = sha(original);
  await writeFile(join(f.directory, 'release-set.json'), original);
  await writeFile(join(f.directory, 'release-set.sha256'), `${digest}  release-set.json\n`);
  f.request.manifestSha256 = digest; await f.save();
  const result = await prepareReleaseReview({directory: f.directory, expectedSha256: digest, reviewFile: f.reviewFile, destination: f.destination});
  assert.deepEqual(result.manifest.artifacts, f.manifest.artifacts); assert.equal(result.manifest.cohorts.length, 3);
  assert.deepEqual(result.review.provenance.map(item => item.targetId), ['node', 'python', 'native']);
  assert.equal(result.review.acceptance.length, 6); assert.equal(result.manifest.acceptance, 'unaccepted');
  for (const item of [...f.manifest.cohorts, ...f.manifest.artifacts]) assert.deepEqual(await readFile(join(f.directory, item.path)), await readFile(join(f.destination, item.path)));
  const summary = releaseSetSummary(result);
  assert.deepEqual(summary.review, f.request); assert.match(summary.markdown, /Reported native\/public-install: not-run/u);
  assert.deepEqual(await readFile(join(f.directory, 'release-set.json')), original);
});
