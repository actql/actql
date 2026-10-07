// A local physical diagnostic, never an authenticated Actions receipt. Linux
// preparation uses an explicit immutable builder; execution uses the same
// scratch image and scientific consumer as CI, with a different owner domain.
import assert from 'node:assert/strict';
import {spawnSync, execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync, lstatSync, statSync, realpathSync} from 'node:fs';
import {join, resolve, isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gitTree, hash} from './inputs.mjs';
import {checkIsolatedInputs} from './isolated-runtime.mjs';
import {prepareLocalIsolatedMutation, executeLocalIsolatedMutation} from './isolated-execution.mjs';
import {validatePipelinePristineOriginal} from './isolated-pipeline-results.mjs';
import {stagePipelinePristineSource, pipelinePristineSourcePaths, stagePipelineFixedJsSource, pipelineFixedJsSourcePaths} from './isolation.mjs';
import {snapshot} from '../relation-pipeline/inventory.mjs';
import {validatePristineReport, readPristineFiles, pristineScientificObservation} from '../relation-pipeline/pristine-replay.mjs';
import {validateFixedJsReport, readFixedJsFiles, fixedJsScientificObservation, fixedJsExecutions} from '../relation-pipeline/fixed-js-replay.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';
import {setTimeout as delay} from 'node:timers/promises';

const root = fileURLToPath(new URL('../../', import.meta.url));
const json = (path, value) => writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, {flag: 'wx'});
const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
const call = (engine, args, timeout = 120000) => {
  const result = spawnSync(engine, args, {encoding: 'utf8', timeout, maxBuffer: 16 * 1024 * 1024});
  if (result.error || result.status !== 0) process.stderr.write((result.stderr ?? '').slice(-4000));
  assert(!result.error && result.status === 0, result.error?.code === 'ETIMEDOUT' ? 'Local preparation command timed out' : 'Local preparation command failed');
  return result.stdout;
};

// The pipeline preparer also runs the separate normal phase. Its budget must
// cover preparation plus the bounded replay, rather than only image staging.
export function localAcceptanceLimits(profile = 'session') {
  assert(['session', 'pipeline-pristine', 'pipeline-fixed-js'].includes(profile), 'Unregistered local profile');
  return Object.freeze(profile === 'session'
    ? {preparationMilliseconds: 180000, timeoutSeconds: 1200}
    : profile === 'pipeline-pristine' ? {preparationMilliseconds: 900000, normalReplayMilliseconds: 480000, timeoutSeconds: 1800}
      : {preparationMilliseconds: 1200000, normalReplayMilliseconds: 900000, timeoutSeconds: 2400});
}

// The Linux preparer receives Git object identities, not an unverified working
// copy. Only declared regular blobs can be read, with their exact tracked mode.
export function checkoutTree(directory, descriptor) {
  assert(/^[a-f0-9]{40}$/u.test(descriptor.revision));
  const entries = new Map(descriptor.entries);
  assert.equal(entries.size, descriptor.entries.length, 'Duplicate Git entry');
  return {revision: descriptor.revision, entries, read(path) {
    const entry = entries.get(path);
    assert(entry?.kind === 'blob' && ['100644', '100755'].includes(entry.mode) &&
      /^[A-Za-z0-9_.\/+\-]+$/u.test(path) && !path.split('/').some(part => ['', '.', '..'].includes(part)), 'Undeclared/nonregular Git input');
    const stat = lstatSync(join(directory, path));
    assert(stat.isFile() && Number.parseInt(entry.mode.slice(-3), 8) === (stat.mode & 0o777), 'Changed Git file kind/mode');
    const bytes = readFileSync(join(directory, path));
    const object = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
    assert.equal(object, entry.object, 'Checkout differs from the declared Git blob');
    return bytes;
  }};
}

