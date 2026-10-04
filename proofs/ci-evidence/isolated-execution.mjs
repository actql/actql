// CI-only owner of one scratch image and one isolated execution. There are no
// host mounts, inherited container credentials, registry pulls or cache reuse.
// Keep this action comparison-only until runtime closure has been reviewed.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdirSync, mkdtempSync, readFileSync, writeFileSync, chmodSync, existsSync, realpathSync} from 'node:fs';
import {join} from 'node:path';
import {performance} from 'node:perf_hooks';
import {encode} from '../bounded-session/action-inputs.mjs';
import {snapshot} from '../bounded-session/evidence.mjs';
import {hash} from './inputs.mjs';
import {copyRegular, stageDistribution, stageMutationSource, loaderPaths, isolatedEnvironment,
  isolatedRunArguments, scratchDockerfile} from './isolation.mjs';
import {observeImageRoot, platformInputs, imageRuntime, checkIsolatedInputs, checkIsolatedResult} from './isolated-runtime.mjs';

const jsonBytes = value => Buffer.from(`${encode(value)}\n`);
const command = (program, args, options = {}) => {
  const result = spawnSync(program, args, {encoding: 'utf8', timeout: 120000,
    maxBuffer: 16 * 1024 * 1024, ...options});
  if (result.error || result.status !== 0) process.stderr.write((result.stderr ?? '').slice(-4000));
  assert(!result.error && result.status === 0, `Isolated executor command failed: ${program}`);
  return result.stdout;
};
const docker = args => command('/usr/bin/docker', args);

// Static executables need no copied loader. Require an actual ELF64 x86-64
// header with neither INTERP nor DYNAMIC; do not infer this from ldd's label.
export function staticElf(bytes) {
  if (bytes.length < 64 || !bytes.subarray(0, 7).equals(Buffer.from([0x7f, 69, 76, 70, 2, 1, 1])) || bytes.readUInt16LE(18) !== 62) return false;
  const offset = bytes.readBigUInt64LE(32), size = bytes.readUInt16LE(54), count = bytes.readUInt16LE(56);
  if (offset > BigInt(bytes.length) || size < 56 || count === 0 || Number(offset) + size * count > bytes.length) return false;
  for (let index = 0; index < count; index++) {
    if ([2, 3].includes(bytes.readUInt32LE(Number(offset) + index * size))) return false;
  }
  return true;
}

export function prepareIsolatedMutation({root, tree, origin, directory}) {
  assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Isolation preparation is CI-only');
  assert.equal(process.platform, 'linux'); assert.equal(process.arch, 'x64');
  const owner = `${origin.runId}:${origin.runAttempt}:${origin.jobId}`;
  assert(/^[0-9]+:[0-9]+:[0-9]+$/u.test(owner));
  const start = performance.now(), context = mkdtempSync(join(directory, 'isolated-build-'));
  const imageRoot = join(context, 'root'); mkdirSync(imageRoot);
  const source = stageMutationSource({tree, destination: imageRoot});
  const pin = JSON.parse(tree.read('toolchain.json'));
  const moonHome = process.env.MOON_HOME ?? join(root, '.toolchains', `moonbit-${pin.version}`);
  const budget = {remaining: 1024 ** 3};
  copyRegular({source: realpathSync(process.execPath), target: join(imageRoot, 'runtime/node'), budget});
  stageDistribution({source: moonHome, destination: join(imageRoot, 'runtime/moonbit'), budget});
  const executables = [process.execPath, ...['moon', 'moonc', 'moonrun'].map(name => join(moonHome, 'bin', name))];
  const loaderObservations = [], libraries = new Set();
  for (const [index, path] of executables.entries()) {
    const inspected = realpathSync(path), bytes = readFileSync(inspected);
    const result = spawnSync('/usr/bin/ldd', [inspected], {encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024,
      env: {PATH: '/usr/bin:/bin', LANG: 'C', LC_ALL: 'C'}});
    assert(!result.error, 'Loader inspection failed');
    const output = `${result.stdout ?? ''}${result.stderr ?? ''}`;
    const staticallyLinked = staticElf(bytes);
    assert(staticallyLinked ? /^(?:\s*(?:statically linked|not a dynamic executable)\s*)$/u.test(output) : result.status === 0,
      'Unsupported executable loader inspection');
    const paths = staticallyLinked ? [] : loaderPaths(output);
    paths.forEach(path => libraries.add(path));
    loaderObservations.push({executable: index === 0 ? 'runtime/node' : `runtime/moonbit/bin/${['moon', 'moonc', 'moonrun'][index - 1]}`,
      digest: hash(bytes), static: staticallyLinked, paths});
  }
  for (const library of [...libraries].sort()) copyRegular({source: realpathSync(library), target: join(imageRoot, library.slice(1)), budget});
  const probe = join(imageRoot, 'runtime/actql-write-probe'); writeFileSync(probe, '', {flag: 'wx', mode: 0o666}); chmodSync(probe, 0o666);
  const manifest = {version: 'actql-isolated-mutation-inputs/0.1', environment: isolatedEnvironment,
    dockerfile: scratchDockerfile(), root: observeImageRoot(imageRoot), platformInputs: platformInputs(), loaderObservations};
  const runtime = imageRuntime(manifest); checkIsolatedInputs({runtime, manifest, tree});
  mkdirSync(join(imageRoot, 'control')); writeFileSync(join(imageRoot, 'control/inputs.json'), jsonBytes(manifest), {flag: 'wx'});
  writeFileSync(join(context, 'Dockerfile'), manifest.dockerfile, {flag: 'wx'});
  return {owner, context, runtime, manifest, sourceBytes: source.bytes,
    preparationMilliseconds: Math.round(performance.now() - start)};
}

