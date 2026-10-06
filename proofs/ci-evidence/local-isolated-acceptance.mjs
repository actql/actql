// A local physical diagnostic, never an authenticated Actions receipt. Linux
// preparation uses an explicit immutable builder; execution uses the same
// scratch image and scientific consumer as CI, with a different owner domain.
import assert from 'node:assert/strict';
import {spawnSync, execFileSync} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync, lstatSync, realpathSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {gitTree, hash} from './inputs.mjs';
import {checkIsolatedInputs} from './isolated-runtime.mjs';
import {prepareLocalIsolatedMutation, executeLocalIsolatedMutation} from './isolated-execution.mjs';
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
  const pin = JSON.parse(tree.read('toolchain.json'));
  const versions = [...new Set([...tree.read('.github/workflows/ci.yml').toString().matchAll(/node-version:\s*(\d+\.\d+\.\d+)/gu)].map(match => match[1]))];
  assert.equal(versions.length, 1, 'Ambiguous pinned Node version');
  assert.equal(process.version, `v${versions[0]}`, 'Builder Node differs from the candidate workflow pin');
  assert.equal(call('/toolchain/bin/moonc', ['-v']).trim(), pin.moonc);
  assert.equal(call('/toolchain/bin/moon', ['version']).trim().split(/\r?\n/u)[0], `moon ${pin.moon}`);
  const prepared = prepareLocalIsolatedMutation({root: '/candidate', tree, owner: descriptor.owner, directory: '/out'});
  json('/out/prepared.json', prepared);
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
  const descriptor = {revision: options.revision, owner, entries: [...tree.entries]};
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
    '/candidate/proofs/ci-evidence/local-isolated-acceptance.mjs', 'prepare-linux', '/out/checkout.json'], 180000);
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
  checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree});
  const answer = executeLocalIsolatedMutation({root, tree, prepared, engine: options.engine});
  assert.equal(git(['rev-parse', 'HEAD']), options.revision);
  assert.equal(git(['status', '--porcelain', '--untracked-files=no']), '');
  json(join(directory, 'acceptance.json'), {authority: 'local-physical-acceptance', reuseAuthorized: false,
    revision: options.revision, builderImage: options.builderImage,
    manifestDigest: hash(JSON.stringify(prepared.manifest)), prepared, answer});
  console.log(JSON.stringify({directory, revision: options.revision, mutations: answer.payload.report.results.length,
    restored: answer.payload.restored, imageId: answer.imageId, reuseAuthorized: false}));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [mode, ...args] = process.argv.slice(2);
  if (mode === 'prepare-linux') prepareLinux(args[0]);
  else if (mode === 'worker') worker(JSON.parse(args[0]));
  else {
    assert.equal(mode, 'run', 'Use run --engine PATH --builder-image sha256:ID --moon-home PATH');
    assert.equal(args.length, 6); const options = {};
    for (let i = 0; i < args.length; i += 2) {
      assert(['--engine', '--builder-image', '--moon-home'].includes(args[i]) && !options[args[i]], 'Invalid/duplicate option');
      options[args[i]] = args[i + 1];
    }
    const engine = realpathSync(options['--engine']), moonHome = realpathSync(options['--moon-home']);
    assert(lstatSync(engine).isFile() && lstatSync(moonHome).isDirectory());
    mkdirSync(join(root, '_build'), {recursive: true});
    process.exitCode = await runLocalCheck({root, heavy: true, timeoutSeconds: 1200, graceSeconds: 10,
      steps: [{name: 'local isolated Session physical acceptance', command: process.execPath,
        args: [fileURLToPath(import.meta.url), 'worker', JSON.stringify({engine, moonHome,
          builderImage: options['--builder-image'], revision: git(['rev-parse', 'HEAD'])})]}]});
  }
}