// Preserve the named launcher: multicall engines (including OrbStack) select
// their Docker behavior from argv[0]. Resolve only to check its regular target.
export function localEngine(path) {
  assert(typeof path === 'string' && isAbsolute(path) && statSync(path).isFile(), 'Use an explicit regular Docker launcher');
  return resolve(path);
}

export function checkBuilder(image, imageId) {
  assert(/^sha256:[a-f0-9]{64}$/u.test(imageId));
  assert.equal(image.Id, imageId); assert.equal(image.Os, 'linux'); assert.equal(image.Architecture, 'amd64');
  for (const field of ['Volumes', 'OnBuild', 'Healthcheck'])
    assert(image.Config[field] === null || image.Config[field] === undefined, 'Unexpected builder side effects');
  return true;
}

function prepareLinux(descriptorFile) {
  const descriptor = JSON.parse(readFileSync(descriptorFile));
  const tree = checkoutTree('/candidate', descriptor);
  const profile = descriptor.profile ?? 'session';
  assert(['session', 'pipeline-pristine', 'pipeline-fixed-js'].includes(profile));
  const pin = JSON.parse(tree.read('toolchain.json'));
  const versions = [...new Set([...tree.read('.github/workflows/ci.yml').toString().matchAll(/node-version:\s*(\d+\.\d+\.\d+)/gu)].map(match => match[1]))];
  assert.equal(versions.length, 1, 'Ambiguous pinned Node version');
  assert.equal(process.version, `v${versions[0]}`, 'Builder Node differs from the candidate workflow pin');
  assert.equal(call('/toolchain/bin/moonc', ['-v']).trim(), pin.moonc);
  assert.equal(call('/toolchain/bin/moon', ['version']).trim().split(/\r?\n/u)[0], `moon ${pin.moon}`);
  const prepared = prepareLocalIsolatedMutation({root: '/candidate', tree, owner: descriptor.owner, directory: '/out', profile});
  json('/out/prepared.json', prepared);
  if (profile !== 'session') {
    // Both phases build in private Linux tmpfs. The preparation output mount
    // receives only evidence, not the normal source/build tree.
    const normalPreparationStart = performance.now();
    mkdirSync('/tmp/pipeline-normal');
    (profile === 'pipeline-pristine' ? stagePipelinePristineSource : stagePipelineFixedJsSource)({tree, destination: '/tmp/pipeline-normal'});
    const directory = '/tmp/pipeline-normal/source', start = performance.now();
    const sourcePreparationMilliseconds = Math.round(start - normalPreparationStart);
    json('/out/preparation-phases.json', {imagePreparationMilliseconds: prepared.preparationMilliseconds,
      normalSourcePreparationMilliseconds: sourcePreparationMilliseconds,
      normalStartedAt: new Date().toISOString(), normalCompleted: false});
    const entry = profile === 'pipeline-pristine' ? ['proofs/relation-pipeline/pristine-replay.mjs']
      : ['proofs/relation-pipeline/fixed-js-replay.mjs', descriptor.revision];
    const result = spawnSync(process.execPath, entry, {
      cwd: directory, env: process.env, encoding: 'utf8', timeout: localAcceptanceLimits(profile).normalReplayMilliseconds, maxBuffer: 32 * 1024 * 1024,
    });
    // Save actual process facts before admission, including a timed-out partial
    // campaign. These diagnostics cannot stand in for a complete phase report.
    writeFileSync('/out/normal-output.log', result.stdout ?? '', {flag: 'wx'});
    writeFileSync('/out/normal-error.log', result.stderr ?? '', {flag: 'wx'});
    const processFacts = {timeoutMilliseconds: localAcceptanceLimits(profile).normalReplayMilliseconds,
      elapsedMilliseconds: Math.round(performance.now() - start), status: result.status,
      signal: result.signal, errorCode: result.error?.code ?? null,
      complete: !result.error && result.status === 0, reuseAuthorized: false};
    json('/out/normal-process.json', processFacts);
    if (!processFacts.complete) {
      process.stderr.write((result.stderr ?? '').slice(-4000));
      process.stderr.write(`ACTQL_NORMAL_PIPELINE_FAILURE ${JSON.stringify(processFacts)}\n`);
    }
    assert(processFacts.complete, 'Normal pinned pipeline replay failed');
    const prefix = profile === 'pipeline-pristine' ? 'ACTQL_PIPELINE_PRISTINE ' : 'ACTQL_PIPELINE_FIXED_JS ';
    const summaries = result.stdout.split('\n').filter(line => line.startsWith(prefix)); assert.equal(summaries.length, 1);
    const summary = JSON.parse(summaries[0].slice(prefix.length));
    assert(summary.path.startsWith(`${directory}/.artifacts/${profile}/replay-`));
    const report = JSON.parse(readFileSync(summary.path)), files = profile === 'pipeline-pristine' ? readPristineFiles(directory, report) : readFixedJsFiles(directory, report);
    if (profile === 'pipeline-pristine') validatePristineReport(report, snapshot(directory), files);
    else validateFixedJsReport({report, source: snapshot(directory), files, revision: descriptor.revision,
      readSource: path => readFileSync(join(directory, path))});
    json('/out/normal.json', {report, files, sourcePreparationMilliseconds, milliseconds: Math.round(performance.now() - start)});
  }

}

