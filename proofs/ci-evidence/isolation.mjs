// The first isolated executor is restricted to the existing JS mutation action.
// Build an immutable scratch image from staged bytes, not a mutable registry tag
// or host bind mounts. This preparation alone does not authorize evidence reuse.
import assert from 'node:assert/strict';
import {constants, openSync, closeSync, readSync, fstatSync, lstatSync, mkdirSync,
  writeFileSync, chmodSync, utimesSync, opendirSync, readlinkSync, symlinkSync, realpathSync} from 'node:fs';
import {join, dirname, resolve, relative, isAbsolute} from 'node:path';
import {createHash} from 'node:crypto';
import {encode} from '../bounded-session/action-inputs.mjs';
import {hash, mutationSnapshotExtras} from './inputs.mjs';
export {mutationSnapshotExtras} from './inputs.mjs';

export const isolatedEnvironment = Object.freeze({HOME: '/tmp/home', TMPDIR: '/tmp',
  PATH: '/runtime/moonbit/bin:/runtime', MOON_HOME: '/runtime/moonbit',
  LANG: 'C', LC_ALL: 'C', TZ: 'UTC'});
export const isolatedSourceFiles = Object.freeze(['proofs/ci-evidence/isolated-mutations.mjs',
  'proofs/ci-evidence/isolation.mjs', 'proofs/ci-evidence/isolated-runtime.mjs',
  'proofs/ci-evidence/runtime.mjs', 'proofs/ci-evidence/inputs.mjs',
  'proofs/ci-evidence/package-configurations.mjs',
  'proofs/ci-evidence/mutation-inventory.mjs']);
const child = isolatedSourceFiles[0];
const safe = path => typeof path === 'string' && /^[A-Za-z0-9_.\/-]+$/u.test(path) &&
  !isAbsolute(path) && !path.split('/').some(part => ['', '.', '..'].includes(part));
const stable = (a, b) => ['dev', 'ino', 'mode', 'size', 'mtimeNs', 'ctimeNs'].every(key => a[key] === b[key]);

export function mutationSourcePaths(tree) {
  const paths = [...new Set([...tree.entries.keys()].filter(path => path.startsWith('src/') ||
    path.startsWith('proofs/bounded-session/')).concat(mutationSnapshotExtras, isolatedSourceFiles))].sort();
  assert(paths.includes('proofs/bounded-session/mutations.mjs'), 'Missing original mutation executor');
  for (const path of paths) {
    const entry = tree.entries.get(path);
    assert(safe(path) && entry?.kind === 'blob' && ['100644', '100755'].includes(entry.mode), 'Unsupported isolated source path/kind/mode');
  }
  return paths;
}

export function stageMutationSource({tree, destination, maxBytes = 128 * 1024 * 1024}) {
  assert(Number.isSafeInteger(maxBytes) && maxBytes > 0, 'Invalid source byte bound');
  const paths = mutationSourcePaths(tree), files = [];
  tree.prefetch?.(paths);
  let bytes = 0;
  for (const path of paths) {
    const data = tree.read(path), mode = Number.parseInt(tree.entries.get(path).mode.slice(-3), 8);
    bytes += data.length; assert(bytes <= maxBytes, 'Isolated source exceeds bounded size');
    const target = join(destination, 'source', path);
    mkdirSync(dirname(target), {recursive: true}); writeFileSync(target, data, {flag: 'wx', mode});
    chmodSync(target, mode); utimesSync(target, 0, 0);
    files.push({path: `source/${path}`, mode, bytes: data.length, digest: hash(data)});
  }
  return {files, bytes};
}

