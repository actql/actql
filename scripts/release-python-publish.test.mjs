// Existing full wheel/fixed/review owners with inert wheel containers. Every
// HTTP/upload/signing result below is injected, never actual PyPI or approval.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, cp, lstat, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import test, {before, after} from 'node:test';
import {inspect} from 'node:util';
import {writeInertPythonReleaseCohort} from './fixtures/release-python-wheels.mjs';
import {freezeReleaseSet, prepareReleaseReview} from './release-set.mjs';
import {pythonPublishPlan, publishPythonReleaseProject} from './publish-package-release.mjs';
import {runRelease} from './release.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const actionRevision = 'dc37677b2e1c63e2034f94d8a5b11f265b73ba33'; // Source DATA only, not an executed image/tool.
let root, python, reviewed, noRecovery, unaccepted, extraPlatform;
before(async () => {
  root = await mkdtemp(join(tmpdir(), 'actql-python-publish-'));
  python = execFileSync('python3', ['-c', 'import os,sys;print(os.path.realpath(sys.executable))'], {encoding: 'utf8'}).trim();
  const cohort = join(root, 'original'); await writeInertPythonReleaseCohort(cohort, python);
  const request = {schemaVersion: 'actql-release-request/0.1', releaseId: 'inert-python-publish-only', version: '0.0.7-rc.1',
    source: {repository: 'https://github.com/actql/actql', commit: 'a'.repeat(40), branch: 'main'},
    targets: [{id: 'python', ecosystem: 'pypi', packages: ['actql-sdk', 'actql-local-runtime', 'actql'],
      platforms: ['darwin-arm64'], profiles: ['local'], destination: 'https://upload.pypi.org/legacy/', channels: []}],
    notes: {summary: 'Inert protocol test, no candidate or publisher', breakingChanges: [], migration: [], knownLimitations: ['No engine, public runtime or trust']}};
  const policy = {schemaVersion: 'actql-release-policy/0.1', allowedLines: ['0.0'], publicationAuthority: 'external-owner-approval-required'};
  const directory = join(root, 'preparation');
  const fixed = await freezeReleaseSet({request, policy, cohorts: [{targetId: 'python', kind: 'python-wheels', directory: cohort}], destination: directory, python});
  const inputs = join(root, 'review-inputs'); await mkdir(inputs); const evidence = [];
  for (const kind of ['recipe', 'toolchain', 'build', 'acceptance']) {
    const file = `${kind}.txt`, bytes = Buffer.from(`INERT supplied ${kind}, never accepted evidence\n`); await writeFile(join(inputs, file), bytes);
    evidence.push({id: kind, kind, file, bytes: bytes.length, sha256: sha(bytes)});
  }
  const review = {schemaVersion: 'actql-release-review-request/0.1', manifestSha256: fixed.sha256, evidence,
    provenance: [{targetId: 'python', recipeEvidence: 'recipe', toolchainEvidence: 'toolchain', build: {kind: 'local', run: 'inert', artifactId: null, evidence: 'build'}}],
    environments: [{targetId: 'python', platforms: ['darwin-arm64'], profiles: ['local'], node: null, python: 'inert metadata only', abi: 'inert', limitations: ['No runtime']}],
    acceptance: [{targetId: 'python', phase: 'prepublication-install', status: 'passed', evidence: ['acceptance'], limitations: ['Supplied label only; not real acceptance']},
      {targetId: 'python', phase: 'public-install', status: 'not-run', evidence: [], limitations: ['No public candidate']}],
    changes: {previousSource: null, diffEvidence: null}, executionScope: {publish: ['python'], promote: [], resumeIdenticalMissing: ['python']}};
  const file = join(inputs, 'review.json'); await writeFile(file, JSON.stringify(review));
  reviewed = await prepareReleaseReview({directory, expectedSha256: fixed.sha256, reviewFile: file, destination: join(root, 'reviewed')});
  review.executionScope.resumeIdenticalMissing = []; await writeFile(file, JSON.stringify(review));
  noRecovery = await prepareReleaseReview({directory, expectedSha256: fixed.sha256, reviewFile: file, destination: join(root, 'no-recovery')});
  review.executionScope.resumeIdenticalMissing = ['python'];
  review.acceptance[0].status = 'not-run'; review.acceptance[0].evidence = []; await writeFile(file, JSON.stringify(review));
  unaccepted = await prepareReleaseReview({directory, expectedSha256: fixed.sha256, reviewFile: file, destination: join(root, 'unaccepted')});
  const wideRequest = structuredClone(request); wideRequest.targets[0].platforms.push('linux-x64');
  const wideDirectory = join(root, 'wide-preparation');
  const wide = await freezeReleaseSet({request: wideRequest, policy, cohorts: [{targetId: 'python', kind: 'python-wheels', directory: cohort}], destination: wideDirectory, python});
  review.manifestSha256 = wide.sha256; review.environments[0].platforms = wideRequest.targets[0].platforms;
  review.acceptance[0].status = 'passed'; review.acceptance[0].evidence = ['acceptance']; await writeFile(file, JSON.stringify(review));
  extraPlatform = await prepareReleaseReview({directory: wideDirectory, expectedSha256: wide.sha256, reviewFile: file, destination: join(root, 'extra-platform')});
});
after(async () => {if (root) await rm(root, {recursive: true});});