export function checkOwnedPreparation(container, {cid, imageId, owner}) {
  assert(/^[a-f0-9]{64}$/u.test(cid) && /^local-[a-f0-9]{32}$/u.test(owner));
  assert.equal(container.Id, cid); assert.equal(container.Image, imageId);
  assert.equal(container.Config?.Labels?.['org.actql.local.owner'], owner);
  return true;
}

// --rm may already be removing a container when a timed-out client returns.
// Only tolerate that precise owned-container transition; absence must then be
// observed. Unknown transport/daemon errors never prove cleanup complete.
export async function closeOwnedPreparation({engine, cid, imageId, owner}, run = spawnSync) {
  assert(/^[a-f0-9]{64}$/u.test(cid) && /^sha256:[a-f0-9]{64}$/u.test(imageId) &&
    /^local-[a-f0-9]{32}$/u.test(owner), 'Invalid owned preparer identity');
  const deadline = performance.now() + 30000;
  while (performance.now() < deadline) {
    const timeout = () => Math.max(1, Math.min(5000, Math.floor(deadline - performance.now())));
    const inspected = run(engine, ['container', 'inspect', cid], {encoding: 'utf8', timeout: timeout()});
    if (!inspected.error && inspected.status === 1 && /No such (?:object|container)/u.test(inspected.stderr)) return;
    assert(!inspected.error && inspected.status === 0, 'Unconfirmed preparer cleanup');
    const containers = JSON.parse(inspected.stdout); assert.equal(containers.length, 1);
    checkOwnedPreparation(containers[0], {cid, imageId, owner});
    const removed = run(engine, ['container', 'rm', '--force', cid], {encoding: 'utf8', timeout: timeout()});
    assert(!removed.error && (removed.status === 0 || (removed.status === 1 &&
      new RegExp(`^Error response from daemon: removal of container ${cid} is already in progress\\s*$`, 'u').test(removed.stderr))),
    'Unconfirmed owned preparer removal');
    await delay(250);
  }
  throw new Error('Owned preparer cleanup timed out; retain CID custody');
}

