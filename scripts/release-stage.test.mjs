// Real existing archive/fixed-set owners with inert payloads; every registry
// and npm stage operation is an injected component port. No trust, approval,
// actual stage, 2FA, publisher credential or product runtime is exercised.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, cp, lstat, mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test, {before, after} from 'node:test';
import {admitCohort, stagePackage} from './package-release.mjs';
import {freezeReleaseSet, prepareReleaseReview, verifyReleaseSet} from './release-set.mjs';
import {publicConsumerEnvironment} from './release-public-install.mjs';
import {observeNpmStageTarget} from './release-registry.mjs';
import {npmStagePlan, stagePackageRelease} from './publish-package-release.mjs';
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

async function fixture(t) {
  const own = await mkdtemp(join(root, 'case-')); t.after(() => rm(own, {recursive: true, force: true}));
  const directory = join(own, 'fixed'); await cp(join(root, 'reviewed'), directory, {recursive: true});
  const artifacts = reviewed.manifest.artifacts, originals = new Map();
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
    if (args.length === 1 && args[0] === '--version') return {code: 0, stdout: control.wrongTool ? '10.9.4\n' : '11.15.0\n'};
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
    return {code: 0, stdout: control.malformedReply ? '{' : JSON.stringify({[item.name]: {id: `${item.name}@${item.version}`,
      name: item.name, version: item.version, size: item.bytes, integrity: item.integrity, stageId: id + control.stageIdSuffix}})};
  };
  const receiptsDirectory = join(own, 'receipts');
  const options = {directory, expectedSha256: reviewed.sha256, targetId: 'node', receiptsDirectory,
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
    assert.deepEqual(args, ['--version']); initialProbes++; return {code: 0, stdout: '11.16.0\n'};
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
