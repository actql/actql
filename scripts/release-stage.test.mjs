// Real existing archive/fixed-set owners with inert payloads; every registry
// and npm stage operation is an injected component port. No trust, approval,
// actual stage, 2FA, publisher credential or product runtime is exercised.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, cp, lstat, mkdir, mkdtemp, readFile, readdir, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test, {before, after} from 'node:test';
import {inspect} from 'node:util';
import {admitCohort, stagePackage, inventory} from './package-release.mjs';
import {freezeReleaseSet, prepareReleaseReview, verifyReleaseSet} from './release-set.mjs';
import {publicConsumerEnvironment} from './release-public-install.mjs';
import {observeNpmStageTarget} from './release-registry.mjs';
import {npmStagePlan, stagePackageRelease, npmStageApprovalPlan, approveStagedPackageRelease} from './publish-package-release.mjs';
import {runRelease} from './release.mjs';

const registry = 'https://registry.npmjs.org/', hash = bytes => createHash('sha256').update(bytes).digest('hex');
let root, preparation, reviewFile, reviewRequest, reviewed;

before(async () => {
  root = await mkdtemp(join(tmpdir(), 'actql-stage-protocol-'));
  const cohortDirectory = join(root, 'cohort'), development = join(cohortDirectory, 'development');
  await mkdir(development, {recursive: true});
  const packRoot = join(root, 'pack-environment'); await mkdir(packRoot);
  const environment = publicConsumerEnvironment(process.env, packRoot);
  for (const path of [environment.HOME, environment.TMPDIR]) await mkdir(path);
  await writeFile(environment.npm_config_userconfig, `registry=${registry}\n`); await writeFile(environment.npm_config_globalconfig, '');
  const version = '0.0.7-rc.1', source = 'a'.repeat(40), tag = 'candidate-synthetic';
  const cohort = admitCohort({version: 'actql-package-release-cohort/0.1', packageVersion: version,
    registry, access: 'public', tag, packages: ['client-wire', 'sdk', 'local-node', 'node']});
  const license = join(root, 'LICENSE'); await writeFile(license, 'Inert staging fixture license\n');
  const packages = [], tarballs = {};
  for (const [index, name] of cohort.packages.entries()) {
    const directory = join(root, `original-${name}`); await mkdir(directory);
    await writeFile(join(directory, 'package.json'), JSON.stringify({name: `@actql/${name}`, version: '0.0.0-development',
      private: true, type: 'module', files: ['index.mjs'], exports: './index.mjs',
      dependencies: index ? {[`@actql/${cohort.packages[index - 1]}`]: '0.0.0-development'} : {}}));
    await writeFile(join(directory, 'index.mjs'), 'export const inert = 79;\n');
    execFileSync('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination', development, '--cache', join(packRoot, 'cache')],
      {cwd: directory, env: environment, encoding: 'utf8', stdio: 'pipe'});
    const item = await stagePackage({archive: join(development, `actql-${name}-0.0.0-development.tgz`), destination: cohortDirectory, name, cohort, license});
    packages.push(item); tarballs[name] = item.originalSha256;
  }
  await writeFile(join(development, 'packed-client-packages.json'), JSON.stringify({revision: source, tarballs}));
  await writeFile(join(cohortDirectory, 'release.json'), JSON.stringify({version: 'actql-package-release/0.1', sourceSha: source,
    preparedAt: '2000-01-01T00:00:00Z', cohort, recipeSha256: 'b'.repeat(64), cohortSha256: 'c'.repeat(64),
    toolchain: {fixture: true}, generation: 'normal-prepack-then-metadata-and-license-only', packages}));
  preparation = join(root, 'preparation');
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'synthetic-stage-protocol-only', version,
    source: {repository: 'https://github.com/actql/actql', commit: source, branch: 'main'},
    targets: [{id: 'node', ecosystem: 'npm', packages: packages.map(item => item.name), platforms: ['darwin-arm64'],
      profiles: ['local'], destination: registry, channels: [tag]}],
    notes: {summary: 'Inert stage protocol, not a selected product', breakingChanges: [], migration: [], knownLimitations: ['No real stage, runtime or owner approval']}};
  const fixed = await freezeReleaseSet({request, policy: {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'],
    publicationAuthority: 'external-owner-approval-required'}, cohorts: [{targetId: 'node', kind: 'node-npm', directory: cohortDirectory}], destination: preparation});
  const inputs = join(root, 'inputs'); await mkdir(inputs); const evidence = [];
  for (const kind of ['recipe', 'toolchain', 'build']) {
    const bytes = Buffer.from(`Inert original ${kind} evidence\n`), file = `${kind}.txt`; await writeFile(join(inputs, file), bytes);
    evidence.push({id: kind, kind, file, bytes: bytes.length, sha256: hash(bytes)});
  }
  reviewRequest = {schemaVersion: 'actql-release-review-request/0.1', manifestSha256: fixed.sha256, evidence,
    provenance: [{targetId: 'node', recipeEvidence: 'recipe', toolchainEvidence: 'toolchain', build: {kind: 'local', run: 'inert', artifactId: null, evidence: 'build'}}],
    environments: [{targetId: 'node', platforms: ['darwin-arm64'], profiles: ['local'], node: 'synthetic only', python: null, abi: 'inert', limitations: ['No executable']}],
    acceptance: ['prepublication-install', 'public-install'].map(phase => ({targetId: 'node', phase, status: 'not-run', evidence: [], limitations: ['No product']})),
    changes: {previousSource: null, diffEvidence: null}, executionScope: {publish: ['node'], promote: [], resumeIdenticalMissing: ['node']}};
  reviewFile = join(inputs, 'review.json'); await writeFile(reviewFile, JSON.stringify(reviewRequest));
  reviewed = await prepareReleaseReview({directory: preparation, expectedSha256: fixed.sha256, reviewFile, destination: join(root, 'reviewed')});
});
after(async () => {if (root) await rm(root, {recursive: true, force: true});});

const uuid = index => `10000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`;