async function fixture(t, recovery = true, variant = null) {
  const own = await mkdtemp(join(root, 'case-')); t.after(() => rm(own, {recursive: true}));
  const selected = variant === 'unaccepted' ? unaccepted : variant === 'extra-platform' ? extraPlatform : recovery ? reviewed : noRecovery;
  const original = variant ?? (recovery ? 'reviewed' : 'no-recovery'), directory = join(own, 'fixed');
  await cp(join(root, original), directory, {recursive: true});
  const artifacts = selected.manifest.artifacts, originals = new Map(), published = new Map(), calls = [], jobs = [];
  for (const item of artifacts) originals.set(item.name, await readFile(join(directory, item.path)));
  const control = {}, count = new Map();
  const fetchResponse = async (url, options) => {
    calls.push(url); assert.equal(options.method, 'GET'); assert.equal(options.credentials, 'omit'); assert.equal(options.redirect, 'error');
    assert.equal(options.headers.authorization, undefined); assert.equal(options.body, undefined);
    const item = artifacts.find(value => url === `https://pypi.org/pypi/${value.name}/${value.version}/json`);
    if (item) {
      count.set(item.name, (count.get(item.name) ?? 0) + 1);
      if (control.race === item.name && count.get(item.name) >= 2) published.set(item.name, originals.get(item.name));
      if (control.unavailable === item.name || control.afterUnavailable && jobs.length) return new Response('', {status: 403});
      if (!published.has(item.name)) return new Response('', {status: 404});
      const urls = [{filename: item.file, digests: {sha256: item.sha256}, size: item.bytes, packagetype: 'bdist_wheel', yanked: false,
        url: `https://files.pythonhosted.org/packages/aa/${item.file}`}];
      if (control.foreign === item.name) urls.push({...urls[0], filename: 'old_foreign-0.0.7rc1-py3-none-any.whl'});
      return Response.json({info: {name: item.name, version: item.version}, urls});
    }
    const body = artifacts.find(value => url === `https://files.pythonhosted.org/packages/aa/${value.file}`); assert(body, url);
    return new Response(published.get(body.name));
  };
  const options = {directory, expectedSha256: selected.sha256, targetId: 'python', python, actionRevision,
    publisherWorkspace: own, receiptsDirectory: join(own, 'receipts'), fetchResponse,
    runProjectJob: async (action, context) => {
      assert.equal(action.uses, `pypa/gh-action-pypi-publish@${actionRevision}`); assert(Object.isFrozen(action) && Object.isFrozen(action.with));
      assert.deepEqual(Object.keys(action.with).sort(), ['packages-dir', 'repository-url', 'verify-metadata', 'skip-existing', 'attestations'].sort());
      assert.equal(action.with['repository-url'], 'https://upload.pypi.org/legacy/'); assert.equal(action.with['skip-existing'], 'false');
      assert.equal(action.with['verify-metadata'], 'true'); assert.equal(action.with.attestations, 'true');
      const payload = action.with['packages-dir'], item = artifacts.find(value => value.name === context.project);
      assert.equal(context.manifestSha256, selected.sha256); assert.equal(context.targetId, 'python');
      const intent = JSON.parse(await readFile(join(dirname(payload), 'intent.json'))); assert.deepEqual(intent.artifact, item); assert.deepEqual(intent.action, action);
      assert.deepEqual(await readdir(payload), [item.file]); const path = join(payload, item.file);
      assert.deepEqual(await readFile(path), originals.get(item.name)); assert.equal((await lstat(path)).mode & 0o777, 0o400);
      jobs.push({project: context.project, action, payload, intent});
      if (!control.noPublic) published.set(item.name, originals.get(item.name));
      if (control.throwReply) throw Error('Original fake terminal job response lost');
      if (control.malformed) return {code: 0, signal: null, stdout: 1, stderr: ''};
      if (control.changeWheel) {await chmod(path, 0o600); await writeFile(path, 'Changed original private wheel');}
      if (control.changeFixed) await writeFile(join(directory, item.path), 'Changed original frozen wheel');
      if (control.extraPayload) await writeFile(join(payload, 'unselected.whl'), 'Not approved');
      if (control.linkedAttestation) await symlink('/unselected-must-not-be-followed', `${path}.publish.attestation`);
      else if (control.oversizedAttestation) await writeFile(`${path}.publish.attestation`, Buffer.alloc(4 * 1024 * 1024 + 1));
      else if (!control.noAttestation) await writeFile(`${path}.publish.attestation`, '{"inert":"NOT a signature or real publisher"}\n');
      return {code: control.failedCode ? 1 : 0, signal: null, stdout: 'INERT terminal project job\n', stderr: ''};
    }};
  return {own, options, selected, artifacts, originals, published, calls, jobs, control,
    publish: project => publishPythonReleaseProject({...options, project}),
    attempts: async project => {
      const dir = join(own, 'receipts', selected.sha256, 'python', project);
      return (await readdir(dir)).map(value => join(dir, value));
    }};
}

