// Reusable protocol for a separately protected owner-approved executor.
// Direct CLI publication stays disabled; bytes never establish authority.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {lstat, mkdir, mkdtemp, open, readFile, readdir, realpath, rm, writeFile} from 'node:fs/promises';
import {basename, dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {inventory, publicationPlan, publishedVersion, unpack, verifyPackageRelease} from './package-release.mjs';
import {refuseUnconfiguredPublication} from './release-authority.mjs';
import {nativeReleaseDraftRequest, readFrozenReleaseArtifact, verifyReleaseSet, verifyReleasePromotionReview} from './release-set.mjs';
import {observeNativePublicationTarget, observeNpmStageTarget, observePythonReleaseTarget,
  observeReleaseSet, observeReleaseChannels} from './release-registry.mjs';
import {requireNativeCohortPackageVersions} from './native-cli-artifact-reader.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
// Preserve the SAME original exception and its cleanup duty for the caller,
// without exposing authentication or child output in receipts/normal inspect.
function retainOriginalPublisherFailure(error, failure, property = 'originalPublisherFailure') {
  return Object.defineProperty(error, property, {value: failure, enumerable: false});
}

const stageUuid = value => typeof value === 'string' && value.length === 36 && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu.test(value);
const stableTool = value => {
  assert(typeof value === 'string' && value.length <= 64 && value === value.trim());
  assert.match(value, /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/u);
  return value.split('.').map(BigInt);
};
const atLeast = (actual, required) => {
  const a = stableTool(actual), b = stableTool(required);
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] > b[i];
  return true;
};

function stageArguments(path, target) {
  return ['stage', 'publish', path, '--ignore-scripts', '--json', '--registry', target.registry,
    '--access', 'public', '--tag', target.tag, '--provenance'];
}