async function fixture(t, selected = reviewed, originalDirectory = join(root, 'reviewed')) {
  const own = await mkdtemp(join(root, 'case-')); t.after(() => rm(own, {recursive: true, force: true}));
  const directory = join(own, 'fixed'); await cp(originalDirectory, directory, {recursive: true});
  const artifacts = selected.manifest.artifacts, originals = new Map();
  for (const item of artifacts) originals.set(item.name, await readFile(join(directory, item.path)));
  const pending = new Map(), published = new Map(), calls = [], commands = [], namesAbsent = new Set();
  const control = {ownerUnavailable: false, ownerAfterSendUnavailable: false, throwAfterSend: false, malformedReply: false, wrongTool: false,
    stageIdSuffix: '', occupiedTag: false};
  const fetchResponse = async (url, options) => {
    calls.push({role: 'public', url}); assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit');
    const item = artifacts.find(value => url === `${registry}${encodeURIComponent(value.name)}/${value.version}`);
    if (item) return published.has(item.name) ? Response.json({name: item.name, version: item.version,
      dist: {integrity: item.integrity, tarball: `${registry}${item.name}/-/${item.file}`}}) : new Response('', {status: 404});
    const binary = artifacts.find(value => url === `${registry}${value.name}/-/${value.file}`);
    if (binary) return new Response(published.get(binary.name));
    const namespace = artifacts.find(value => url === `${registry}${encodeURIComponent(value.name)}`); assert(namespace, `Foreign public request ${url}`);
    return namesAbsent.has(namespace.name) ? new Response('', {status: 404})
      : Response.json({name: namespace.name, versions: {'0.0.0-stage': {}}, 'dist-tags': control.occupiedTag ? {'candidate-synthetic': '0.0.1'} : {}});
  };
  const fetchStage = async (url, options) => {
    calls.push({role: 'owner-read', url}); assert.equal(options.method, 'GET');
    const parsed = new URL(url);
    if (control.ownerUnavailable || (control.ownerAfterSendUnavailable && commands.length)) return new Response('', {status: 403});
    if (parsed.pathname === '/-/stage') {
      assert.equal(parsed.searchParams.get('page'), '0'); assert.equal(parsed.searchParams.get('perPage'), '100');
      const item = pending.get(parsed.searchParams.get('package'));
      return Response.json({total: item ? 1 : 0, items: item ? [item.body] : []});
    }
    const stage = [...pending.values()].find(value => parsed.pathname === `/-/stage/${value.body.id}` || parsed.pathname === `/-/stage/${value.body.id}/tarball`);
    assert(stage, `Missing exact stage request ${url}`);
    return parsed.pathname.endsWith('/tarball') ? new Response(stage.bytes) : Response.json(stage.body);
  };
  const run = role => async (args, context) => {
    if (args.length === 1 && args[0] === '--version') return {code: 0, signal: null, stdout: control.wrongTool ? '10.9.4\n' : '11.15.0\n'};
    const item = artifacts.find(value => value.name === context.artifact.name); assert(item);
    assert.deepEqual(args.slice(0, 2), ['stage', 'publish']);
    assert.deepEqual(args.slice(3), ['--ignore-scripts', '--json', '--registry', registry, '--access', 'public', '--tag', 'candidate-synthetic', '--provenance']);
    assert(Object.isFrozen(args)); assert.equal(context.manifestSha256, options.expectedSha256);
    const index = artifacts.indexOf(item), intent = JSON.parse(await readFile(join(dirname(dirname(args[2])), `${index}-intent.json`)));
    assert.equal(intent.manifestSha256, options.expectedSha256); assert.deepEqual(intent.artifact, item);
    const bytes = await readFile(args[2]); assert.deepEqual(bytes, originals.get(item.name));
    assert.equal((await lstat(args[2])).mode & 0o777, 0o400);
    commands.push({role, name: item.name, args: [...args]});
    const id = uuid(index); pending.set(item.name, {body: {id, packageName: item.name, version: item.version,
      tag: 'candidate-synthetic', status: 'awaiting_approval', shasum: 'not-a-reuse-proof'}, bytes}); namesAbsent.delete(item.name);
    if (control.throwAfterSend) {control.throwAfterSend = false; throw Error('Independent lost stage response');}
    return {code: 0, signal: null, stdout: control.malformedReply ? '{' : JSON.stringify({[item.name]: {id: `${item.name}@${item.version}`,
      name: item.name, version: item.version, size: item.bytes, integrity: item.integrity, stageId: id + control.stageIdSuffix}})};
  };
  const receiptsDirectory = join(own, 'receipts');
  const options = {directory, expectedSha256: selected.sha256, targetId: selected.manifest.request.targets[0].id, receiptsDirectory,
    npmVersion: '11.15.0', runNpm: run('stage-only'), fetchStage, fetchResponse};
  return {own, directory, artifacts, originals, pending, published, calls, commands, namesAbsent, control, options,
    executeInitialStage: run('initial-owner'), stage: extra => stagePackageRelease({...options, ...extra})};
}

test('npm stage: read-only CLI plan is explicit and legacy mutation commands remain unavailable', async t => {
  const f = await fixture(t), plan = await runRelease(['npm-stage-plan', f.directory, reviewed.sha256, 'node']);
  assert.equal(plan.manifestSha256, reviewed.sha256); assert.equal(plan.execution, 'unavailable'); assert.equal(plan.packages.length, 4);
  assert(plan.packages.every(item => item.proposedArguments[0] === 'stage' && item.proposedArguments[1] === 'publish'));
  assert.equal(plan.tools.minimumNpm, '11.15.0');
  for (const command of ['stage', 'publish', 'promote', 'resume']) await assert.rejects(runRelease([command, 'absent']), /External release operation is unavailable/u);
  assert.deepEqual(f.commands, []); assert.deepEqual(f.calls, []);
});

test('npm stage: pinned tool and separate read port are required before any actual send, not actor/approved JSON', async t => {
  const f = await fixture(t);
  await assert.rejects(f.stage({fetchStage: undefined}), /separate owner stage read port/u);
  await assert.rejects(f.stage({approved: true}), /Unexpected stage execution fields/u);
  await assert.rejects(f.stage({npmVersion: '11.14.0'}), /npm11.15/u);
  await assert.rejects(f.stage({npmVersion: '11.15.0\n'}));
  f.control.wrongTool = true; await assert.rejects(f.stage(), /explicit protected pin/u);
  assert.deepEqual(f.commands, []); assert.deepEqual(f.calls, []);
});

test('npm stage: complete preflight, private exact copies, immutable intents and original stage IDs preserve dependency order', async t => {
  const f = await fixture(t), original = await readFile(join(f.directory, 'release-set.json'));
  const result = await f.stage();
  assert.deepEqual(f.commands.map(value => value.name), f.artifacts.map(value => value.name));
  assert(result.results.every(item => item.state === 'pending')); assert.equal(result.results[0].stageId, uuid(0));
  assert.deepEqual(await readFile(join(f.directory, 'release-set.json')), original);
  assert.equal((await verifyReleaseSet(f.directory, {expectedSha256: reviewed.sha256})).sha256, reviewed.sha256);
  assert.equal(JSON.parse(await readFile(join(result.receiptDirectory, '0-command.json'))).confirmation, 'unobserved');
  assert.equal(JSON.parse(await readFile(join(result.receiptDirectory, '0-after.json'))).observations[0].state, 'pending');
  const before = [...f.commands]; await f.stage(); assert.deepEqual(f.commands, before);
});

test('npm stage: partial lost response preserves Unknown intent and resumes original pending bytes without sending them again', async t => {
  const f = await fixture(t); f.control.throwAfterSend = true;
  await assert.rejects(f.stage(), /Original stage outcome unknown/u);
  assert.equal(f.pending.size, 1); assert.equal(f.commands.length, 1);
  const target = join(f.options.receiptsDirectory, reviewed.sha256, 'node'), first = (await readdir(target))[0];
  const intent = join(target, first, '0-intent.json'), before = await readFile(intent), inode = (await lstat(intent)).ino;
  assert.equal(JSON.parse(await readFile(join(target, first, '0-unknown.json'))).reason, 'runner-threw');
  const result = await f.stage(); assert(result.results.every(item => item.state === 'pending'));
  assert.deepEqual(f.commands.map(value => value.name), f.artifacts.map(value => value.name));
  assert.deepEqual(await readFile(intent), before); assert.equal((await lstat(intent)).ino, inode);
});