test('Python publish: read-only exact plan has three separate jobs and no credential or executable CLI route', async t => {
  const f = await fixture(t), before = await readFile(join(f.options.directory, 'release-set.json'));
  const plan = await runRelease(['python-publish-plan', f.options.directory, f.selected.sha256, 'python', python, actionRevision]);
  assert.equal(plan.execution, 'unavailable'); assert.equal(plan.uses, `pypa/gh-action-pypi-publish@${actionRevision}`);
  assert.deepEqual(plan.jobs.map(value => [value.project, value.after, value.actionInvocationsPerJob]),
    [['actql-sdk', [], 1], ['actql-local-runtime', [], 1], ['actql', ['actql-sdk', 'actql-local-runtime'], 1]]);
  assert(plan.jobs.every(value => value.inputs['skip-existing'] === 'false' && value.inputs.attestations === 'true'));
  await assert.rejects(pythonPublishPlan(f.options.directory, f.selected.sha256, 'python', python, 'release/v1'));
  await assert.rejects(pythonPublishPlan(f.options.directory, f.selected.sha256, 'python', 'python3', actionRevision));
  await assert.rejects(runRelease(['python-publish', f.options.directory]), /publication authority/u);
  await assert.rejects(publishPythonReleaseProject({...f.options, project: 'actql-sdk', approved: true}), /Unexpected/u);
  await assert.rejects(publishPythonReleaseProject({...f.options, project: 'actql-sdk', runProjectJob: undefined}), /No protected/u);
  assert.equal(f.jobs.length, 0); assert.equal(f.calls.length, 0); assert.deepEqual(await readFile(join(f.options.directory, 'release-set.json')), before);
});

test('Python publish: one immutable project per job, original full byte readback and dependency gate keep facade last', async t => {
  const f = await fixture(t);
  await assert.rejects(f.publish('actql'), /Facade publication waits/u); assert.equal(f.jobs.length, 0);
  for (const project of ['actql-sdk', 'actql-local-runtime', 'actql']) {
    const result = await f.publish(project); assert.equal(result.state, 'command-and-public-bytes-confirmed');
    assert.match(result.attestation.qualification, /cryptographic.*not established/u);
    const intent = JSON.parse(await readFile(join(result.receiptDirectory, 'intent.json')));
    assert.equal(intent.project, project); assert.equal(intent.manifestSha256, f.selected.sha256);
    assert.equal(JSON.parse(await readFile(join(result.receiptDirectory, 'command.json'))).commandSucceeded, true);
  }
  assert.deepEqual(f.jobs.map(value => value.project), ['actql-sdk', 'actql-local-runtime', 'actql']);
  assert.equal(f.published.size, 3);
});