async function stageSelection(directory, expectedSha256, targetId) {
  const fixed = await verifyReleaseSet(directory, {expectedSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === targetId);
  assert(target?.ecosystem === 'npm', 'Select one complete original npm target');
  assert(fixed.review?.executionScope.publish.includes(targetId), 'Staging needs the bound proposed publication scope and evidence');
  const child = fixed.manifest.cohorts.find(value => value.targetId === targetId);
  assert(['node-npm', 'native-npm'].includes(child.kind));
  const manifest = JSON.parse(await readFile(join(directory, child.path)));
  if (child.kind === 'native-npm') requireNativeCohortPackageVersions(manifest);
  assert.equal(manifest.cohort.registry, 'https://registry.npmjs.org/');
  assert.equal(manifest.cohort.access, 'public'); assert(target.channels.includes(manifest.cohort.tag));
  assert(manifest.cohort.tag !== 'latest' && !/^release-[0-9]+\.[0-9]+$/u.test(manifest.cohort.tag) &&
    !fixed.review.executionScope.promote.some(value => value.targetId === targetId && value.channel === manifest.cohort.tag),
  'Use a separate staging tag; final channels require the protected promotion boundary');
  return {fixed, target, child: manifest, registry: manifest.cohort.registry, tag: manifest.cohort.tag,
    artifacts: fixed.manifest.artifacts.filter(value => value.targetId === targetId)};
}

export async function npmStagePlan(directory, expectedSha256, targetId) {
  const selected = await stageSelection(directory, expectedSha256, targetId);
  return {schemaVersion: 'actql-npm-stage-plan/0.1', manifestSha256: selected.fixed.sha256, targetId,
    execution: 'unavailable', tools: {minimumNode: '22.14.0', minimumNpm: '11.15.0', exactNpmPin: 'required-by-protected-runner'},
    packages: selected.artifacts.map(item => ({name: item.name, version: item.version, file: item.file,
      bytes: item.bytes, sha256: item.sha256, integrity: item.integrity, tag: selected.tag,
      proposedArguments: stageArguments(resolve(directory, item.path), selected)})),
    pending: ['Independent owner approval of exact upper set and permitted recovery scope',
      'Protected immutable validator/workflow, one exclusive executor and actual stage-only registry trust',
      'Separate owner read port for complete pending-stage inventory and actual tarball bytes',
      'Separate owner-authorized initial-name operation when a stage would create a public placeholder',
      'Verified pinned runner/provenance source and actual npm 2FA owner approval; no approval/reject/channel command is executed here']};
}

async function privateDirectory(path) {
  let created = false;
  try {await mkdir(path, {mode: 0o700}); created = true;} catch (failure) {if (failure.code !== 'EEXIST') throw failure;}
  const st = await lstat(path);
  assert(st.isDirectory() && !st.isSymbolicLink() && (st.mode & 0o077) === 0, 'Select an original private receipt directory');
  if (created) await syncDirectory(dirname(path));
}

async function syncDirectory(path) {
  const handle = await open(path, 'r');
  let primary;
  try {await handle.sync();} catch (failure) {primary = failure;}
  await closeOriginal(handle, primary);
}

async function closeOriginal(handle, primary) {
  try {await handle.close();} catch (cleanup) {
    const pending = Error('Original release receipt descriptor cleanup pending');
    Object.assign(pending, {originalHandle: handle, originalError: primary, cleanupError: cleanup});
    throw pending;
  }
  if (primary) throw primary;
}

async function writePrivateOriginal(path, bytes, mode = 0o600) {
  const handle = await open(path, 'wx', mode);
  let primary;
  try {await handle.writeFile(bytes); await handle.chmod(mode); await handle.sync();} catch (failure) {primary = failure;}
  await closeOriginal(handle, primary);
  await syncDirectory(dirname(path));
}

async function inspectStagePayload(directory, expectedSha256, targetId, item, selected) {
  const captured = await readFrozenReleaseArtifact(directory, expectedSha256, targetId, item.file);
  const scratch = await mkdtemp(join(tmpdir(), 'actql-stage-inspect-'));
  try {
    const file = join(scratch, item.file); await writeFile(file, captured.bytes, {flag: 'wx', mode: 0o600});
    const payload = await unpack(file, join(scratch, 'content'));
    const original = selected.child.packages.find(value => value.name === item.name);
    assert.deepEqual(await inventory(payload), original.files, 'Stage payload differs from its complete original inventory');
    const metadata = JSON.parse(await readFile(join(payload, 'package.json')));
    assert.equal(metadata.name, item.name); assert.equal(metadata.version, item.version);
    // Preserve each existing producer's metadata contract: Native intentionally
    // omits private; Node projects it explicitly to false. Neither accepts true.
    assert.equal(metadata.private, selected.child.version === 'actql-native-cli-release/0.1' ? undefined : false);
    assert.deepEqual(metadata.publishConfig, {registry: selected.registry, access: 'public'}, 'Unexpected publisher configuration in artifact');
    for (const name of ['preinstall', 'install', 'postinstall', 'prepublish', 'prepublishOnly', 'prepare', 'prepack', 'postpack', 'publish', 'postpublish'])
      assert.equal(metadata.scripts?.[name], undefined, 'Publication jobs never run or prepare artifact lifecycle scripts');
    const names = selected.artifacts.map(value => value.name);
    for (const kind of ['dependencies', 'peerDependencies', 'optionalDependencies'])
      for (const [name, version] of Object.entries(metadata[kind] ?? {}))
        if (name.startsWith('@actql/') || names.includes(name)) {
          assert(names.includes(name), 'Incomplete staged cohort dependency'); assert.equal(version, item.version);
        }
  } finally {await rm(scratch, {recursive: true});}
}

function stageResponse(stdout, item) {
  const value = JSON.parse(new TextDecoder('utf8', {fatal: true}).decode(stdout));
  assert.deepEqual(Object.keys(value), [item.name], 'Stage stdout is not the one selected package');
  const body = value[item.name];
  assert.equal(body.id, `${item.name}@${item.version}`); assert.equal(body.name, item.name); assert.equal(body.version, item.version);
  assert.equal(body.size, item.bytes); assert.equal(body.integrity, item.integrity); assert(stageUuid(body.stageId), 'Missing original stage id');
  return body.stageId;
}

// Reusable protocol inside the existing publisher Owner, NOT an authority
// boundary. No default runner/read credentials/CLI route exists. The external
// protected executor must supply owner approval, isolation, exclusive current
// execution and verified pinned tools. Callback presence or local JSON proves
// none of those duties. Initial-name execution uses a separate owner port.
// A runner must settle only after its original child has terminated. Lost
// observation keeps that SAME child/handle with the protected executor; it
// cannot be converted into a second invocation while execution is live.
export async function stagePackageRelease(options) {
  const allowed = ['directory', 'expectedSha256', 'targetId', 'receiptsDirectory', 'npmVersion', 'runNpm', 'fetchStage', 'fetchResponse', 'executeInitialStage'];
  assert(options && Object.keys(options).every(key => allowed.includes(key)), 'Unexpected stage execution fields');
  const {directory, expectedSha256, targetId, receiptsDirectory, npmVersion, runNpm,
    fetchStage, fetchResponse = fetch, executeInitialStage} = options;
  assert.equal(typeof runNpm, 'function', 'No protected npm runner supplied');
  assert.equal(typeof fetchStage, 'function', 'No separate owner stage read port supplied');
  if (executeInitialStage !== undefined) assert.equal(typeof executeInitialStage, 'function');
  const selected = await stageSelection(directory, expectedSha256, targetId);
  assert(atLeast(process.versions.node, '22.14.0'), 'Selected stage runner needs Node22.14 or newer');
  assert(atLeast(npmVersion, '11.15.0'), 'Selected stage runner needs npm11.15 or newer');
  const tool = await runNpm(['--version']);
  assert(tool?.code === 0 && tool.signal === null && typeof tool.stdout === 'string' && tool.stdout === `${npmVersion}\n`, 'Actual npm differs from the explicit protected pin');
  const observe = file => observeNpmStageTarget(directory, expectedSha256, targetId, {fetchStage, fetchResponse, file});
  const initial = await observe(null);
  assert(initial.observations.every(value => ['published', 'pending', 'missing'].includes(value.state)), 'Stage preflight is unknown or conflicting');
  for (const item of selected.artifacts) await inspectStagePayload(directory, expectedSha256, targetId, item, selected);
  if (initial.observations.some(value => value.state === 'missing' && value.namespace === 'absent')) {
    assert.equal(typeof executeInitialStage, 'function', 'Initial name would create a public placeholder; separate owner operation required');
  }
  const root = resolve(receiptsDirectory); await privateDirectory(root);
  const releaseRoot = join(root, expectedSha256); await privateDirectory(releaseRoot);
  const targetRoot = join(releaseRoot, targetId); await privateDirectory(targetRoot);
  const prior = await readdir(targetRoot);
  assert(prior.every(value => value.startsWith('attempt-') && stageUuid(value.slice(8))), 'Unrecognized original stage receipt entry');
  for (const name of prior) {const st = await lstat(join(targetRoot, name)); assert(st.isDirectory() && !st.isSymbolicLink(), 'Original receipt directory cannot be a link');}
  if (prior.length) assert(selected.fixed.review.executionScope.resumeIdenticalMissing.includes(targetId), 'Original proposed scope did not include same-bytes recovery');
  const attemptId = randomUUID(), attempt = join(targetRoot, `attempt-${attemptId}`);
  await mkdir(attempt, {mode: 0o700}); await syncDirectory(targetRoot);
  const record = async (name, value) => {
    const bytes = Buffer.isBuffer(value) ? value : Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
    await writePrivateOriginal(join(attempt, name), bytes);
    return {file: name, bytes: bytes.length, sha256: digest(bytes)};
  };
  await record('preflight.json', initial);
  const results = [];
  for (const [index, item] of selected.artifacts.entries()) {
    const fresh = await observe(item.file); await record(`${index}-before.json`, fresh);
    const current = fresh.observations[0];
    assert(['published', 'pending', 'missing'].includes(current.state), 'Original stage boundary became unavailable');
    if (current.state !== 'missing') {results.push(current); continue;}
    const execute = current.namespace === 'absent' ? executeInitialStage : runNpm;
    assert.equal(typeof execute, 'function', 'Initial-name owner operation unavailable at the actual boundary');
    if (current.namespace === 'absent') {
      const initialTool = await execute(['--version']);
      assert(initialTool?.code === 0 && initialTool.signal === null && initialTool.stdout === `${npmVersion}\n`, 'Initial-name owner tool differs from the explicit pin');
    }
    const captured = await readFrozenReleaseArtifact(directory, expectedSha256, targetId, item.file);
    const payloadRoot = join(attempt, `payload-${index}`); await mkdir(payloadRoot, {mode: 0o700}); await syncDirectory(attempt);
    const path = join(payloadRoot, item.file); await writePrivateOriginal(path, captured.bytes, 0o400);
    const args = Object.freeze(stageArguments(path, selected));
    await record(`${index}-intent.json`, {schemaVersion: 'actql-npm-stage-intent/0.1', at: new Date().toISOString(),
      manifestSha256: expectedSha256, targetId, attemptId, artifact: item, namespace: current.namespace,
      npmVersion, args, outcome: 'unknown-until-original-response-and-owner-readback'});
    let reply;
    try {reply = await execute(args, {manifestSha256: expectedSha256, targetId, artifact: structuredClone(item), namespace: current.namespace});}
    catch (failure) {
      try {await record(`${index}-unknown.json`, {state: 'unknown', reason: 'runner-threw', originalIntent: `${index}-intent.json`});}
      catch (cleanup) {throw retainOriginalPublisherFailure(cleanup, failure);}
      throw retainOriginalPublisherFailure(Error(`Original stage outcome unknown; preserve ${attempt} and reobserve with the original owner reader`), failure);
    }
    if (!reply || typeof reply.stdout !== 'string' || Buffer.byteLength(reply.stdout) > 1024 * 1024) {
      await record(`${index}-unknown.json`, {state: 'unknown', reason: 'invalid-or-oversized-runner-response'});
      throw Error(`Original stage outcome unknown; preserve ${attempt}`);
    }
    const output = Buffer.from(reply.stdout), code = reply.code, signal = reply.signal;
    const raw = await record(`${index}-stdout.json`, output);
    const terminal = {};
    if (code === null || Number.isInteger(code)) terminal.code = code;
    else terminal.unreportedOrInvalidCode = true;
    if (signal === null || (typeof signal === 'string' && Buffer.byteLength(signal) <= 64)) terminal.signal = signal;
    else terminal.unreportedOrInvalidSignal = true;
    // Keep original bounded terminal DATA separately from success and remote
    // readback. A receipt/descriptor failure retains its original cleanup duty.
    await record(`${index}-terminal.json`, terminal);
    let id;
    try {assert.equal(code, 0); assert.equal(signal, null); id = stageResponse(output, item);}
    catch {await record(`${index}-unknown.json`, {state: 'unknown', reason: 'command-or-original-response-unconfirmed', raw}); throw Error(`Original stage outcome unknown; preserve ${attempt}`);}
    await record(`${index}-command.json`, {schemaVersion: 'actql-npm-stage-command/0.1', manifestSha256: expectedSha256,
      targetId, code, signal, commandSucceeded: true, stageId: id, raw, confirmation: 'unobserved'});
    const after = await observe(item.file); await record(`${index}-after.json`, after);
    const confirmed = after.observations[0];
    assert(confirmed.state === 'published' || (confirmed.state === 'pending' && confirmed.stageId === id),
      `Stage command returned but original owner confirmation is unavailable; preserve ${attempt}`);
    results.push(confirmed);
  }
  await verifyReleaseSet(directory, {expectedSha256});
  const summary = {schemaVersion: 'actql-npm-stage-attempt/0.1', manifestSha256: expectedSha256, targetId, attemptId,
    at: new Date().toISOString(), results, qualification: 'same-byte staging protocol outcome only; owner 2FA publication, public install, trust isolation and exclusive execution remain independent'};
  await record('summary.json', summary); return {...summary, receiptDirectory: attempt};
}

const pythonProjects = ['actql-sdk', 'actql-local-runtime', 'actql'];
const pythonDependencies = project => project === 'actql' ? pythonProjects.slice(0, 2) : [];
const actionUses = revision => {
  assert.match(revision, /^[a-f0-9]{40}$/u, 'Select the protected full PyPA action revision, never a moving ref');
  return `pypa/gh-action-pypi-publish@${revision}`;
};

async function pythonPublishSelection(directory, expectedSha256, targetId, python, actionRevision) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u); assert(isAbsolute(python), 'Select one absolute verifier Python');
  const uses = actionUses(actionRevision), fixed = await verifyReleaseSet(directory, {expectedSha256});
  const target = fixed.manifest.request.targets.find(value => value.id === targetId);
  assert.equal(target?.ecosystem, 'pypi'); assert.equal(target.destination, 'https://upload.pypi.org/legacy/');
  assert.deepEqual(target.packages, pythonProjects, 'Use the complete original three-project Python cohort');
  assert(fixed.review?.executionScope.publish.includes(targetId), 'Python publication needs its bound proposed scope and evidence');
  const child = fixed.manifest.cohorts.find(value => value.targetId === targetId); assert.equal(child.kind, 'python-wheels');
  // This is the original cold wheel owner, executed only from the protected
  // immutable validator checkout, not executable code supplied by a candidate.
  const output = JSON.parse(execFileSync(python, [fileURLToPath(new URL('./python_release_cohort.py', import.meta.url)),
    '--verify-directory', dirname(join(resolve(directory), child.path)), '--source', fixed.manifest.request.source.commit,
    '--version', fixed.manifest.release.pythonVersion, '--frozen-layout'],
  {encoding: 'utf8', timeout: 60_000, maxBuffer: 4 * 1024 * 1024}));
  assert.equal(output.manifest_sha256, child.sha256);
  assert.deepEqual(target.platforms, [output.cohort.platform], 'No unverified extra Python platform can inherit this single original cohort');
  await verifyReleaseSet(directory, {expectedSha256});
  return {fixed, target, uses, artifacts: fixed.manifest.artifacts.filter(value => value.targetId === targetId)};
}