test('npm stage: successful command without owner confirmation is retained separately and never assumed absent', async t => {
  const f = await fixture(t); f.control.ownerAfterSendUnavailable = true;
  await assert.rejects(f.stage(), /owner confirmation is unavailable/u);
  const target = join(f.options.receiptsDirectory, reviewed.sha256, 'node'), first = (await readdir(target))[0];
  const receipt = JSON.parse(await readFile(join(target, first, '0-command.json')));
  assert.equal(receipt.commandSucceeded, true); assert.equal(receipt.stageId, uuid(0)); assert.equal(receipt.confirmation, 'unobserved');
  assert.equal(f.commands.length, 1); f.control.ownerAfterSendUnavailable = false;
  await f.stage(); assert.equal(f.commands.length, 4);
});

test('npm stage: malformed original stdout keeps its raw receipt and requires fresh owner readback rather than resend', async t => {
  const f = await fixture(t); f.control.malformedReply = true; await assert.rejects(f.stage(), /outcome unknown/u);
  const target = join(f.options.receiptsDirectory, reviewed.sha256, 'node'), first = (await readdir(target))[0];
  assert.equal((await readFile(join(target, first, '0-stdout.json'))).toString(), '{');
  f.control.malformedReply = false; await f.stage(); assert.equal(f.commands.length, 4);
});

test('npm stage: initial public placeholder needs the separate supplied owner operation, never a local boolean', async t => {
  const f = await fixture(t); f.artifacts.forEach(item => f.namesAbsent.add(item.name));
  await assert.rejects(f.stage(), /separate owner operation required/u); assert.equal(f.commands.length, 0);
  await assert.rejects(f.stage({executeInitialStage: true})); assert.equal(f.commands.length, 0);
  const result = await f.stage({executeInitialStage: f.executeInitialStage});
  assert(result.results.every(item => item.state === 'pending')); assert(f.commands.every(item => item.role === 'initial-owner'));
});

test('npm stage: reader denial, wrong immutable tag, or different pending bytes stop the whole cohort before a send', async t => {
  const f = await fixture(t), first = f.artifacts[0]; f.control.ownerUnavailable = true;
  await assert.rejects(f.stage(), /preflight is unknown or conflicting/u); assert.equal(f.commands.length, 0);
  f.control.ownerUnavailable = false;
  const body = {id: uuid(0), packageName: first.name, version: first.version, tag: 'wrong', status: 'awaiting_approval', actor: 'fixture-owner', approved: true};
  f.pending.set(first.name, {body, bytes: f.originals.get(first.name)});
  await assert.rejects(f.stage(), /preflight is unknown or conflicting/u); assert.equal(f.commands.length, 0);
  body.tag = 'candidate-synthetic'; f.pending.get(first.name).bytes = Buffer.alloc(first.bytes, 65);
  await assert.rejects(f.stage(), /preflight is unknown or conflicting/u); assert.equal(f.commands.length, 0);
});

test('npm stage: a newly absent namespace still checks the separate initial owner tool at the actual boundary', async t => {
  const f = await fixture(t), first = f.artifacts[0]; let namespaces = 0, initialProbes = 0;
  const fetchResponse = async (url, options) => {
    if (url === `${registry}${encodeURIComponent(first.name)}` && ++namespaces === 2) f.namesAbsent.add(first.name);
    return f.options.fetchResponse(url, options);
  };
  const executeInitialStage = async args => {
    assert.deepEqual(args, ['--version']); initialProbes++; return {code: 0, signal: null, stdout: '11.16.0\n'};
  };
  await assert.rejects(f.stage({fetchResponse, executeInitialStage}), /Initial-name owner tool differs/u);
  assert.equal(initialProbes, 1); assert.deepEqual(f.commands, []);
});

test('npm stage: already published exact original versions need no staging or owner-stage lookup', async t => {
  const f = await fixture(t); for (const item of f.artifacts) f.published.set(item.name, f.originals.get(item.name));
  const result = await f.stage(); assert(result.results.every(item => item.state === 'published'));
  assert.equal(f.commands.length, 0); assert.equal(f.calls.filter(item => item.role === 'owner-read').length, 0);
});

test('npm stage: an occupied staging channel is not an implicit promotion permission', async t => {
  const f = await fixture(t); f.control.occupiedTag = true;
  await assert.rejects(f.stage(), /preflight is unknown or conflicting/u); assert.deepEqual(f.commands, []);
});

test('npm stage: opaque stage ids with a trailing newline remain unknown, never normalized into another original', async t => {
  const f = await fixture(t); f.control.stageIdSuffix = '\n';
  await assert.rejects(f.stage(), /outcome unknown/u); assert.equal(f.commands.length, 1);
  f.control.stageIdSuffix = ''; await f.stage(); assert.equal(f.commands.length, 4);
  f.pending.get(f.artifacts[0].name).body.id += '\n';
  const result = await observeNpmStageTarget(f.directory, reviewed.sha256, 'node', {...f.options, file: f.artifacts[0].file});
  assert.equal(result.observations[0].state, 'unknown');
});

test('npm stage: complete owner pagination and exact before/after stage tuple are required for pending reuse', async t => {
  const f = await fixture(t), item = f.artifacts[0];
  const selected = {id: uuid(0), packageName: item.name, version: item.version, tag: 'candidate-synthetic', status: 'awaiting_approval'};
  f.pending.set(item.name, {body: selected, bytes: f.originals.get(item.name)});
  const history = Array.from({length: 100}, (_, index) => ({id: uuid(index + 20), packageName: item.name, version: `0.0.1-legacy.${index}`}));
  const pages = []; let changedTotal = false, changedAfter = false, views = 0;
  const fetchStage = async (url, options) => {
    const value = new URL(url);
    if (value.pathname === '/-/stage') {
      const page = Number(value.searchParams.get('page')); pages.push(page);
      return Response.json({total: changedTotal && page === 1 ? 102 : 101, items: page === 0 ? history : [selected]});
    }
    if (value.pathname === `/-/stage/${selected.id}`) {
      views++; return Response.json(changedAfter && views % 2 === 0 ? {...selected, status: 'rejected'} : selected);
    }
    return f.options.fetchStage(url, options);
  };
  const observe = () => observeNpmStageTarget(f.directory, reviewed.sha256, 'node', {fetchStage, fetchResponse: f.options.fetchResponse, file: item.file});
  assert.equal((await observe()).observations[0].state, 'pending'); assert.deepEqual(pages, [0, 1]);
  changedTotal = true; assert.equal((await observe()).observations[0].state, 'unknown');
  changedTotal = false; changedAfter = true; assert.equal((await observe()).observations[0].state, 'conflict');
  assert.deepEqual(f.commands, []);
});