test('Python publish: whole-target unknown conflict and foreign placeholder stop before any project send', async t => {
  for (const kind of ['unavailable', 'corrupt', 'foreign']) {
    const f = await fixture(t);
    if (kind === 'unavailable') f.control.unavailable = 'actql';
    else {f.published.set('actql-local-runtime', kind === 'corrupt' ? Buffer.from('different') : f.originals.get('actql-local-runtime'));
      if (kind === 'foreign') f.control.foreign = 'actql-local-runtime';}
    await assert.rejects(f.publish('actql-sdk'), /unknown or conflicting/u); assert.equal(f.jobs.length, 0);
  }
});

test('Python publish: lost original terminal response keeps Unknown intent and same-byte resume does not resend', async t => {
  const f = await fixture(t); f.control.throwReply = true;
  await assert.rejects(f.publish('actql-sdk'), /outcome unknown/u); assert.equal(f.jobs.length, 1);
  const [original] = await f.attempts('actql-sdk'); assert.equal(JSON.parse(await readFile(join(original, 'unknown.json'))).state, 'unknown');
  await assert.rejects(readFile(join(original, 'summary.json')), {code: 'ENOENT'});
  f.control.throwReply = false; const resumed = await f.publish('actql-sdk');
  assert.equal(resumed.state, 'already-identical'); assert.equal(resumed.attestation, null); assert.equal(f.jobs.length, 1);
  assert.notEqual(resumed.receiptDirectory, original); assert.equal(JSON.parse(await readFile(join(original, 'unknown.json'))).state, 'unknown');
});

test('Python publish: same-byte recovery scope remains required even after a lost successful reply', async t => {
  const f = await fixture(t, false); f.control.throwReply = true;
  await assert.rejects(f.publish('actql-sdk'), /outcome unknown/u);
  f.control.throwReply = false; await assert.rejects(f.publish('actql-sdk'), /recovery was not/u);
  assert.equal(f.jobs.length, 1);
});

test('Python publish: command success and public confirmation are distinct; denial retains original command and attestation', async t => {
  const f = await fixture(t); f.control.afterUnavailable = true;
  await assert.rejects(f.publish('actql-sdk'), /unknown or conflicting/u);
  const [original] = await f.attempts('actql-sdk');
  assert.equal(JSON.parse(await readFile(join(original, 'command.json'))).commandSucceeded, true);
  assert.equal(JSON.parse(await readFile(join(original, 'after.json'))).observations[0].state, 'unknown');
  await assert.rejects(readFile(join(original, 'summary.json')), {code: 'ENOENT'});
  f.control.afterUnavailable = false; assert.equal((await f.publish('actql-sdk')).state, 'already-identical'); assert.equal(f.jobs.length, 1);
});

test('Python publish: malformed failed and unconfirmed original job results never make a successful attempt', async t => {
  for (const kind of ['malformed', 'failedCode', 'noPublic', 'noAttestation']) {
    const f = await fixture(t); f.control[kind] = true;
    await assert.rejects(f.publish('actql-sdk'));
    assert.equal(f.jobs.length, 1); const [original] = await f.attempts('actql-sdk');
    assert.equal(JSON.parse(await readFile(join(original, 'intent.json'))).outcome, 'unknown-until-original-job-terminal-and-public-byte-readback');
    await assert.rejects(readFile(join(original, 'summary.json')), {code: 'ENOENT'});
  }
});

test('Python publish: changed wheel fixed source or unselected extra payload cannot inherit original intent', async t => {
  for (const kind of ['changeWheel', 'changeFixed', 'extraPayload']) {
    const f = await fixture(t); f.control[kind] = true;
    await assert.rejects(f.publish('actql-sdk')); assert.equal(f.jobs.length, 1);
    const [original] = await f.attempts('actql-sdk'); await assert.rejects(readFile(join(original, 'summary.json')), {code: 'ENOENT'});
  }
});

test('Python publish: freshly present original wheel is reused without a project job and occupied changed bytes never resend', async t => {
  const f = await fixture(t); f.control.race = 'actql-sdk';
  assert.equal((await f.publish('actql-sdk')).state, 'already-identical'); assert.equal(f.jobs.length, 0);
  f.control.race = null; f.published.set('actql-sdk', Buffer.from('occupied different bytes'));
  await assert.rejects(f.publish('actql-sdk'), /unknown or conflicting/u); assert.equal(f.jobs.length, 0);
});

