// Reusable protocol for a separately protected owner-approved executor.
// Direct CLI publication stays disabled; bytes never establish authority.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {lstat, mkdir, mkdtemp, open, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {inventory, publicationPlan, publishedVersion, unpack, verifyPackageRelease} from './package-release.mjs';
import {refuseUnconfiguredPublication} from './release-authority.mjs';
import {readFrozenReleaseArtifact, verifyReleaseSet} from './release-set.mjs';
import {observeNpmStageTarget} from './release-registry.mjs';

const digest = bytes => createHash('sha256').update(bytes).digest('hex');
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
    assert.equal(metadata.name, item.name); assert.equal(metadata.version, item.version); assert.equal(metadata.private, false);
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
    catch {await record(`${index}-unknown.json`, {state: 'unknown', reason: 'runner-threw', originalIntent: `${index}-intent.json`}); throw Error(`Original stage outcome unknown; preserve ${attempt} and reobserve with the original owner reader`);}
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