test('npm stage: a new candidate lacking same-bytes recovery scope cannot reuse an earlier attempt as approval', async t => {
  const f = await fixture(t), request = structuredClone(reviewRequest); request.executionScope.resumeIdenticalMissing = [];
  const file = join(dirname(reviewFile), 'without-resume.json'); await writeFile(file, JSON.stringify(request));
  const fixed = await prepareReleaseReview({directory: preparation, expectedSha256: reviewRequest.manifestSha256,
    reviewFile: file, destination: join(f.own, 'without-resume')});
  f.options.directory = join(f.own, 'without-resume'); f.options.expectedSha256 = fixed.sha256;
  f.control.throwAfterSend = true; await assert.rejects(f.stage(), /outcome unknown/u);
  await assert.rejects(f.stage(), /did not include same-bytes recovery/u); assert.equal(f.commands.length, 1);
});

test('npm stage: original receipt write refusal stops before any remote stage send', async t => {
  const f = await fixture(t); await mkdir(f.options.receiptsDirectory, {mode: 0o500});
  try {await assert.rejects(f.stage(), {code: 'EACCES'}); assert.equal(f.commands.length, 0);}
  finally {await chmod(f.options.receiptsDirectory, 0o700);}
});

test('npm stage: final stable channels cannot be applied through stage approval instead of the promotion boundary', async t => {
  const f = await fixture(t), base = join(f.own, 'latest-preparation'); await cp(preparation, base, {recursive: true});
  const childPath = join(base, 'node/release.json'), child = JSON.parse(await readFile(childPath)); child.cohort.tag = 'latest';
  const childBytes = Buffer.from(JSON.stringify(child)); await writeFile(childPath, childBytes);
  const manifest = JSON.parse(await readFile(join(base, 'release-set.json'))); manifest.request.targets[0].channels = ['latest'];
  Object.assign(manifest.cohorts[0], {bytes: childBytes.length, sha256: hash(childBytes)});
  const bytes = Buffer.from(JSON.stringify(manifest)), sha256 = hash(bytes);
  await writeFile(join(base, 'release-set.json'), bytes); await writeFile(join(base, 'release-set.sha256'), `${sha256}  release-set.json\n`);
  const request = structuredClone(reviewRequest); request.manifestSha256 = sha256;
  const file = join(dirname(reviewFile), 'latest-review.json'); await writeFile(file, JSON.stringify(request));
  const destination = join(f.own, 'latest-review'), fixed = await prepareReleaseReview({directory: base, expectedSha256: sha256, reviewFile: file, destination});
  await assert.rejects(npmStagePlan(destination, fixed.sha256, 'node'), /separate staging tag/u);
  assert.deepEqual(f.commands, []);
});

test('npm stage: original Native omitted-private metadata and version-bound artifacts use the same staging protocol', async t => {
  const own = await mkdtemp(join(root, 'native-shape-')), base = join(own, 'base'), target = 'native';
  await mkdir(join(base, target), {recursive: true});
  const version = reviewed.manifest.release.version, source = reviewed.manifest.request.source.commit;
  const names = ['@actql/cli-darwin-arm64', '@actql/cli-linux-x64-gnu', 'actql'], packages = [], records = [];
  for (const [index, name] of names.entries()) {
    const input = join(own, `package-${index}`), payload = join(input, 'package'); await mkdir(payload, {recursive: true});
    const metadata = {name, version, license: 'Apache-2.0', publishConfig: {registry, access: 'public'},
      ...(name === 'actql' ? {optionalDependencies: Object.fromEntries(names.slice(0, 2).map(value => [value, version]))} : {})};
    await writeFile(join(payload, 'package.json'), JSON.stringify(metadata));
    await writeFile(join(payload, 'LICENSE'), 'inert Native staging fixture');
    if (name !== 'actql') {
      const binary = Buffer.alloc(64), platform = index === 0 ? 'darwin-arm64' : 'linux-x64-gnu';
      if (index === 0) {binary.writeUInt32LE(0xfeedfacf); binary.writeUInt32LE(0x0100000c, 4);}
      else {binary.writeUInt32BE(0x7f454c46); binary[4] = 2; binary[5] = 1; binary.writeUInt16LE(62, 18);}
      const record = {version: 'actql-native-cli-artifact/0.1', sourceSha: source, platform, binarySha256: hash(binary),
        binaryBytes: binary.length, generatedCSha256: 'b'.repeat(64), toolchainPinSha256: 'c'.repeat(64), notices: {},
        toolchain: {fixture: true}, abi: index === 0 ? {format: 'Mach-O', minimumMacOS: '11.0'} : {format: 'ELF', minimumGlibc: '2.17'},
        testedHost: {}, generation: ['inert metadata; never executed'], packageVersion: version,
        packageVersionObservation: {argv: ['--version'], stdout: `${version}\n`, code: 0, signal: null,
          binarySha256: hash(binary), binaryBytes: binary.length, buildInputSha256: 'd'.repeat(64)}};
      await mkdir(join(payload, 'bin')); await writeFile(join(payload, 'bin/actql-native-client'), binary);
      await writeFile(join(payload, 'artifact.json'), JSON.stringify(record)); records.push(record);
    }
    const file = `${name.replace('@', '').replace('/', '-')}-${version}.tgz`;
    execFileSync('tar', ['-czf', join(base, target, file), '-C', input, 'package']);
    const bytes = await readFile(join(base, target, file));
    packages.push({name, version, file, bytes: bytes.length, sha256: hash(bytes),
      integrity: `sha512-${createHash('sha512').update(bytes).digest('base64')}`, files: await inventory(payload)});
  }
  const child = {version: 'actql-native-cli-release/0.1', sourceSha: source, preparedAt: '2000-01-01T00:00:00Z',
    recipeSha256: 'e'.repeat(64), cohort: {packageVersion: version, registry, access: 'public', tag: 'candidate-synthetic'},
    platforms: Object.fromEntries(records.map(record => [record.platform, {}])), artifacts: records, packages};
  const childBytes = Buffer.from(JSON.stringify(child)); await writeFile(join(base, target, 'release.json'), childBytes);
  const manifest = structuredClone(reviewed.manifest); delete manifest.review;
  manifest.request.targets = [{id: target, ecosystem: 'npm', packages: names, platforms: records.map(record => record.platform),
    profiles: ['remote'], destination: registry, channels: ['candidate-synthetic']}];
  manifest.cohorts = [{targetId: target, kind: 'native-npm', path: `${target}/release.json`, bytes: childBytes.length,
    sha256: hash(childBytes), verification: 'Independent Native-shaped staging fixture; no actual Native artifact or install acceptance'}];
  manifest.artifacts = packages.map(({files, ...item}) => ({targetId: target, ecosystem: 'npm', ...item, path: `${target}/${item.file}`}));
  const bytes = Buffer.from(JSON.stringify(manifest)), digest = hash(bytes);
  await writeFile(join(base, 'release-set.json'), bytes); await writeFile(join(base, 'release-set.sha256'), `${digest}  release-set.json\n`);
  const review = structuredClone(reviewRequest); review.manifestSha256 = digest;
  review.provenance[0].targetId = target;
  Object.assign(review.environments[0], {targetId: target, platforms: manifest.request.targets[0].platforms, profiles: ['remote']});
  for (const row of review.acceptance) row.targetId = target;
  review.executionScope = {publish: [target], promote: [], resumeIdenticalMissing: [target]};
  const reviewPath = join(dirname(reviewFile), 'native-review.json'); await writeFile(reviewPath, JSON.stringify(review));
  const directory = join(own, 'reviewed');
  const fixed = await prepareReleaseReview({directory: base, expectedSha256: digest, reviewFile: reviewPath, destination: directory});
  const f = await fixture(t, fixed, directory), result = await f.stage();
  assert.equal(result.results.length, 3); assert(result.results.every(value => value.state === 'pending'));
  assert.deepEqual(f.commands.map(value => value.name), names);
});