// Read a stable regular file through an exclusive destination. Never copy
// devices, follow a link here, or read more than the explicitly bounded size.
export function copyRegular({source, target, budget}) {
  assert(Number.isSafeInteger(budget?.remaining) && budget.remaining >= 0, 'Invalid runtime byte budget');
  const before = lstatSync(source, {bigint: true});
  assert(before.isFile() && before.size <= BigInt(budget.remaining), 'Missing/nonregular/oversized runtime input');
  const fd = openSync(source, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  let output;
  const digest = createHash('sha256'), mode = Number(before.mode & 0o777n);
  try {
    assert(stable(before, fstatSync(fd, {bigint: true})), 'Runtime input changed before read');
    mkdirSync(dirname(target), {recursive: true});
    output = openSync(target, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL, mode);
    const chunk = Buffer.alloc(1024 * 1024), size = Number(before.size);
    let count = 0, n;
    while ((n = readSync(fd, chunk, 0, Math.min(chunk.length, size - count + 1))) > 0) {
      count += n; assert(count <= size, 'Runtime input grew'); digest.update(chunk.subarray(0, n));
      // Node's writeFileSync on an owned descriptor writes all buffer bytes.
      writeFileSync(output, chunk.subarray(0, n));
    }
    assert(count === size && stable(before, fstatSync(fd, {bigint: true})) &&
      stable(before, lstatSync(source, {bigint: true})), 'Runtime input changed during read');
    budget.remaining -= count;
    return {mode, bytes: count, digest: digest.digest('hex')};
  } finally {
    closeSync(fd); if (output !== undefined) closeSync(output);
    if (output !== undefined) { chmodSync(target, mode); utimesSync(target, 0, 0); }
  }
}

// Preserve in-distribution symlinks and bind their exact targets. Every chain
// must terminate inside the staged installation; outside/dangling/cyclic links
// fail preparation instead of becoming a cleared unresolved label.
export function stageDistribution({source, destination, budget, maxEntries = 30000}) {
  assert(Number.isSafeInteger(maxEntries) && maxEntries > 0, 'Invalid distribution entry bound');
  assert(lstatSync(source).isDirectory(), 'Distribution root must be a real directory');
  // Parent aliases such as macOS /var -> /private/var do not constitute a
  // distribution escape. Compare physical roots after rejecting a linked root.
  const root = realpathSync(source), records = [], links = [];
  function visit(path) {
    assert(records.length < maxEntries, 'Distribution entry bound exceeded');
    const from = path ? join(root, path) : root, to = path ? join(destination, path) : destination;
    const before = lstatSync(from, {bigint: true}), mode = Number(before.mode & 0o777n);
    if (before.isSymbolicLink()) {
      const target = readlinkSync(from), resolved = realpathSync(from), inside = relative(root, resolved);
      assert(!isAbsolute(target) && inside && !inside.startsWith('../') && !isAbsolute(inside), 'Distribution link escapes the staged root');
      mkdirSync(dirname(to), {recursive: true}); symlinkSync(target, to);
      records.push({path, kind: 'symlink', mode, target}); links.push({path, resolved: inside});
    } else if (before.isDirectory()) {
      mkdirSync(to, {recursive: true}); chmodSync(to, mode);
      const directory = opendirSync(from), members = [];
      try {
        let entry;
        while ((entry = directory.readSync()) !== null) {
          assert(members.length < maxEntries, 'Distribution membership bound exceeded'); members.push(entry.name);
        }
      } finally { directory.closeSync(); }
      members.sort(); records.push({path, kind: 'directory', mode, members});
      for (const member of members) { assert(safe(member), 'Unreviewed distribution path'); visit(path ? `${path}/${member}` : member); }
    } else {
      assert(before.isFile(), 'Nonregular distribution entry');
      records.push({path, kind: 'file', ...copyRegular({source: from, target: to, budget})});
    }
    assert(stable(before, lstatSync(from, {bigint: true})), 'Distribution changed during staging');
  }
  visit('');
  for (const link of links) {
    assert(records.some(record => record.path === link.resolved && ['file', 'directory'].includes(record.kind)), 'Unstaged link target');
    assert.equal(relative(realpathSync(destination), realpathSync(join(destination, link.path))), link.resolved, 'Staged link changed resolution');
  }
  return {records, digest: hash(encode(records))};
}

// ldd is an explicit trusted extraction step for already pinned executables.
// Unknown output and nonstandard library locations are not guessed away. The
// staged image has no other host library/configuration mounts or network.
export function loaderPaths(output) {
  const paths = new Set();
  for (const raw of output.split('\n').filter(line => line.trim())) {
    const line = raw.trim();
    if (/^linux-vdso\.so\.\d+ \(0x[0-9a-f]+\)$/u.test(line)) continue;
    const library = /^(?:[A-Za-z0-9_.+-]+ => )?(\/(?:usr\/)?lib(?:64)?\/[A-Za-z0-9_./+-]+) \(0x[0-9a-f]+\)$/u.exec(line);
    assert(library && !library[1].split('/').includes('..'), 'Unresolved/unsupported ELF loader input');
    paths.add(library[1]);
  }
  assert(paths.size > 0, 'Missing ELF loader inputs');
  return [...paths].sort();
}

export function isolatedRunArguments({imageId, cidFile, owner}) {
  assert(/^sha256:[a-f0-9]{64}$/u.test(imageId), 'Use an inspected immutable image ID');
  assert(typeof cidFile === 'string' && isAbsolute(cidFile), 'Use an owned absolute CID file');
  assert(typeof owner === 'string' && /^[0-9]+:[0-9]+:[0-9]+$/u.test(owner), 'Use the actual run/attempt/job owner');
  return ['run', '--rm', '--pull=never', '--read-only', '--network=none', '--cap-drop=ALL',
    '--security-opt=no-new-privileges', '--user=1000:1000', '--hostname=actql-session',
    '--label', `org.actql.ci.owner=${owner}`, '--cidfile', cidFile, '--tmpfs', '/tmp:rw,nosuid,nodev,mode=1777',
    '--tmpfs', '/workspace:rw,nosuid,nodev,mode=1777', '--workdir=/workspace',
    '--entrypoint=/runtime/node', imageId, `/source/${child}`];
}

export function scratchDockerfile() {
  return ['FROM scratch', 'COPY root/ /', ...Object.entries(isolatedEnvironment).map(([name, value]) => `ENV ${name}=${value}`),
    'USER 1000:1000', 'WORKDIR /workspace', `ENTRYPOINT ["/runtime/node", "/source/${child}"]`, ''].join('\n');
}

// The build instruction bytes are not a substitute for inspecting the image
// actually produced. Refuse extra ENV, startup hooks and automatically mounted
// volumes before running any command from that image. Never print ENV values.
export function checkImageDefinition({image, imageId, owner}) {
  assert(/^sha256:[a-f0-9]{64}$/u.test(imageId) && /^[0-9]+:[0-9]+:[0-9]+$/u.test(owner), 'Invalid image identity/owner');
  assert.equal(image.Id, imageId); assert.equal(image.Os, 'linux'); assert.equal(image.Architecture, 'amd64');
  const config = image.Config;
  assert(config?.Labels?.['org.actql.ci.owner'] === owner, 'Wrong built image owner');
  // Builders can retain the position of an existing default PATH when ENV
  // replaces its value. Order is not a dependency when all names are unique;
  // exact sorted entries still reject extra, missing, duplicate or changed ENV.
  assert(Array.isArray(config.Env) && config.Env.every(value => typeof value === 'string') &&
    encode([...config.Env].sort()) === encode(Object.entries(isolatedEnvironment).map(([name, value]) => `${name}=${value}`).sort()),
  'Unexpected built image environment');
  assert(config.User === '1000:1000' && config.WorkingDir === '/workspace', 'Changed image user/workdir');
  assert(encode(config.Entrypoint) === encode(['/runtime/node', `/source/${child}`]), 'Changed image entrypoint');
  for (const field of ['Cmd', 'Volumes', 'Healthcheck', 'OnBuild', 'ExposedPorts']) {
    assert(config[field] === undefined || config[field] === null, 'Unreviewed image startup/configuration');
  }
  return true;
}