// Corrupt actual captured values, never assume the first minimum emits rows.
// Refuse no-op tamper fixtures as well as a validator accepting changed facts.
export function verifyPristineTamperRefusals(payload) {
  const rejected = [];
  for (const [name, alter] of [
    ['missing-receipt', p => p.report.receipts.pop()],
    ['wrong-target', p => p.report.receipts[0].receipt.target = 'native'],
    ['changed-source', p => p.report.source.digest = '0'.repeat(64)],
    ['changed-log', p => p.files[p.report.receipts[0].receipt.logPath] += 'changed'],
    ['changed-input', p => p.files[p.report.receipts[0].receipt.inputPath] = '[]'],
    ['changed-value', p => {
      const candidates = p.report.observations.flatMap(({observed}) => observed.wireRows.flatMap(row =>
        Object.keys(row).filter(key => typeof row[key] === 'number' && Number.isFinite(row[key]))
          .map(key => ({row, key}))));
      assert(candidates.length > 0, 'No numeric observed value for the registered pristine tamper fixture');
      const {row, key} = candidates[0]; row[key] = row[key] === 0 ? 1 : 0;
    }],
    ['reuse-promotion', p => p.report.reuseAuthorized = true],
  ]) {
    const changed = structuredClone(payload); alter(changed);
    assert.notDeepEqual(changed, payload, `Tamper fixture made no change: ${name}`);
    assert.throws(() => validatePipelinePristineOriginal(changed.report, payload.report.source, changed.files), name);
    rejected.push(name);
  }
  return rejected;
}

// Remove an actually captured defect while keeping the altered copy's receipt,
// input and compiled-boundary digests consistent. The independent anchor still
// must refuse it; a successful log or killed label cannot replace detection.
export function eraseFixedJsDetection(payload) {
  const result = payload.report.results[0], execution = result.executions[0], run = execution.receipt;
  const observed = {...structuredClone(result.healthy.js), id: run.cases[0].id};
  run.cases[0].observation = observed; result.replay.js = observed;
  const {rows: _derivedRows, tableRows, faults: _faults, ...raw} = observed;
  const log = payload.files[run.logPath].split('\n')
    .filter(line => !line.startsWith('ACTQL_PIPELINE_FAULT:'))
    .map(line => line.startsWith('ACTQL_PIPELINE:') ? `ACTQL_PIPELINE:${JSON.stringify({...raw, rows: tableRows})}` : line).join('\n');
  payload.files[run.logPath] = log; run.logDigest = hash(log);
  execution.digest = hash(JSON.stringify(run));
  payload.files[execution.path] = `${JSON.stringify(run, null, 2)}\n`;
}

export function verifyFixedJsTamperRefusals(payload, context) {
  const rejected = [];
  for (const [name, alter] of [
    ['missing-execution', p => p.report.results[0].executions.pop()],
    ['missing-restoration', p => delete p.report.results[0].postRestore],
    ['wrong-target', p => p.report.action.target = 'native'],
    ['changed-phase', p => p.report.action.phases[0] = 'pristine'],
    ['changed-owner', p => p.report.workspaces.mutable.id = 'another-owner'],
    ['old-restoration-owner', p => p.report.restorationOwner.id = p.report.workspaces.mutable.id],
    ['changed-source', p => p.report.source.digest = '0'.repeat(64)],
    ['changed-log', p => p.files[p.report.results[0].executions[0].receipt.logPath] += 'changed'],
    ['changed-input', p => p.files[p.report.results[0].executions[0].receipt.inputPath] = '[]'],
    ['changed-program', p => p.report.results[0].executions[0].receipt.cases[0].program.source = '[]'],
    ['replaced-anchor', p => p.report.results[0].anchor.usedPort = 99],
    ['erased-detection', eraseFixedJsDetection],
    ['reuse-promotion', p => p.report.reuseAuthorized = true],
  ]) {
    const changed = structuredClone(payload); alter(changed);
    assert.notDeepEqual(changed, payload, `Tamper fixture made no change: ${name}`);
    assert.throws(() => validateFixedJsReport({report: changed.report, files: changed.files, ...context}), name);
    rejected.push(name);
  }
  return rejected;
}