test('npm stage terminal: signalled or unreported main tool probe refuses before any registry read',async t=>{
  for(const signal of ['SIGTERM',undefined]){
    const f=await fixture(t);
    const runNpm=async(args,context)=>{
      const reply=await f.options.runNpm(args,context);
      if(args[0]==='--version'){if(signal===undefined)delete reply.signal;else reply.signal=signal;}
      return reply;
    };
    await assert.rejects(f.stage({runNpm}),/Actual npm differs from the explicit protected pin/u);
    assert.deepEqual(f.calls,[]);assert.deepEqual(f.commands,[]);
  }
});

test('npm stage terminal: initial owner probe cannot bypass explicit terminal status',async t=>{
  for(const signal of ['SIGTERM',undefined]){
    const f=await fixture(t);f.artifacts.forEach(item=>f.namesAbsent.add(item.name));let probes=0;
    const executeInitialStage=async(args,context)=>{
      const reply=await f.executeInitialStage(args,context);
      if(args[0]==='--version'){probes++;if(signal===undefined)delete reply.signal;else reply.signal=signal;}
      return reply;
    };
    await assert.rejects(f.stage({executeInitialStage}),/Initial-name owner tool differs/u);
    assert.equal(probes,1);assert.deepEqual(f.commands,[]);assert.equal(f.pending.size,0);
  }
});

test('npm stage terminal: signalled original send stops once with raw status and explicit no-resend recovery',async t=>{
  const f=await fixture(t);let afterSendReads=0;
  const fetchStage=async(url,options)=>{if(f.commands.length)afterSendReads++;return f.options.fetchStage(url,options);};
  const runNpm=async(args,context)=>{
    const reply=await f.options.runNpm(args,context);if(args[0]!=='--version')reply.signal='SIGTERM';return reply;
  };
  await assert.rejects(f.stage({runNpm,fetchStage}),/Original stage outcome unknown/u);
  assert.equal(f.commands.length,1);assert.equal(f.pending.size,1);assert.equal(afterSendReads,0);
  const target=join(f.options.receiptsDirectory,reviewed.sha256,'node'),[attempt]=await readdir(target);
  const original=join(target,attempt),intent=join(original,'0-intent.json');
  const bytes=await readFile(intent),inode=(await lstat(intent)).ino;
  assert.deepEqual(JSON.parse(await readFile(join(original,'0-terminal.json'))),{code:0,signal:'SIGTERM'});
  assert.equal(JSON.parse(await readFile(join(original,'0-unknown.json'))).reason,'command-or-original-response-unconfirmed');
  await assert.rejects(readFile(join(original,'0-command.json')),{code:'ENOENT'});
  assert.equal(JSON.parse(await readFile(join(original,'0-stdout.json')))[f.artifacts[0].name].stageId,uuid(0));
  const result=await f.stage();assert(result.results.every(item=>item.state==='pending'));
  assert.deepEqual(f.commands.map(item=>item.name),f.artifacts.map(item=>item.name));
  assert.deepEqual(await readFile(intent),bytes);assert.equal((await lstat(intent)).ino,inode);
});

test('npm stage terminal: missing send status stays Unknown without a successful command receipt',async t=>{
  for(const field of ['signal','code']){
    const f=await fixture(t);
    const runNpm=async(args,context)=>{
      const reply=await f.options.runNpm(args,context);if(args[0]!=='--version')delete reply[field];return reply;
    };
    await assert.rejects(f.stage({runNpm}),/Original stage outcome unknown/u);
    assert.equal(f.commands.length,1);assert.equal(f.pending.size,1);
    const target=join(f.options.receiptsDirectory,reviewed.sha256,'node'),[attempt]=await readdir(target);
    assert.equal(JSON.parse(await readFile(join(target,attempt,'0-unknown.json'))).reason,'command-or-original-response-unconfirmed');
    await assert.rejects(readFile(join(target,attempt,'0-command.json')),{code:'ENOENT'});
    assert.equal(JSON.parse(await readFile(join(target,attempt,'0-stdout.json')))[f.artifacts[0].name].stageId,uuid(0));
  }
});

test('npm stage failure custody: SAME private runner failure reaches caller without receipt or normal error-output leakage',async t=>{
  const f=await fixture(t),original=f.options.runNpm;
  const failure=Object.assign(Error('PRIVATE-INERT-STAGE-RUNNER-MARKER'),{originalCleanup:{inertIdentityOnly:true}});
  let caught;
  try{await f.stage({runNpm:async(args,context)=>{
    const reply=await original(args,context);if(args[0]!=='--version')throw failure;return reply;
  }});}catch(error){caught=error;}
  assert(caught);assert.equal(caught.originalPublisherFailure,failure);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalPublisherFailure').enumerable,false);
  assert(!String(caught).includes('PRIVATE-INERT'));assert(!inspect(caught).includes('PRIVATE-INERT'));
  assert.equal(f.commands.length,1);assert.equal(f.pending.size,1);
  const target=join(f.options.receiptsDirectory,reviewed.sha256,'node'),[attempt]=await readdir(target);
  const path=join(target,attempt);
  assert.equal(JSON.parse(await readFile(join(path,'0-unknown.json'))).reason,'runner-threw');
  for(const file of await readdir(path))if((await lstat(join(path,file))).isFile())
    assert(!(await readFile(join(path,file),'utf8')).includes('PRIVATE-INERT'));
});