test('Python publish: outside normalized and shell-unsafe action payload paths refuse before public read or job', async t => {
  const f = await fixture(t);
  for (const path of [join(f.own, '..', 'outside'), join(f.own, 'unsafe payload'), join(f.own, 'glob*')])
    await assert.rejects(publishPythonReleaseProject({...f.options, project: 'actql-sdk', receiptsDirectory: path}));
  assert.equal(f.calls.length, 0); assert.equal(f.jobs.length, 0);
});

test('Python publish: explicit unaccepted evidence or extra unverified platform never enters a project job', async t => {
  for (const variant of ['unaccepted', 'extra-platform']) {
    const f = await fixture(t, true, variant); await assert.rejects(f.publish('actql-sdk'));
    assert.equal(f.jobs.length, 0); assert.equal(f.calls.length, 0);
  }
});

test('Python publish: preflight fixed-byte tamper missing wheel or wrong retained digest refuses before any public or job call', async t => {
  for (const kind of ['changed', 'missing', 'digest']) {
    const f = await fixture(t), first = f.artifacts[0], path = join(f.options.directory, first.path);
    if (kind === 'changed') await writeFile(path, 'Changed frozen input before preflight');
    else if (kind === 'missing') await rm(path); else f.options.expectedSha256 = 'f'.repeat(64);
    await assert.rejects(f.publish('actql-sdk')); assert.equal(f.jobs.length, 0); assert.equal(f.calls.length, 0);
  }
});

test('Python publish: publisher sidecar bounds and links are checked as raw output without claiming signature verification', async t => {
  for (const kind of ['linkedAttestation', 'oversizedAttestation']) {
    const f = await fixture(t); f.control[kind] = true;
    await assert.rejects(f.publish('actql-sdk')); assert.equal(f.jobs.length, 1);
    const [original] = await f.attempts('actql-sdk');
    assert.equal(JSON.parse(await readFile(join(original, 'command.json'))).commandSucceeded, true);
    await assert.rejects(readFile(join(original, 'summary.json')), {code: 'ENOENT'});
  }
});

test('Python publish failure custody: SAME private job failure reaches caller without receipt or normal error-output leakage',async t=>{
  const f=await fixture(t),original=f.options.runProjectJob;
  const failure=Object.assign(Error('PRIVATE-INERT-PYTHON-JOB-MARKER'),{originalCleanup:{inertIdentityOnly:true}});
  f.options.runProjectJob=async(action,context)=>{await original(action,context);throw failure;};
  let caught;try{await f.publish('actql-sdk');}catch(error){caught=error;}
  assert(caught);assert.equal(caught.originalPublisherFailure,failure);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalPublisherFailure').enumerable,false);
  assert(!String(caught).includes('PRIVATE-INERT'));assert(!inspect(caught).includes('PRIVATE-INERT'));
  assert.equal(f.jobs.length,1);assert.equal(f.published.size,1);
  const [attempt]=await f.attempts('actql-sdk');
  assert.equal(JSON.parse(await readFile(join(attempt,'unknown.json'))).reason,'original-job-response-lost');
  for(const file of await readdir(attempt))if((await lstat(join(attempt,file))).isFile())
    assert(!(await readFile(join(attempt,file),'utf8')).includes('PRIVATE-INERT'));
});

test('Python publish failure custody: Unknown receipt write refusal retains BOTH original job failure and physical write error',async t=>{
  const f=await fixture(t),original=f.options.runProjectJob;
  const failure=Object.assign(Error('PRIVATE-INERT-PYTHON-WRITE-MARKER'),{originalCleanup:{inertIdentityOnly:true}});
  let attempt,caught;
  f.options.runProjectJob=async(action,context)=>{
    await original(action,context);attempt=dirname(action.with['packages-dir']);await chmod(attempt,0o500);throw failure;
  };
  try{await f.publish('actql-sdk');}catch(error){caught=error;}
  finally{if(attempt)await chmod(attempt,0o700);}
  assert(caught);assert.equal(caught.code,'EACCES');assert.notEqual(caught,failure);
  assert.equal(caught.originalPublisherFailure,failure);
  assert.equal(Object.getOwnPropertyDescriptor(caught,'originalPublisherFailure').enumerable,false);
  assert(!inspect(caught).includes('PRIVATE-INERT'));assert.equal(f.jobs.length,1);
  assert.equal(JSON.parse(await readFile(join(attempt,'intent.json'))).outcome,'unknown-until-original-job-terminal-and-public-byte-readback');
  await assert.rejects(readFile(join(attempt,'unknown.json')),{code:'ENOENT'});
});