export function executeIsolatedMutation({root, tree, prepared}) {
  assert.equal(process.env.GITHUB_ACTIONS, 'true', 'Isolated execution is CI-only');
  checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree});
  const before = snapshot(root), tag = `actql-session-${prepared.owner.replaceAll(':', '-')}`;
  const cidFile = join(prepared.context, 'container.id'), iidFile = join(prepared.context, 'image.id');
  const costs = {preparationMilliseconds: prepared.preparationMilliseconds, buildMilliseconds: 0, executionMilliseconds: 0,
    inspectionMilliseconds: 0, closeMilliseconds: 0};
  let imageId, failure, answer;
  try {
    let start = performance.now();
    docker(['build', '--network=none', '--pull=false', '--label', `org.actql.ci.owner=${prepared.owner}`,
      '--iidfile', iidFile, '--tag', tag, prepared.context]);
    imageId = readFileSync(iidFile, 'utf8').trim();
    assert(/^sha256:[a-f0-9]{64}$/u.test(imageId), 'Missing immutable built image ID');
    const image = JSON.parse(docker(['image', 'inspect', imageId]));
    assert.equal(image.length, 1); assert.equal(image[0].Id, imageId);
    assert.equal(image[0].Config.Labels['org.actql.ci.owner'], prepared.owner);
    costs.buildMilliseconds = Math.round(performance.now() - start);
    start = performance.now();
    const args = isolatedRunArguments({imageId, cidFile, owner: prepared.owner});
    const result = spawnSync('/usr/bin/docker', args, {encoding: 'utf8', timeout: 10 * 60 * 1000, maxBuffer: 64 * 1024 * 1024});
    costs.executionMilliseconds = Math.round(performance.now() - start);
    if (result.error || result.status !== 0) process.stderr.write((result.stderr ?? '').slice(-4000));
    assert(!result.error && result.status === 0, 'Original isolated mutation action failed');
    start = performance.now();
    const prefix = 'ACTQL_ISOLATED_MUTATIONS ', lines = result.stdout.split('\n');
    const records = lines.filter(line => line.startsWith(prefix)); assert.equal(records.length, 1, 'Missing/duplicate actual isolation observation');
    const payload = JSON.parse(records[0].slice(prefix.length));
    checkIsolatedResult({payload, manifest: prepared.manifest, before});
    assert.equal(snapshot(root).digest, before.digest, 'Host source changed during isolation');
    const output = `${lines.filter(line => !line.startsWith(prefix)).join('\n')}${result.stderr ?? ''}`;
    costs.inspectionMilliseconds = Math.round(performance.now() - start);
    answer = {output, payload, imageId, owner: prepared.owner, arguments: args, costs};
  } catch (error) { failure = error; }
  const start = performance.now();
  try {
    // Only a container carrying this owner's label and this immutable image
    // may be closed. Never prune, unlink another CID or remove shared tags.
    if (existsSync(cidFile)) {
      const cid = readFileSync(cidFile, 'utf8').trim(); assert(/^[a-f0-9]{64}$/u.test(cid));
      const inspected = spawnSync('/usr/bin/docker', ['container', 'inspect', cid], {encoding: 'utf8', timeout: 30000});
      if (inspected.status === 0) {
        const [container] = JSON.parse(inspected.stdout);
        assert.equal(container.Id, cid); assert.equal(container.Image, imageId);
        assert.equal(container.Config.Labels['org.actql.ci.owner'], prepared.owner);
        docker(['container', 'rm', '--force', cid]);
      } else {
        assert(!inspected.error && inspected.status === 1 && /No such (?:object|container)/u.test(inspected.stderr), 'Unable to confirm owned container closure');
      }
    }
    if (imageId) {
      const [image] = JSON.parse(docker(['image', 'inspect', imageId]));
      assert.equal(image.Config.Labels['org.actql.ci.owner'], prepared.owner);
      assert.deepEqual(image.RepoTags, [tag], 'Image is referenced by another owner');
      docker(['image', 'rm', imageId]);
    }
  } catch (error) { if (!failure) failure = error; else console.error('Owned isolated executor cleanup also failed'); }
  costs.closeMilliseconds = Math.round(performance.now() - start);
  if (failure) throw failure;
  return answer;
}