test('npm stage failure custody: Unknown receipt write refusal retains BOTH original failure and physical write error',async t=>{
  const f=await fixture(t),original=f.options.runNpm;
  const failure=Object.assign(Error('PRIVATE-INERT-STAGE-WRITE-MARKER'),{originalCleanup:{inertIdentityOnly:true}});
  let attempt,caught;
  try{await f.stage({runNpm:async(args,context)=>{
    const reply=await original(args,context);
    if(args[0]!=='--version'){attempt=dirname(dirname(args[2]));await chmod(attempt,0o500);throw failure;}
    return reply;
  }});}catch(error){caught=error;}
  finally{if(attempt)await chmod(attempt,0o700);}
  assert(caught);assert.equal(caught.code,'EACCES');assert.notEqual(caught,failure);
  assert.equal(caught.originalPublisherFailure,failure);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalPublisherFailure').enumerable,false);
  assert(!inspect(caught).includes('PRIVATE-INERT'));assert.equal(f.commands.length,1);
  assert.equal(JSON.parse(await readFile(join(attempt,'0-intent.json'))).outcome,'unknown-until-original-response-and-owner-readback');
  await assert.rejects(readFile(join(attempt,'0-unknown.json')),{code:'ENOENT'});
});

// Inert existing stage setup, complete real reader, injected owner terminal.
// No npm approval, session, OTP, real publication or product runtime occurs.
async function ownerFixture(t) {
  const f=await fixture(t);await f.stage();
  const tags=new Map(f.artifacts.map(item=>[item.name,{}]));
  const commands=[],control={wrongTool:false,throwAfterSend:false,noPublish:false,cancel:false,authOutput:false,wrongTag:false,
    denyAfterSend:false,ownerUnavailable:false,replaceLater:false,badBytes:false,beforeList:null,listRound:0};
  const stages=f.artifacts.map((item,index)=>({file:item.file,stageId:uuid(index)}));
  const fetchStage=async(url,options)=>{
    const parsed=new URL(url);
    if(parsed.pathname==='/-/stage'&&parsed.searchParams.get('package')===f.artifacts[0].name){
      control.listRound++;await control.beforeList?.(control.listRound);
    }
    if(control.ownerUnavailable||(control.denyAfterSend&&commands.length))return new Response('',{status:403});
    return f.options.fetchStage(url,options);
  };
  const receiptsDirectory=join(f.own,'owner-receipts');
  const fetchResponse=async(url,options)=>{
    const item=f.artifacts.find(value=>url===`${registry}-/package/${encodeURIComponent(value.name)}/dist-tags`);
    if(item)return Response.json(tags.get(item.name));
    return f.options.fetchResponse(url,options);
  };
  const runNpmOwner=async(args,context)=>{
    assert(Object.isFrozen(args));assert(Object.isFrozen(context));assert.equal(context.manifestSha256,reviewed.sha256);
    if(args[0]==='--version')return {code:0,signal:null,stdout:control.wrongTool?'10.9.4\n':'11.15.0\n',stderr:''};
    assert.equal(context.phase,'owner-approval');assert(Object.isFrozen(context.package));assert(Object.isFrozen(context.review));
    const presentation=JSON.parse(context.review.json);assert.equal(presentation.packages.length,4);assert.equal(presentation.acceptance,'unaccepted');
    assert(context.review.markdown.includes('Original staged cohort for owner review'));
    const item=f.artifacts.find(value=>value.name===context.package.name),index=f.artifacts.indexOf(item);
    assert.deepEqual(args,['stage','approve',uuid(index),'--registry',registry]);assert.equal(args.includes('--otp'),false);
    assert.equal(context.package.sha256,item.sha256);assert.equal(context.package.integrity,item.integrity);
    const targetRoot=join(receiptsDirectory,reviewed.sha256,'owner-approval','node');let intent;
    for(const attempt of await readdir(targetRoot)){
      try{const path=join(targetRoot,attempt,`${index}-intent.json`),body=JSON.parse(await readFile(path));
        try{await lstat(join(targetRoot,attempt,`${index}-unknown.json`));continue;}catch(failure){if(failure.code!=='ENOENT')throw failure;}
        assert.equal((await lstat(path)).mode&0o777,0o600);intent=body;
      }catch(failure){if(failure.code!=='ENOENT')throw failure;}
    }
    assert(intent);assert.equal(intent.stageId,args[2]);assert.deepEqual(intent.args,args);assert.equal(intent.state,'outcome-unknown');
    commands.push(item.name);
    if(!control.noPublish&&!control.cancel){const pending=f.pending.get(item.name);assert(pending);
      f.published.set(item.name,control.badBytes?Buffer.alloc(pending.bytes.length,88):pending.bytes);f.pending.delete(item.name);
      tags.get(item.name)['candidate-synthetic']=control.wrongTag?'0.0.1':item.version;}
    if(control.replaceLater)f.pending.get(f.artifacts[3].name).body.id=uuid(90);
    if(control.throwAfterSend){control.throwAfterSend=false;throw Error('PRIVATE-AUTH-PROMPT-MUST-NOT-BE-RECORDED');}
    if(control.authOutput)return {code:0,signal:null,stdout:'PRIVATE-AUTH-PROMPT-MUST-NOT-BE-RECORDED'};
    return {code:control.cancel?1:0,signal:null};
  };
  const selection={directory:f.directory,expectedSha256:reviewed.sha256,targetId:'node',stages,fetchStage,fetchResponse};
  const options={...selection,receiptsDirectory,npmVersion:'11.15.0',runNpmOwner};
  return {...f,commands,control,tags,stages,selection,options,review:extra=>npmStageApprovalPlan({...selection,...extra}),
    approve:extra=>approveStagedPackageRelease({...options,...extra})};
}

test('npm owner helper: complete current original stage list and human review do not execute approval',async t=>{
  const f=await ownerFixture(t),plan=await f.review();
  assert.equal(plan.manifestSha256,reviewed.sha256);assert.equal(plan.packages.length,4);assert.equal(plan.acceptance,'unaccepted');
  assert.deepEqual(plan.packages.map(item=>item.stageId),f.stages.map(item=>item.stageId));
  for(const item of f.artifacts){assert(plan.markdown.includes(item.name));assert(plan.markdown.includes(item.sha256));}
  assert.equal(plan.candidate.manifestSha256,reviewed.sha256);assert.deepEqual(f.commands,[]);
});

test('npm owner helper: sequential explicit IDs and numeric terminal retain full original public-byte readback',async t=>{
  const f=await ownerFixture(t),result=await f.approve();
  assert.deepEqual(f.commands,f.artifacts.map(item=>item.name));assert.equal(result.operationCount,4);
  assert.equal(result.state,'original-cohort-public-bytes-observed');assert.equal(f.published.size,4);
  assert(result.results.every(item=>item.state==='original-public-bytes-observed'));
  const terminal=JSON.parse(await readFile(join(result.receiptDirectory,'0-terminal.json')));assert.deepEqual(terminal,{code:0,signal:null});
  assert.equal((await lstat(result.receiptDirectory)).mode&0o777,0o700);
  assert.equal((await verifyReleaseSet(f.directory,{expectedSha256:reviewed.sha256})).sha256,reviewed.sha256);
});