async function worker(options) {
  const workerStarted = performance.now();
  assert.equal(git(['rev-parse', 'HEAD']), options.revision, 'Candidate HEAD changed');
  assert.equal(git(['status', '--porcelain', '--untracked-files=no']), '', 'Use a clean tracked candidate');
  const tree = gitTree(root, options.revision);
  const [image] = JSON.parse(call(options.engine, ['image', 'inspect', options.builderImage]));
  checkBuilder(image, options.builderImage);
  const owner = `local-${randomUUID().replaceAll('-', '')}`;
  const directory = mkdtempSync(join(root, '_build', 'local-isolated-'));
  const profile = options.profile ?? 'session';
  assert(['session', 'pipeline-pristine', 'pipeline-fixed-js'].includes(profile));
  const descriptor = {revision: options.revision, owner, profile, entries: [...tree.entries]};
  json(join(directory, 'checkout.json'), descriptor);
  json(join(directory, 'custody.json'), {authority: 'local-physical-acceptance', owner, builderImage: options.builderImage, directory});
  // These mounts exist only during preparation. The actual mutation container
  // has no mounts, no network, no inherited credentials and a read-only root.
  let preparationError;
  try { call(options.engine, ['run', '--rm', '--pull=never', '--platform=linux/amd64', '--network=none',
    '--cap-drop=ALL', '--security-opt=no-new-privileges', '--read-only', '--tmpfs', '/tmp:rw,nosuid,nodev',
    '--label', `org.actql.local.owner=${owner}`, '--cidfile', join(directory, 'preparer.id'),
    '--mount', `type=bind,src=${realpathSync(root)},dst=/candidate,readonly`,
    '--mount', `type=bind,src=${options.moonHome},dst=/toolchain,readonly`,
    '--mount', `type=bind,src=${directory},dst=/out`,
    '--env', 'MOON_HOME=/toolchain', '--env', 'ImageVersion=local-linux-amd64',
    '--entrypoint', 'node', options.builderImage,
    '/candidate/proofs/ci-evidence/local-isolated-acceptance.mjs', 'prepare-linux', '/out/checkout.json'], localAcceptanceLimits(profile).preparationMilliseconds);
  } catch (error) { preparationError = error; }
  // A timed-out client does not imply the daemon stopped its container. Keep
  // the CID custody and close only a positively authenticated local preparer.
  try {
    let cid;
    try { cid = readFileSync(join(directory, 'preparer.id'), 'utf8').trim(); } catch (error) { assert.equal(error.code, 'ENOENT'); }
    if (cid) {
await closeOwnedPreparation({engine: options.engine, cid, imageId: options.builderImage, owner});
    }
  } catch (error) {
    if (preparationError) console.error('Local preparer cleanup also failed; retain CID custody');
    else preparationError = error;
  }
  if (preparationError) throw preparationError;
  const prepared = JSON.parse(readFileSync(join(directory, 'prepared.json')));
  assert.equal(prepared.owner, owner);
  assert(/^\/out\/isolated-build-[A-Za-z0-9]+$/u.test(prepared.context), 'Unexpected owned context');
  prepared.context = join(directory, prepared.context.slice('/out/'.length));
  // The Linux preparer has its own Git descriptor, so prime this host tree
  // through the existing bounded, object-checked cat-file batches.
  if (profile !== 'session') tree.prefetch(profile === 'pipeline-pristine' ? pipelinePristineSourcePaths(tree) : pipelineFixedJsSourcePaths(tree));
  checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree, local: true, profile});
  const answer = await executeLocalIsolatedMutation({root, tree, prepared, engine: options.engine, profile});
  if (profile !== 'session') {
    // Preserve validated image originals before optional cross-phase and
    // refusal diagnostics. A later diagnostic failure cannot discard them.
    json(join(directory, 'isolated-result.json'), {authority: 'local-physical-acceptance',
      revision: options.revision, prepared, answer, comparison: 'not-yet-verified', reuseAuthorized: false});
  }
  let comparison = null;
  if (profile !== 'session') {
    const normal = JSON.parse(readFileSync(join(directory, 'normal.json')));
    const context = {source: answer.payload.report.source, revision: options.revision, readSource: path => tree.read(path)};
    if (profile === 'pipeline-pristine') validatePipelinePristineOriginal(normal.report, context.source, normal.files);
    else validateFixedJsReport({report: normal.report, files: normal.files, ...context});
    const observe = profile === 'pipeline-pristine' ? pristineScientificObservation : fixedJsScientificObservation;
    const scientific = observe(answer.payload.report);
    assert.deepEqual(scientific, observe(normal.report), 'Normal/image scientific observations differ');
    // Reconsume actual captured evidence with independently altered grounds.
    // A green summary cannot conceal missing executions, changed raw logs,
    // wrong target, changed identity or a changed independent expectation.
    const rejected = profile === 'pipeline-pristine' ? verifyPristineTamperRefusals(answer.payload) : verifyFixedJsTamperRefusals(answer.payload, context);
    comparison = {normalMilliseconds: normal.milliseconds, normalSourcePreparationMilliseconds: normal.sourcePreparationMilliseconds,
      localElapsedMilliseconds: Math.round(performance.now() - workerStarted), isolatedCosts: answer.costs,
      scientificDigest: hash(JSON.stringify(scientific)), units: scientific.length,
      matched: true, rejected, scope: profile === 'pipeline-pristine'
        ? 'two local fresh pristine JS phases; not mutation detection, Actions qualification or net CI savings'
        : 'two local fresh fixed JS campaigns; not a complete part, Actions qualification or net CI savings'};
  }
  assert.equal(git(['rev-parse', 'HEAD']), options.revision);
  assert.equal(git(['status', '--porcelain', '--untracked-files=no']), '');
  json(join(directory, 'acceptance.json'), {authority: 'local-physical-acceptance', reuseAuthorized: false,
    revision: options.revision, profile, builderImage: options.builderImage,
    manifestDigest: hash(JSON.stringify(prepared.manifest)), prepared, answer, comparison});
  console.log(JSON.stringify({directory, revision: options.revision, profile, units: profile === 'session' ? answer.payload.report.results.length : profile === 'pipeline-pristine'
    ? answer.payload.report.units : fixedJsExecutions(answer.payload.report).length,
    restored: answer.payload.restored ?? null, sourcePreserved: answer.payload.sourcePreserved ?? null, imageId: answer.imageId, comparison, reuseAuthorized: false}));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, ...args] = process.argv.slice(2);
  if (mode === 'prepare-linux') prepareLinux(args[0]);
  else if (mode === 'worker') await worker(JSON.parse(args[0]));
  else {
    assert.equal(mode, 'run', 'Use run --engine PATH --builder-image sha256:ID --moon-home PATH');
    assert([6, 8].includes(args.length)); const options = {};
    for (let i = 0; i < args.length; i += 2) {
      assert(['--engine', '--builder-image', '--moon-home', '--profile'].includes(args[i]) && !options[args[i]], 'Invalid/duplicate option');
      options[args[i]] = args[i + 1];
    }
    const profile = options['--profile'] ?? 'session';
    assert(['session', 'pipeline-pristine', 'pipeline-fixed-js'].includes(profile), 'Unregistered local profile');
    const engine = localEngine(options['--engine']), moonHome = realpathSync(options['--moon-home']);
    assert(lstatSync(moonHome).isDirectory());
    mkdirSync(join(root, '_build'), {recursive: true});
    process.exitCode = await runLocalCheck({root, heavy: true, timeoutSeconds: localAcceptanceLimits(profile).timeoutSeconds, graceSeconds: 10,
      steps: [{name: `local isolated ${profile} physical acceptance`, command: process.execPath,
        args: [fileURLToPath(import.meta.url), 'worker', JSON.stringify({engine, moonHome, profile,
          builderImage: options['--builder-image'], revision: git(['rev-parse', 'HEAD'])})]}]});
  }
}