export async function pythonPublishPlan(directory, expectedSha256, targetId, python, actionRevision) {
  const selected = await pythonPublishSelection(directory, expectedSha256, targetId, python, actionRevision);
  return {schemaVersion: 'actql-python-publish-plan/0.1', manifestSha256: expectedSha256, targetId,
    execution: 'unavailable', uses: selected.uses,
    jobs: pythonProjects.map(project => ({project, after: pythonDependencies(project),
      artifacts: selected.artifacts.filter(value => value.name === project),
      actionInvocationsPerJob: 1, inputs: {'repository-url': selected.target.destination,
        'verify-metadata': 'true', 'skip-existing': 'false', attestations: 'true'}})),
    pending: ['Independent owner approval and actual accepted build/install evidence for this exact fixed set',
      'One protected exclusive executor, credential-free build and immutable trusted validator/workflow',
      'Separate top-level Linux job/Environment and PyPI project trust for each action invocation',
      'Actual action/container/tool correspondence; a commit-named image tag is not a measured immutable image digest',
      'No default runner/credentials; proposed scope, labels and function ports are not permission']};
}

// Same existing publisher/receipt Owner. This protocol is NOT an authority
// verifier. runProjectJob must be supplied only by the independent protected
// executor: exactly one action in one separately approved top-level Linux job,
// using this immutable validator and the original mounted workspace. It must
// settle only after that ORIGINAL job is terminal. A lost live observation
// retains the same job handle; never invoke another job on that basis.
export async function publishPythonReleaseProject(options) {
  const allowed = ['directory', 'expectedSha256', 'targetId', 'project', 'python', 'actionRevision',
    'publisherWorkspace', 'receiptsDirectory', 'runProjectJob', 'fetchResponse'];
  assert(options && Object.keys(options).every(key => allowed.includes(key)), 'Unexpected Python publication fields');
  const {directory, expectedSha256, targetId, project, python, actionRevision, publisherWorkspace,
    receiptsDirectory, runProjectJob, fetchResponse = fetch} = options;
  assert(pythonProjects.includes(project)); assert.equal(typeof runProjectJob, 'function', 'No protected project job supplied');
  const selected = await pythonPublishSelection(directory, expectedSha256, targetId, python, actionRevision);
  const acceptance = selected.fixed.review.acceptance.find(value => value.targetId === targetId && value.phase === 'prepublication-install');
  assert.equal(acceptance.status, 'passed', 'Prepublication evidence is not even supplied as passed');
  // This label is eligibility DATA only; the protected owner must independently
  // validate its actual evidence. It cannot be treated as approval or authority.
  assert(isAbsolute(publisherWorkspace) && isAbsolute(receiptsDirectory));
  const workspace = await realpath(publisherWorkspace), normalized = resolve(receiptsDirectory);
  const parent = await realpath(dirname(normalized)), root = join(parent, basename(normalized));
  const delta = relative(workspace, parent);
  assert(delta !== '..' && !delta.startsWith(`..${sep}`) && !isAbsolute(delta), 'Publisher payload must be in its original mounted workspace');
  assert.match(root, /^\/[A-Za-z0-9_./-]+$/u,
    'Selected action needs a literal Unix payload path without shell whitespace or glob syntax');
  const observe = () => observePythonReleaseTarget(directory, expectedSha256, targetId, {fetchResponse});
  const valid = observation => assert(observation.observations.every(value => ['present', 'absent'].includes(value.state)),
    'Original Python publication preflight is unknown or conflicting');
  const initial = await observe(); valid(initial);
  await privateDirectory(root);
  const releaseRoot = join(root, expectedSha256); await privateDirectory(releaseRoot);
  const targetRoot = join(releaseRoot, targetId); await privateDirectory(targetRoot);
  const projectRoot = join(targetRoot, project); await privateDirectory(projectRoot);
  const prior = await readdir(projectRoot);
  assert(prior.every(value => value.startsWith('attempt-') && stageUuid(value.slice(8))), 'Unrecognized original Python attempt');
  for (const value of prior) {const st = await lstat(join(projectRoot, value)); assert(st.isDirectory() && !st.isSymbolicLink());}
  if (prior.length) assert(selected.fixed.review.executionScope.resumeIdenticalMissing.includes(targetId), 'Same-bytes recovery was not in the original scope');
  const attemptId = randomUUID(), attempt = join(projectRoot, `attempt-${attemptId}`);
  await mkdir(attempt, {mode: 0o700}); await syncDirectory(projectRoot);
  const record = async (name, value) => {
    const bytes = Buffer.isBuffer(value) ? value : Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
    await writePrivateOriginal(join(attempt, name), bytes); return {file: name, bytes: bytes.length, sha256: digest(bytes)};
  };
  await record('preflight.json', initial);
  const fresh = await observe(); await record('before.json', fresh); valid(fresh);
  const item = selected.artifacts.find(value => value.name === project); assert(item);
  const current = fresh.observations.find(value => value.file === item.file);
  let actionState = 'already-identical', attestation = null;
  if (current.state === 'absent') {
    for (const dependency of pythonDependencies(project)) assert(fresh.observations.some(value =>
      value.name === dependency && value.state === 'present'), 'Facade publication waits for exact original SDK and runtime public bytes');
    const captured = await readFrozenReleaseArtifact(directory, expectedSha256, targetId, item.file);
    const payload = join(attempt, 'payload'); await mkdir(payload, {mode: 0o700}); await syncDirectory(attempt);
    const path = join(payload, item.file); await writePrivateOriginal(path, captured.bytes, 0o400);
    assert.deepEqual(await readdir(payload), [item.file]);
    const inputs = Object.freeze({'packages-dir': payload, 'repository-url': selected.target.destination,
      'verify-metadata': 'true', 'skip-existing': 'false', attestations: 'true'});
    const action = Object.freeze({uses: selected.uses, with: inputs});
    await record('intent.json', {schemaVersion: 'actql-python-publish-intent/0.1', at: new Date().toISOString(),
      manifestSha256: expectedSha256, targetId, project, attemptId, artifact: item, action,
      outcome: 'unknown-until-original-job-terminal-and-public-byte-readback'});
    let reply;
    try {reply = await runProjectJob(action, {manifestSha256: expectedSha256, targetId, project, artifact: structuredClone(item)});}
    catch (failure) {
      try {await record('unknown.json', {state: 'unknown', reason: 'original-job-response-lost'});}
      catch (cleanup) {throw retainOriginalPublisherFailure(cleanup, failure);}
      throw retainOriginalPublisherFailure(Error(`Original PyPI outcome unknown; preserve ${attempt}`), failure);
    }
    const stdoutText = reply?.stdout, stderrText = typeof stdoutText === 'string' ? reply.stderr : undefined;
    if (!reply || typeof stdoutText !== 'string' || typeof stderrText !== 'string' ||
        Buffer.byteLength(stdoutText) + Buffer.byteLength(stderrText) > 1024 * 1024) {
      await record('unknown.json', {state: 'unknown', reason: 'invalid-or-oversized-original-job-response'});
      throw Error(`Original PyPI outcome unknown; preserve ${attempt}`);
    }
    const code = reply.code, signal = reply.signal, stdoutBytes = Buffer.from(stdoutText), stderrBytes = Buffer.from(stderrText);
    const stdout = await record('stdout.txt', stdoutBytes), stderr = await record('stderr.txt', stderrBytes);
    await record('command.json', {schemaVersion: 'actql-python-publish-command/0.1', manifestSha256: expectedSha256,
      targetId, project, code, signal, stdout, stderr,
      commandSucceeded: code === 0 && signal === null, confirmation: 'unobserved'});
    assert(code === 0 && signal === null, `Original PyPI outcome unconfirmed; preserve ${attempt}`);
    assert.deepEqual(await readFile(path), captured.bytes, 'Publisher changed original wheel bytes');
    const original = await lstat(path); assert(original.isFile() && !original.isSymbolicLink() && (original.mode & 0o777) === 0o400);
    const sidecar = `${item.file}.publish.attestation`;
    assert.deepEqual((await readdir(payload)).sort(), [item.file, sidecar].sort(), 'Original action attestation missing or unselected payload appeared');
    const sidecarPath = join(payload, sidecar), stat = await lstat(sidecarPath);
    assert(stat.isFile() && !stat.isSymbolicLink() && stat.size > 0 && stat.size <= 4 * 1024 * 1024);
    const bytes = await readFile(sidecarPath); assert.equal(bytes.length, stat.size);
    attestation = {file: sidecar, bytes: bytes.length, sha256: digest(bytes),
      qualification: 'raw original publisher output; cryptographic identity, PyPI provenance and owner acceptance not established by this receipt'};
    await record('attestation.json', attestation);
    const after = await observe(); await record('after.json', after); valid(after);
    assert(after.observations.some(value => value.file === item.file && value.state === 'present'),
      `Original job returned but public bytes remain unconfirmed; preserve ${attempt}`);
    actionState = 'command-and-public-bytes-confirmed';
  }
  await verifyReleaseSet(directory, {expectedSha256});
  const summary = {schemaVersion: 'actql-python-publish-attempt/0.1', manifestSha256: expectedSha256,
    targetId, project, attemptId, at: new Date().toISOString(), state: actionState, attestation,
    qualification: 'one-project same-byte protocol only; not owner approval, trust/image isolation, signature verification, public install or complete release acceptance'};
  await record('summary.json', summary); return {...summary, receiptDirectory: attempt};
}