test('npm owner helper: missing conflicting denied or replaced original stage refuses the full cohort before owner command',async t=>{
  for(const kind of ['missing','bytes','denied','id','duplicate','incomplete']){
    const f=await ownerFixture(t);
    if(kind==='missing')f.pending.delete(f.artifacts[3].name);
    if(kind==='bytes')f.pending.get(f.artifacts[3].name).bytes=Buffer.from('different actual stage bytes');
    if(kind==='denied')f.control.ownerUnavailable=true;
    if(kind==='id')f.stages[3].stageId=uuid(80);
    if(kind==='duplicate')f.stages[3].stageId=f.stages[0].stageId;
    if(kind==='incomplete')f.stages.pop();
    await assert.rejects(f.approve());assert.deepEqual(f.commands,[]);
    await assert.rejects(lstat(f.options.receiptsDirectory),{code:'ENOENT'});
  }
});

test('npm owner helper: stage replacement after displayed review is caught before owner approval',async t=>{
  const f=await ownerFixture(t);f.control.beforeList=round=>{if(round===2)f.pending.get(f.artifacts[0].name).body.id=uuid(80);};
  await assert.rejects(f.approve(),/stage identity/u);assert.deepEqual(f.commands,[]);
});

test('npm owner helper: lost response stops once without auth capture and explicit recovery skips original public bytes',async t=>{
  const f=await ownerFixture(t);f.control.throwAfterSend=true;
  await assert.rejects(f.approve(),/outcome unknown/u);assert.equal(f.commands.length,1);
  const targetRoot=join(f.options.receiptsDirectory,reviewed.sha256,'owner-approval','node'),[attempt]=await readdir(targetRoot);
  const first=join(targetRoot,attempt),unknown=await readFile(join(first,'0-unknown.json'),'utf8');assert(!unknown.includes('PRIVATE-AUTH'));
  await assert.rejects(lstat(join(first,'summary.json')),{code:'ENOENT'});
  const recovered=await f.approve();assert.equal(recovered.operationCount,3);assert.equal(recovered.results[0].state,'already-original-public');
  assert.deepEqual(f.commands,f.artifacts.map(item=>item.name));
  assert.equal((await f.approve()).operationCount,0);assert.equal(f.commands.length,4);
});

test('npm owner helper: cancellation no publication auth output or unavailable readback never becomes approval or continuation',async t=>{
  for(const flag of ['cancel','noPublish','authOutput','denyAfterSend','badBytes']){
    const f=await ownerFixture(t);f.control[flag]=true;await assert.rejects(f.approve(),/outcome unknown/u);assert.equal(f.commands.length,1);
    const targetRoot=join(f.options.receiptsDirectory,reviewed.sha256,'owner-approval','node'),[attempt]=await readdir(targetRoot);
    const path=join(targetRoot,attempt),files=await readdir(path);
    assert(files.includes('0-unknown.json'));assert(!files.includes('summary.json'));
    for(const name of files)assert(!(await readFile(join(path,name),'utf8')).includes('PRIVATE-AUTH-PROMPT'));
  }
});

test('npm owner helper: full next-stage fence refuses unrelated replacement and original mapping cannot be mutated through owner presentation',async t=>{
  const changed=await ownerFixture(t);changed.control.replaceLater=true;
  await assert.rejects(changed.approve(),/outcome unknown/u);assert.equal(changed.commands.length,1);
  const f=await ownerFixture(t),original=f.options.runNpmOwner;
  const result=await f.approve({runNpmOwner:async(args,context)=>{
    if(context.phase==='tool-version')f.stages[0].stageId=uuid(80);
    if(context.phase==='owner-approval')assert.throws(()=>{context.review.markdown='changed';});
    return original(args,context);
  }});
  assert.equal(result.operationCount,4);
});

test('npm owner helper: no terminal or forged authority, wrong tool and frozen-input receipt destination refuse',async t=>{
  const f=await ownerFixture(t);
  await assert.rejects(f.approve({runNpmOwner:undefined}),/owner terminal/u);
  await assert.rejects(f.approve({approved:true}),/Unexpected/u);
  await assert.rejects(f.approve({otp:'not-accepted'}),/Unexpected/u);
  f.control.wrongTool=true;await assert.rejects(f.approve(),/protected pin/u);f.control.wrongTool=false;
  await assert.rejects(f.approve({receiptsDirectory:join(f.directory,'owner-output')}),/outside/u);
  await assert.rejects(runRelease(['stage-approve',f.directory]),/unavailable/u);
  assert.deepEqual(f.commands,[]);
});

test('npm owner helper: staged tag occupancy and post-approval tag drift cannot masquerade as publication',async t=>{
  const occupied=await ownerFixture(t);occupied.tags.get(occupied.artifacts[3].name)['candidate-synthetic']='0.0.1';
  await assert.rejects(occupied.approve(),/staging tag/u);assert.deepEqual(occupied.commands,[]);
  const changed=await ownerFixture(t);changed.control.wrongTag=true;
  await assert.rejects(changed.approve(),/outcome unknown/u);assert.equal(changed.commands.length,1);
});

test('npm owner helper: original private owner failure custody survives without receipt or routine error-output leakage',async t=>{
  const f=await ownerFixture(t),original=f.options.runNpmOwner;
  const privateFailure=Object.assign(Error('PRIVATE-AUTH-PROMPT-MUST-NOT-BE-RECORDED'),{originalCleanup: {inertCustodyIdentity:true}});
  let caught;
  try{await f.approve({runNpmOwner:async(args,context)=>{
    const result=await original(args,context);if(context.phase==='owner-approval')throw privateFailure;return result;
  }});}catch(failure){caught=failure;}
  assert(caught);assert.equal(caught.originalOwnerFailure,privateFailure);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalOwnerFailure').enumerable,false);
  assert(!String(caught).includes('PRIVATE-AUTH'));assert(!inspect(caught).includes('PRIVATE-AUTH'));
  assert.equal(f.commands.length,1);
  const targetRoot=join(f.options.receiptsDirectory,reviewed.sha256,'owner-approval','node'),[attempt]=await readdir(targetRoot);
  for(const name of await readdir(join(targetRoot,attempt)))assert(!(await readFile(join(targetRoot,attempt,name),'utf8')).includes('PRIVATE-AUTH'));
});

// Own returned terminal DATA only. Authentication/output getters are spies,
// never a real prompt, OTP or owner session.
function ownerTerminalResponse(initial,later=null,failure=null) {
  const current={...initial},reads={code:0,signal:0},secretReads={stdout:0,otp:0},reply={};let mutated=false;
  for(const field of Object.keys(reads))Object.defineProperty(reply,field,{enumerable:true,get(){
    reads[field]++;
    if(field==='code'&&failure)throw failure;
    if(field==='code'&&reads[field]===1&&later)queueMicrotask(()=>{Object.assign(current,later);mutated=true;});
    return current[field];
  }});
  for(const field of Object.keys(secretReads))Object.defineProperty(reply,field,{get(){secretReads[field]++;throw Error('INERT forbidden owner output read');}});
  return {reply,reads,secretReads,mutated:()=>mutated};
}

