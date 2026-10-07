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
import {stagePipelinePristineSource} from './isolation.mjs';
import {snapshot} from '../relation-pipeline/inventory.mjs';
import {validatePristineReport, readPristineFiles, pristineScientificObservation} from '../relation-pipeline/pristine-replay.mjs';
import {runLocalCheck} from '../../scripts/local-checks-guard.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const json = (path, value) => writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`, {flag: 'wx'});
const git = args => execFileSync('git', args, {cwd: root, encoding: 'utf8'}).trim();
const call = (engine, args, timeout = 120000) => {
  const result = spawnSync(engine, args, {encoding: 'utf8', timeout, maxBuffer: 16 * 1024 * 1024});
  if (result.error || result.status !== 0) process.stderr.write((result.stderr ?? '').slice(-4000));
  assert(!result.error && result.status === 0, 'Local preparation command failed');
  return result.stdout;
};

// The Linux preparer receives Git object identities, not an unverified working
// copy. Only declared regular blobs can be read, with their exact tracked mode.
export function checkoutTree(directory, descriptor) {
  assert(/^[a-f0-9]{40}$/u.test(descriptor.revision));
  const entries = new Map(descriptor.entries);
  assert.equal(entries.size, descriptor.entries.length, 'Duplicate Git entry');
  return {entries, read(path) {
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
  assert(['session', 'pipeline-pristine'].includes(profile));
  const pin = JSON.parse(tree.read('toolchain.json'));
  const versions = [...new Set([...tree.read('.github/workflows/ci.yml').toString().matchAll(/node-version:\s*(\d+\.\d+\.\d+)/gu)].map(match => match[1]))];
  assert.equal(versions.length, 1, 'Ambiguous pinned Node version');
  assert.equal(process.version, `v${versions[0]}`, 'Builder Node differs from the candidate workflow pin');
  assert.equal(call('/toolchain/bin/moonc', ['-v']).trim(), pin.moonc);
  assert.equal(call('/toolchain/bin/moon', ['version']).trim().split(/\r?\n/u)[0], `moon ${pin.moon}`);
  const prepared = prepareLocalIsolatedMutation({root: '/candidate', tree, owner: descriptor.owner, directory: '/out', profile});
  json('/out/prepared.json', prepared);
  if (profile === 'pipeline-pristine') {
    // Both phases build in private Linux tmpfs. The preparation output mount
    // receives only evidence, not the normal source/build tree.
    mkdirSync('/tmp/pipeline-normal');
    stagePipelinePristineSource({tree, destination: '/tmp/pipeline-normal'});
    const directory = '/tmp/pipeline-normal/source', start = performance.now();
    const result = spawnSync(process.execPath, ['proofs/relation-pipeline/pristine-replay.mjs'], {
      cwd: directory, env: process.env, encoding: 'utf8', timeout: 480000, maxBuffer: 32 * 1024 * 1024,
    });
    if (result.error || result.status !== 0) process.stderr.write((result.stderr ?? '').slice(-4000));
    assert(!result.error && result.status === 0, 'Normal pinned pipeline replay failed');
    const prefix = 'ACTQL_PIPELINE_PRISTINE ';
    const summaries = result.stdout.split('\n').filter(line => line.startsWith(prefix)); assert.equal(summaries.length, 1);
    const summary = JSON.parse(summaries[0].slice(prefix.length));
    assert(summary.path.startsWith(`${directory}/.artifacts/pipeline-pristine/replay-`));
    const report = JSON.parse(readFileSync(summary.path)), files = readPristineFiles(directory, report);
    validatePristineReport(report, snapshot(directory), files);
    json('/out/normal.json', {report, files, milliseconds: Math.round(performance.now() - start)});
  }

}

export function checkOwnedPreparation(container, {cid, imageId, owner}) {
  assert(/^[a-f0-9]{64}$/u.test(cid) && /^local-[a-f0-9]{32}$/u.test(owner));
  assert.equal(container.Id, cid); assert.equal(container.Image, imageId);
  assert.equal(container.Config?.Labels?.['org.actql.local.owner'], owner);
  return true;
}

function worker(options) {
  assert.equal(git(['rev-parse', 'HEAD']), options.revision, 'Candidate HEAD changed');
  assert.equal(git(['status', '--porcelain', '--untracked-files=no']), '', 'Use a clean tracked candidate');
  const tree = gitTree(root, options.revision);
  const [image] = JSON.parse(call(options.engine, ['image', 'inspect', options.builderImage]));
  checkBuilder(image, options.builderImage);
  const owner = `local-${randomUUID().replaceAll('-', '')}`;
  const directory = mkdtempSync(join(root, '_build', 'local-isolated-'));
  const profile = options.profile ?? 'session';
  assert(['session', 'pipeline-pristine'].includes(profile));
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
    '/candidate/proofs/ci-evidence/local-isolated-acceptance.mjs', 'prepare-linux', '/out/checkout.json'], profile === 'pipeline-pristine' ? 600000 : 180000);
  } catch (error) { preparationError = error; }
  // A timed-out client does not imply the daemon stopped its container. Keep
  // the CID custody and close only a positively authenticated local preparer.
  try {
    let cid;
    try { cid = readFileSync(join(directory, 'preparer.id'), 'utf8').trim(); } catch (error) { assert.equal(error.code, 'ENOENT'); }
    if (cid) {
      const inspected = spawnSync(options.engine, ['container', 'inspect', cid], {encoding: 'utf8', timeout: 30000});
      if (inspected.status === 0) {
        const [container] = JSON.parse(inspected.stdout);
        checkOwnedPreparation(container, {cid, imageId: options.builderImage, owner});
        call(options.engine, ['container', 'rm', '--force', cid]);
      } else assert(!inspected.error && inspected.status === 1 && /No such (?:object|container)/u.test(inspected.stderr), 'Unconfirmed preparer cleanup');
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
  checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree, local: true, profile});
  const answer = executeLocalIsolatedMutation({root, tree, prepared, engine: options.engine, profile});
  let comparison = null;
  if (profile === 'pipeline-pristine') {
    const normal = JSON.parse(readFileSync(join(directory, 'normal.json')));
    validatePristineReport(normal.report, answer.payload.report.source, normal.files);
    const scientific = pristineScientificObservation(answer.payload.report);
    assert.deepEqual(scientific, pristineScientificObservation(normal.report), 'Normal/image scientific observations differ');
    // Reconsume actual captured evidence with independently altered grounds.
    // A green summary cannot conceal missing executions, changed raw logs,
    // wrong target, changed identity or a changed independent expectation.
    const rejected = [];
    for (const [name, alter] of [
      ['missing-receipt', p => p.report.receipts.pop()],
      ['wrong-target', p => p.report.receipts[0].receipt.target = 'native'],
      ['changed-source', p => p.report.source.digest = '0'.repeat(64)],
      ['changed-log', p => p.files[p.report.receipts[0].receipt.logPath] += 'changed'],
      ['changed-input', p => p.files[p.report.receipts[0].receipt.inputPath] = '[]'],
      ['changed-value', p => p.report.observations[0].observed.wireRows = []],
      ['reuse-promotion', p => p.report.reuseAuthorized = true],
    ]) {
      const changed = structuredClone(answer.payload); alter(changed);
      assert.throws(() => validatePristineReport(changed.report, answer.payload.report.source, changed.files), name);
      rejected.push(name);
    }
    comparison = {normalMilliseconds: normal.milliseconds, isolatedCosts: answer.costs,
      scientificDigest: hash(JSON.stringify(scientific)), units: scientific.length,
      matched: true, rejected, scope: 'two local fresh pristine JS phases; not mutation detection, Actions qualification or net CI savings'};
  }
  assert.equal(git(['rev-parse', 'HEAD']), options.revision);
  assert.equal(git(['status', '--porcelain', '--untracked-files=no']), '');
  json(join(directory, 'acceptance.json'), {authority: 'local-physical-acceptance', reuseAuthorized: false,
    revision: options.revision, profile, builderImage: options.builderImage,
    manifestDigest: hash(JSON.stringify(prepared.manifest)), prepared, answer, comparison});
  console.log(JSON.stringify({directory, revision: options.revision, profile, units: profile === 'session' ? answer.payload.report.results.length : answer.payload.report.units,
    restored: answer.payload.restored ?? null, sourcePreserved: answer.payload.sourcePreserved ?? null, imageId: answer.imageId, comparison, reuseAuthorized: false}));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, ...args] = process.argv.slice(2);
  if (mode === 'prepare-linux') prepareLinux(args[0]);
  else if (mode === 'worker') worker(JSON.parse(args[0]));
  else {
    assert.equal(mode, 'run', 'Use run --engine PATH --builder-image sha256:ID --moon-home PATH');
    assert([6, 8].includes(args.length)); const options = {};
    for (let i = 0; i < args.length; i += 2) {
      assert(['--engine', '--builder-image', '--moon-home', '--profile'].includes(args[i]) && !options[args[i]], 'Invalid/duplicate option');
      options[args[i]] = args[i + 1];
    }
    const profile = options['--profile'] ?? 'session';
    assert(['session', 'pipeline-pristine'].includes(profile), 'Unregistered local profile');
    const engine = localEngine(options['--engine']), moonHome = realpathSync(options['--moon-home']);
    assert(lstatSync(moonHome).isDirectory());
    mkdirSync(join(root, '_build'), {recursive: true});
    process.exitCode = await runLocalCheck({root, heavy: true, timeoutSeconds: 1200, graceSeconds: 10,
      steps: [{name: `local isolated ${profile} physical acceptance`, command: process.execPath,
        args: [fileURLToPath(import.meta.url), 'worker', JSON.stringify({engine, moonHome, profile,
          builderImage: options['--builder-image'], revision: git(['rev-parse', 'HEAD'])})]}]});
  }
}