async function nativePublishSelection(directory, expectedSha256, targetId) {
  assert.match(expectedSha256, /^[a-f0-9]{64}$/u);
  const fixed = await verifyReleaseSet(directory, {expectedSha256}), draft = nativeReleaseDraftRequest(fixed, targetId);
  assert(fixed.review?.executionScope.publish.includes(targetId), 'Native publication needs its bound proposed scope/evidence');
  const cohort = fixed.manifest.cohorts.find(value => value.targetId === targetId);
  assert.equal(cohort.kind, 'native-standalone');
  const {verifyNativeStandalone} = await import('./native-standalone-release.mjs');
  const original = await verifyNativeStandalone(dirname(join(resolve(directory), cohort.path)));
  requireNativeCohortPackageVersions(JSON.parse(original.origin.manifest));
  await verifyReleaseSet(directory, {expectedSha256});
  return {fixed, draft, artifacts: fixed.manifest.artifacts.filter(value => value.targetId === targetId)};
}

export async function nativePublishPlan(directory, expectedSha256, targetId) {
  const selected = await nativePublishSelection(directory, expectedSha256, targetId);
  return {schemaVersion: 'actql-native-publish-plan/0.1', manifestSha256: expectedSha256, targetId,
    execution: 'unavailable', draft: selected.draft, artifacts: selected.artifacts,
    pending: ['Independent owner approval of this exact set and permitted same-bytes recovery',
      'Protected immutable validator, full actual install evidence, separate read/mutation trust and one exclusive executor',
      'Administration-read immutable setting and complete authenticated draft visibility; anonymous 404 is unknown',
      'Actual signing/provenance and immutable-release verification; this protocol does not verify attestations',
      'No default runner, credentials or CLI; final channel promotion/public-install acceptance is separate']};
}