for(const [name,code,signal]of [['nonzero',1,null],['signalled',0,'SIGTERM'],['unreported code',null,null]])
test(`npm owner terminal custody: original ${name} cannot become approval during receipt IO`,async t=>{
  const f=await ownerFixture(t),original=f.options.runNpmOwner;
  const initial={code,signal},captured=ownerTerminalResponse(initial,{code:0,signal:null});
  await assert.rejects(f.approve({runNpmOwner:async(args,context)=>{
    const reply=await original(args,context);return context.phase==='owner-approval'&&f.commands.length===1?captured.reply:reply;
  }}),failure=>{assert.match(failure.message,/outcome unknown/u);
    assert.match(failure.originalApprovalError.message,/command did not confirm completion/u);
    assert.equal(Object.getOwnPropertyDescriptor(failure,'originalApprovalError').enumerable,false);return true;});
  assert(captured.mutated());assert.deepEqual(captured.reads,{code:1,signal:1});assert.deepEqual(captured.secretReads,{stdout:0,otp:0});
  const target=join(f.options.receiptsDirectory,reviewed.sha256,'owner-approval','node'),[name]=await readdir(target),attempt=join(target,name);
  assert.deepEqual(JSON.parse(await readFile(join(attempt,'0-terminal.json'))),initial);
  assert.equal(f.commands.length,1);assert.equal(f.published.size,1);
  assert.equal(JSON.parse(await readFile(join(attempt,'0-unknown.json'))).reason,'terminal-or-public-readback-unconfirmed');
  await assert.rejects(lstat(join(attempt,'0-confirmed.json')),{code:'ENOENT'});await assert.rejects(lstat(join(attempt,'summary.json')),{code:'ENOENT'});
});

test('npm owner terminal custody: original success survives later mutation and never reads output or OTP',async t=>{
  const f=await ownerFixture(t),original=f.options.runNpmOwner;
  const initial={code:0,signal:null},captured=ownerTerminalResponse(initial,{code:1,signal:'SIGTERM'});
  const result=await f.approve({runNpmOwner:async(args,context)=>{
    const reply=await original(args,context);return context.phase==='owner-approval'&&f.commands.length===1?captured.reply:reply;
  }});
  assert(captured.mutated());assert.deepEqual(captured.reads,{code:1,signal:1});assert.deepEqual(captured.secretReads,{stdout:0,otp:0});
  assert.equal(result.operationCount,4);assert.equal(result.state,'original-cohort-public-bytes-observed');
  assert.deepEqual(JSON.parse(await readFile(join(result.receiptDirectory,'0-terminal.json'))),initial);
  assert.deepEqual(f.commands,f.artifacts.map(item=>item.name));
});

test('npm owner terminal custody: throwing reply getter stays SAME private failure without cause leakage',async t=>{
  const f=await ownerFixture(t),original=f.options.runNpmOwner;
  const failure=Object.assign(Error('PRIVATE-INERT-OWNER-GETTER'),{originalCleanup:{inertIdentityOnly:true}});
  const captured=ownerTerminalResponse({code:0,signal:null},null,failure);let caught;
  try{await f.approve({runNpmOwner:async(args,context)=>{
    const reply=await original(args,context);return context.phase==='owner-approval'?captured.reply:reply;
  }});}catch(error){caught=error;}
  assert(caught);assert.equal(caught.originalApprovalError,failure);assert.equal(caught.originalOwnerFailure,undefined);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalApprovalError').enumerable,false);assert.equal(caught.cause,undefined);
  assert(!String(caught).includes('PRIVATE-INERT'));assert(!inspect(caught).includes('PRIVATE-INERT'));
  assert.deepEqual(captured.reads,{code:1,signal:0});assert.deepEqual(captured.secretReads,{stdout:0,otp:0});assert.equal(f.commands.length,1);
  const target=join(f.options.receiptsDirectory,reviewed.sha256,'owner-approval','node'),[name]=await readdir(target),attempt=join(target,name);
  assert.equal(JSON.parse(await readFile(join(attempt,'0-unknown.json'))).reason,'terminal-or-public-readback-unconfirmed');
  for(const file of await readdir(attempt))assert(!(await readFile(join(attempt,file),'utf8')).includes('PRIVATE-INERT'));
});

test('npm owner terminal custody: Unknown write refusal retains physical error and SAME private getter failure',async t=>{
  const f=await ownerFixture(t),original=f.options.runNpmOwner;
  const failure=Object.assign(Error('PRIVATE-INERT-OWNER-GETTER-WRITE'),{originalCleanup:{inertIdentityOnly:true}});
  const captured=ownerTerminalResponse({code:0,signal:null},null,failure);let attempt,caught;
  try{await f.approve({runNpmOwner:async(args,context)=>{
    const reply=await original(args,context);if(context.phase!=='owner-approval')return reply;
    const target=join(f.options.receiptsDirectory,reviewed.sha256,'owner-approval','node'),[name]=await readdir(target);attempt=await realpath(join(target,name));
    await chmod(attempt,0o500);return captured.reply;
  }});}catch(error){caught=error;}finally{if(attempt)await chmod(attempt,0o700);}
  assert.equal(caught.code,'EACCES');assert.notEqual(caught,failure);assert.equal(caught.originalApprovalError,failure);
  assert.equal(caught.originalAttempt,attempt);assert.equal(Object.getOwnPropertyDescriptor(caught,'originalApprovalError').enumerable,false);
  assert.equal(caught.cause,undefined);assert(!inspect(caught).includes('PRIVATE-INERT'));assert.equal(f.commands.length,1);
  assert.deepEqual(captured.secretReads,{stdout:0,otp:0});
  assert.equal(JSON.parse(await readFile(join(attempt,'0-intent.json'))).state,'outcome-unknown');
  await assert.rejects(lstat(join(attempt,'0-unknown.json')),{code:'ENOENT'});
});

test('npm owner terminal custody: terminal and Unknown receipt failures retain both original physical errors and attempt',async t=>{
  const f=await ownerFixture(t),original=f.options.runNpmOwner;let attempt,caught;
  try{await f.approve({runNpmOwner:async(args,context)=>{
    const reply=await original(args,context);if(context.phase!=='owner-approval')return reply;
    const target=join(f.options.receiptsDirectory,reviewed.sha256,'owner-approval','node'),[name]=await readdir(target);attempt=await realpath(join(target,name));
    await chmod(attempt,0o500);return reply;
  }});}catch(error){caught=error;}finally{if(attempt)await chmod(attempt,0o700);}
  assert.equal(caught.code,'EACCES');assert.equal(caught.path,join(attempt,'0-unknown.json'));
  assert.equal(caught.originalApprovalError.code,'EACCES');assert.equal(caught.originalApprovalError.path,join(attempt,'0-terminal.json'));
  assert.notEqual(caught,caught.originalApprovalError);assert.equal(caught.originalAttempt,attempt);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalApprovalError').enumerable,false);assert.equal(caught.cause,undefined);
  assert.equal(f.commands.length,1);assert.equal(JSON.parse(await readFile(join(attempt,'0-intent.json'))).state,'outcome-unknown');
  await assert.rejects(lstat(join(attempt,'0-terminal.json')),{code:'ENOENT'});await assert.rejects(lstat(join(attempt,'summary.json')),{code:'ENOENT'});
});