// Protocol only, under the SAME existing publisher/receipt Owner. Neither the
// ports nor proposed scope/passed labels prove owner authority. The protected
// executor must hold exclusive current execution across the entire sequence.
// runGitHub settles only after its ORIGINAL request/job is terminal. A lost
// observation retains that handle externally, never another invocation here.
export async function publishNativeRelease(options) {
  const allowed = ['directory', 'expectedSha256', 'targetId', 'receiptsDirectory', 'fetchOwner', 'fetchCdn', 'runGitHub'];
  assert(options && Object.keys(options).every(key => allowed.includes(key)), 'Unexpected Native publication fields');
  const {directory, expectedSha256, targetId, receiptsDirectory, fetchOwner, fetchCdn = fetch, runGitHub} = options;
  assert.equal(typeof fetchOwner, 'function', 'No protected Native owner read port supplied');
  assert.equal(typeof runGitHub, 'function', 'No protected Native mutation runner supplied');
  const selected = await nativePublishSelection(directory, expectedSha256, targetId);
  const acceptance = selected.fixed.review.acceptance.find(value => value.targetId === targetId && value.phase === 'prepublication-install');
  assert.equal(acceptance.status, 'passed', 'Prepublication evidence is not even supplied as passed');
  const observe = () => observeNativePublicationTarget(directory, expectedSha256, targetId, {fetchOwner, fetchCdn});
  const valid = value => assert(['absent', 'draft', 'published'].includes(value.state),
    `Original Native boundary is ${value.state}: ${value.reason ?? 'unavailable'}`);
  const initial = await observe(); valid(initial);
  assert(isAbsolute(receiptsDirectory)); const root = resolve(receiptsDirectory); await privateDirectory(root);
  const releaseRoot = join(root, expectedSha256); await privateDirectory(releaseRoot);
  const targetRoot = join(releaseRoot, targetId); await privateDirectory(targetRoot);
  const prior = await readdir(targetRoot);
  assert(prior.every(name => name.startsWith('attempt-') && stageUuid(name.slice(8))), 'Unrecognized original Native attempt');
  for (const name of prior) {const status = await lstat(join(targetRoot, name)); assert(status.isDirectory() && !status.isSymbolicLink());}
  if (prior.length) assert(selected.fixed.review.executionScope.resumeIdenticalMissing.includes(targetId), 'Original scope did not permit Native same-bytes recovery');
  const attemptId = randomUUID(), attempt = join(targetRoot, `attempt-${attemptId}`);
  await mkdir(attempt, {mode: 0o700}); await syncDirectory(targetRoot);
  const record = async (name, value) => writePrivateOriginal(join(attempt, name),
    Buffer.isBuffer(value) ? value : Buffer.from(`${JSON.stringify(value, null, 2)}\n`));
  await record('preflight.json', initial);
  let operationIndex = 0;
  const execute = async (kind, request, expectedStatus, artifact = null) => {
    const index = operationIndex++;
    if (request.body) Object.freeze(request.body);
    if (request.headers) Object.freeze(request.headers);
    Object.freeze(request);
    const intent = {schemaVersion: 'actql-native-publish-intent/0.1', manifestSha256: expectedSha256,
      targetId, attemptId, kind, at: new Date().toISOString(), state: 'outcome-unknown', request, artifact};
    await record(`${index}-${kind}-intent.json`, intent);
    let response;
    try {response = await runGitHub(request, Object.freeze({manifestSha256: expectedSha256, targetId, kind}));}
    catch (failure) {
      try {await record(`${index}-${kind}-unobserved.json`, {state: 'unknown', reason: 'original-mutation-unobserved'});}
      catch (cleanup) {throw retainOriginalPublisherFailure(cleanup, failure);}
      throw retainOriginalPublisherFailure(Error(`Native ${kind} outcome unknown; preserve ${attempt}`), failure);
    }
    const terminal = response && ['code', 'signal', 'status', 'stdout', 'stderr'].every(field => Object.hasOwn(response, field));
    const stdout = terminal ? response.stdout : undefined, stderr = typeof stdout === 'string' ? response.stderr : undefined;
    const bounded = terminal && typeof stdout === 'string' && typeof stderr === 'string' &&
      Buffer.byteLength(stdout) + Buffer.byteLength(stderr) <= 8 * 1024 * 1024;
    if (!bounded) {await record(`${index}-${kind}-unobserved.json`, {state: 'unknown', reason: 'Original terminal response unavailable'});
      throw Error(`Native ${kind} outcome unknown; preserve ${attempt}`);}
    const snapshot = {code: response.code, signal: response.signal, status: response.status, stdout, stderr};
    await record(`${index}-${kind}-terminal.json`, snapshot);
    assert(snapshot.code === 0 && snapshot.signal === null && snapshot.status === expectedStatus,
      `Native ${kind} returned without confirmation; preserve ${attempt}`);
    let body;
    try {body = JSON.parse(snapshot.stdout);} catch {throw Error(`Native ${kind} original JSON unavailable; preserve ${attempt}`);}
    assert(Number.isSafeInteger(body?.id) && body.id > 0, 'Original GitHub response identity unavailable');
    return body.id;
  };
  const api = 'https://api.github.com/repos/actql/actql';
  let current = await observe(); await record('before-create.json', current); valid(current);
  if (current.state === 'absent') {
    const createdId = await execute('create', {method: 'POST', url: `${api}/releases`, body: {...selected.draft}}, 201);
    current = await observe(); await record('after-create.json', current); valid(current);
    assert.equal(current.state, 'draft'); assert.equal(current.releaseId, createdId, 'Original created Draft identity changed');
  }
  const releaseId = current.releaseId;
  for (const [index, item] of selected.artifacts.entries()) {
    current = await observe(); await record(`asset-${index}-before.json`, current); valid(current);
    assert.equal(current.releaseId, releaseId, 'Original Native release was replaced');
    const existing = current.observations.find(value => value.file === item.file);
    if (existing.state === 'present') continue;
    assert.equal(current.state, 'draft', 'Never append to an already published release');
    const captured = await readFrozenReleaseArtifact(directory, expectedSha256, targetId, item.file);
    const payload = join(attempt, `payload-${index}`); await mkdir(payload, {mode: 0o700}); await syncDirectory(attempt);
    const path = join(payload, item.file); await writePrivateOriginal(path, captured.bytes, 0o400);
    const assetId = await execute('upload', {method: 'POST',
      url: current.uploadUrl.replace('{?name,label}', `?name=${encodeURIComponent(item.file)}`),
      headers: {'content-type': item.file.endsWith('.tar.gz') ? 'application/gzip' : 'text/plain', 'content-length': String(item.bytes)},
      file: path}, 201, item);
    const status = await lstat(path);
    assert(status.isFile() && !status.isSymbolicLink() && (status.mode & 0o777) === 0o400);
    assert.deepEqual(await readFile(path), captured.bytes, 'Native uploader changed original private payload');
    assert.deepEqual(await readdir(payload), [item.file]);
    current = await observe(); await record(`asset-${index}-after.json`, current); valid(current);
    assert.equal(current.releaseId, releaseId);
    const confirmed = current.observations.find(value => value.file === item.file);
    assert.equal(confirmed.state, 'present'); assert.equal(confirmed.assetId, assetId, 'Original uploaded asset identity changed');
  }
  current = await observe(); await record('before-publish.json', current); valid(current);
  assert.equal(current.releaseId, releaseId); assert(current.observations.every(value => value.state === 'present'));
  if (current.state === 'draft') {
    const {generate_release_notes, ...body} = selected.draft;
    const publishedId = await execute('publish', {method: 'PATCH', url: `${api}/releases/${releaseId}`,
      body: {...body, draft: false, make_latest: 'false'}}, 200);
    assert.equal(publishedId, releaseId);
    current = await observe(); await record('after-publish.json', current); valid(current);
  }
  assert.equal(current.state, 'published'); assert.equal(current.releaseId, releaseId);
  await verifyReleaseSet(directory, {expectedSha256});
  const summary = {schemaVersion: 'actql-native-publish-attempt/0.1', manifestSha256: expectedSha256, targetId,
    attemptId, releaseId, operationCount: operationIndex, state: 'immutable-release-and-original-assets-confirmed',
    qualification: 'same-byte protocol/owner-port readback only; not approval, permission separation, attestation verification, public install, final channel or complete release acceptance'};
  await record('summary.json', summary); return {...summary, receiptDirectory: attempt};
}

function promotionChannelSnapshot(report) {
  const result = new Map();
  for (const item of report.observations) {
    assert(item.state !== 'unknown', 'Original selected channel value is unknown');
    const key = JSON.stringify([item.targetId, item.name, item.channel]);
    assert(!result.has(key)); result.set(key, item.state === 'absent' ? null : item.version);
  }
  return result;
}

// SAME publisher/receipt Owner, protocol only. The protected executor must
// independently validate actual public acceptance and owner approval of BOTH
// digests, then hold exclusive execution across all reads/commands/readbacks.
// A callback, receipt label or GET is not that authority or registry CAS.
// Runner settlement means its SAME original child is terminal; an unobserved
// live child remains with that executor and must never cause a second send.
// No default runner, credential, CLI command or settings operation is supplied.
export async function promoteNpmReleaseChannels(options) {
  const allowed = ['directory', 'expectedSha256', 'reviewDirectory', 'expectedReviewSha256',
    'receiptsDirectory', 'npmVersion', 'runNpm', 'fetchResponse'];
  assert(options && Object.keys(options).every(key => allowed.includes(key)), 'Unexpected promotion execution fields');
  const {directory, expectedSha256, reviewDirectory, expectedReviewSha256, receiptsDirectory,
    npmVersion, runNpm, fetchResponse = fetch} = options;
  assert.equal(typeof runNpm, 'function', 'No protected npm promotion runner supplied');
  const [major, minor] = stableTool(npmVersion);
  assert((major === 11n && minor >= 21n) || (major === 12n && minor >= 2n),
    'Select a verified npm11.21+ or npm12.2+ OIDC dist-tag tool pin');
  assert(atLeast(process.versions.node, '22.14.0'));
  const verify = () => verifyReleasePromotionReview({directory, expectedSha256, reviewDirectory, expectedReviewSha256});
  const checked = await verify(), transitions = checked.plan.transitions;
  assert.equal(checked.plan.schemaVersion,'actql-release-promotion-plan/0.1','This runner accepts only the original npm channel plan');
  const ordered = checked.fixed.manifest.artifacts.flatMap(artifact => transitions.filter(value =>
    value.targetId === artifact.targetId && value.name === artifact.name));
  assert.equal(ordered.length, transitions.length);
  const versionReply = await runNpm(Object.freeze(['--version']), Object.freeze({manifestSha256: expectedSha256,
    promotionReviewSha256: expectedReviewSha256, phase: 'tool-version'}));
  assert(versionReply?.code === 0 && versionReply.signal === null && versionReply.stdout === `${npmVersion}\n` &&
    versionReply.stderr === '', 'Promotion tool differs from the explicit protected pin');
  const bytes = async () => {
    const report = await observeReleaseSet(directory, expectedSha256, {fetchResponse});
    assert(report.observations.every(value => value.state === 'present'), 'Complete original public bytes are unavailable or different');
    return report;
  };
  const channels = () => observeReleaseChannels(directory, expectedSha256, {fetchResponse});
  const initialBytes = await bytes(), initialChannels = await channels(), current = promotionChannelSnapshot(initialChannels);
  for (const move of ordered) {
    const value = current.get(JSON.stringify([move.targetId, move.name, move.channel]));
    assert(value === move.expectedVersion || value === move.toVersion, 'Channel changed outside the original approved transition');
  }
  assert(isAbsolute(receiptsDirectory));
  const root = join(await realpath(dirname(receiptsDirectory)), basename(receiptsDirectory));
  for (const original of [await realpath(directory), await realpath(reviewDirectory)])
    assert(root !== original && !root.startsWith(`${original}${sep}`), 'Promotion receipts must be outside the frozen inputs');
  await privateDirectory(root);
  const releaseRoot = join(root, expectedSha256); await privateDirectory(releaseRoot);
  const reviewRoot = join(releaseRoot, expectedReviewSha256); await privateDirectory(reviewRoot);
  for (const name of await readdir(reviewRoot)) {
    assert(name.startsWith('attempt-') && stageUuid(name.slice(8)), 'Unrecognized original promotion attempt');
    const st = await lstat(join(reviewRoot, name)); assert(st.isDirectory() && !st.isSymbolicLink());
  }
  const attemptId = randomUUID(), attempt = join(reviewRoot, `attempt-${attemptId}`);
  await mkdir(attempt, {mode: 0o700}); await syncDirectory(reviewRoot);
  const record = (name, value) => writePrivateOriginal(join(attempt, name), Buffer.from(`${JSON.stringify(value, null, 2)}\n`));
  await record('public-preflight.json', initialBytes); await record('channels-preflight.json', initialChannels);
  const fence = async label => {
    await verify(); const publicBytes = await bytes(), channelReport = await channels();
    await record(`${label}-public.json`, publicBytes); await record(`${label}-channels.json`, channelReport);
    assert.deepEqual(promotionChannelSnapshot(channelReport), current, 'Selected channel changed across the original execution fence');
    await verify();
  };
  let operationCount = 0;
  const results = [];
  for (const [index, move] of ordered.entries()) {
    await fence(`${index}-before`);
    const key = JSON.stringify([move.targetId, move.name, move.channel]);
    if (current.get(key) === move.toVersion) {
      results.push({...move, outcome: 'already-identical-observed'}); continue;
    }
    assert.equal(current.get(key), move.expectedVersion);
    const args = Object.freeze(['dist-tag', 'add', `${move.name}@${move.toVersion}`, move.channel,
      '--registry', 'https://registry.npmjs.org/', '--ignore-scripts', '--workspaces=false']);
    await record(`${index}-intent.json`, {schemaVersion: 'actql-npm-promotion-intent/0.1', manifestSha256: expectedSha256,
      promotionReviewSha256: expectedReviewSha256, attemptId, at: new Date().toISOString(), move, args, state: 'outcome-unknown'});
    operationCount++;
    try {
      const response = await runNpm(args, Object.freeze({manifestSha256: expectedSha256,
        promotionReviewSha256: expectedReviewSha256, phase: 'dist-tag', transition: Object.freeze({...move})}));
      assert(response && typeof response.stdout === 'string' && typeof response.stderr === 'string' &&
        Buffer.byteLength(response.stdout) + Buffer.byteLength(response.stderr) <= 1024 * 1024,
      'Original bounded npm terminal response unavailable');
      await record(`${index}-terminal.json`, {code: response.code, signal: response.signal,
        stdout: response.stdout, stderr: response.stderr});
      assert(response.code === 0 && response.signal === null, 'Original npm promotion command did not confirm completion');
      // Command success is not a current channel or public-byte proof.
      current.set(key, move.toVersion); await fence(`${index}-after`);
      await record(`${index}-confirmed.json`, {move, state: 'exact-original-current-readback'});
      results.push({...move, outcome: 'exact-original-current-readback'});
    } catch (failure) {
      try {await record(`${index}-unknown.json`, {state: 'unknown', reason: 'original-mutation-or-readback-unconfirmed',
        originalIntent: `${index}-intent.json`});}
      catch (cleanup) {
        Object.assign(cleanup, {originalAttempt: attempt});
        throw retainOriginalPublisherFailure(cleanup, failure, 'originalPromotionError');
      }
      throw retainOriginalPublisherFailure(Error(`Original channel outcome unknown; preserve ${attempt} and use explicit same-digest owner reobservation`), failure, 'originalPromotionError');
    }
  }
  await fence('final');
  const summary = {schemaVersion: 'actql-npm-promotion-attempt/0.1', manifestSha256: expectedSha256,
    promotionReviewSha256: expectedReviewSha256, attemptId, operationCount, results, state: 'selected-current-channels-observed',
    qualification: 'same-original protocol/readback only; not owner approval, trusted public acceptance, permission isolation, exclusive lease/CAS or complete release acceptance'};
  await record('summary.json', summary); return {...summary, receiptDirectory: attempt};
}

export async function publishPackageRelease({directory, executePublish, fetchMetadata = fetch, verify = verifyPackageRelease}) {
  const manifest = await verify(directory);
  // Inspect the whole cohort first, so an occupied conflicting version does
  // not cause an avoidable partial publication of earlier dependencies.
  const plan = await publicationPlan(manifest, fetchMetadata);
  const receipts = join(directory, 'publication-receipts');
  await mkdir(receipts, {recursive: true});
  const manifestSha256 = createHash('sha256').update(await readFile(join(directory, 'release.json'))).digest('hex');
  for (const [index, action] of plan.entries()) {
    if (action.state === 'published-identical') continue;
    // Recheck immediately before publishing. Never overwrite, bump or silently
    // pick another tag when a version appeared between planning and execution.
    const item = manifest.packages[index];
    if (await publishedVersion(item, manifest.cohort.registry, fetchMetadata) === 'published-identical') continue;
    await executePublish({file: join(directory, item.file), registry: manifest.cohort.registry,
      access: manifest.cohort.access, tag: manifest.cohort.tag});
    // Command success is recorded separately from registry confirmation. If
    // confirmation fails, the next invocation authenticates existing bytes
    // first; it does not assume that the previous publication never happened.
    const receipt = {version: 'actql-package-publication/0.1', at: new Date().toISOString(),
      manifestSha256, sourceSha: manifest.sourceSha, name: item.name, packageVersion: item.version,
      integrity: item.integrity, registry: manifest.cohort.registry, commandSucceeded: true};
    const filename = `${index}-${Date.now()}-${crypto.randomUUID()}.json`;
    await writeFile(join(receipts, filename), `${JSON.stringify(receipt, null, 2)}\n`, {flag: 'wx'});
    assert.equal(await publishedVersion(item, manifest.cohort.registry, fetchMetadata), 'published-identical',
      'Publication not yet confirmed; preserve receipt and rerun inspection');
  }
  return publicationPlan(manifest, fetchMetadata);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [permission, input] = process.argv.slice(2);
  assert(permission === '--publish' && input, 'usage after release GO: publish-package-release.mjs --publish <RC-directory>');
  refuseUnconfiguredPublication();
  const directory = resolve(input);
  const manifest = await verifyPackageRelease(directory);
  const identity = execFileSync('npm', ['whoami', '--registry', manifest.cohort.registry,
    '--fetch-timeout=15000', '--fetch-retries=0'], {encoding: 'utf8', timeout: 20_000}).trim();
  assert(identity, 'Authenticated npm identity required');
  console.log(`Authenticated npm operator: ${identity}`);
  console.log(JSON.stringify(await publishPackageRelease({directory, executePublish({file, registry, access, tag}) {
    execFileSync('npm', ['publish', file, '--ignore-scripts', '--registry', registry, '--access', access, '--tag', tag],
      {stdio: 'inherit', timeout: 180_000});
  }}), null, 2));
}
