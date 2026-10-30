// Stage public release metadata over normal, clean-HEAD prepacked artifacts.
// Compiled bytes and contracts are never regenerated or relabelled in staging.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, lstat, mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {basename, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState, packClientPackages, packedClientPackage} from './packed-client-packages.mjs';
import {releaseVersion} from './release-version.mjs';
import {admitReleaseChannel} from './release-policy.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const hash = (bytes, algorithm = 'sha256', encoding = 'hex') => createHash(algorithm).update(bytes).digest(encoding);
const exact = (object, keys) => assert.deepEqual(Object.keys(object).sort(), [...keys].sort());
const packageName = name => `@actql/${name}`;
const run = (command, args, cwd) => execFileSync(command, args, {
  cwd, encoding: 'utf8', timeout: 600_000, maxBuffer: 16 * 1024 * 1024});

export function admitCohort(value) {
  exact(value, ['version', 'packageVersion', 'registry', 'access', 'tag', 'packages']);
  assert(['actql-package-release-cohort/0.1', 'actql-explorer-release-cohort/0.1'].includes(value.version));
  releaseVersion(value.packageVersion);
  assert.equal(value.registry, 'https://registry.npmjs.org/');
  assert.equal(value.access, 'public');
  admitReleaseChannel(value.tag);
  assert.deepEqual(value.packages, value.version === 'actql-explorer-release-cohort/0.1'
    ? ['client-wire', 'sdk', 'local-node', 'node', 'explorer-ui', 'explorer']
    : ['client-wire', 'sdk', 'local-node', 'node']);
  return structuredClone(value);
}

export function releasePackageMetadata(original, name, cohort) {
  assert.equal(original.name, packageName(name));
  const manifest = structuredClone(original);
  manifest.version = cohort.packageVersion;
  manifest.private = false;
  manifest.license = 'Apache-2.0';
  manifest.repository = {type: 'git', url: 'git+https://github.com/actql/actql.git', directory: `packages/${name}`};
  manifest.publishConfig = {registry: cohort.registry, access: cohort.access};
  manifest.files = [...new Set([...(manifest.files ?? []), 'LICENSE'])];
  for (const field of ['dependencies', 'peerDependencies', 'optionalDependencies'])
    for (const [dependency, version] of Object.entries(manifest[field] ?? {})) {
    if (dependency.startsWith('@actql/')) {
      assert(cohort.packages.map(packageName).includes(dependency), `Missing release dependency: ${dependency}`);
      assert(cohort.packages.indexOf(dependency.slice(7)) < cohort.packages.indexOf(name), 'Cohort must be dependency ordered');
      manifest[field][dependency] = cohort.packageVersion;
    } else assert(!/^(?:file:|link:|workspace:)/u.test(version), 'Release dependency must be registry resolvable');
  }
  // Publication consumes the frozen payload, never a consumer checkout build.
  if (manifest.scripts?.prepack !== undefined) {
    delete manifest.scripts.prepack;
    if (Object.keys(manifest.scripts).length === 0) delete manifest.scripts;
  }
  for (const lifecycle of ['preinstall', 'install', 'postinstall']) assert.equal(manifest.scripts?.[lifecycle], undefined);
  return manifest;
}

export async function inventory(directory, prefix = '', {ignoreInstalledDependencies = false} = {}) {
  assert.equal(typeof ignoreInstalledDependencies, 'boolean');
  const files = [];
  for (const name of (await readdir(directory)).sort()) {
    // Only the public consumer asks to separate npm's installed dependency
    // subtree from this package's own frozen payload. Archive checks never do.
    if (ignoreInstalledDependencies && prefix === '' && name === 'node_modules') continue;
    const path = join(directory, name), relative = prefix + name;
    const stat = await lstat(path);
    assert(!stat.isSymbolicLink(), `Release payload symlink: ${relative}`);
    if (stat.isDirectory()) files.push(...await inventory(path, `${relative}/`));
    else {
      assert(stat.isFile(), `Non-file payload: ${relative}`);
      files.push({path: relative, bytes: stat.size, mode: stat.mode & 0o777,
        sha256: hash(await readFile(path))});
    }
  }
  return files;
}

export async function unpack(archive, destination, {rootName = 'package'} = {}) {
  assert(typeof rootName === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.-]*$/u.test(rootName) && rootName === rootName.trim(),
    'Archive root must be one literal directory name');
  const names = run('tar', ['-tzf', archive]);
  assert(names.length < 4 * 1024 * 1024, 'Archive inventory exceeds limit');
  const entries = names.trimEnd().split('\n');
  assert.equal(new Set(entries).size, entries.length, 'Duplicate archive entries are not release payloads');
  for (const name of entries) {
    assert(name.startsWith(`${rootName}/`) && !name.split('/').some(v => v === '..') &&
      !name.includes('\\') && !/[\u0000-\u001f\u007f]/u.test(name), `Unsafe archive entry: ${name}`);
  }
  for (const line of run('tar', ['-tvzf', archive]).trimEnd().split('\n')) {
    assert(/^[d-]/u.test(line), 'Archive links and special files are not release payloads');
  }
  await mkdir(destination, {recursive: true});
  run('tar', ['-xzf', archive, '-C', destination]);
  return join(destination, rootName);
}

export async function stagePackage({archive, destination, name, cohort, license}) {
  const scratch = await mkdtemp(join(destination, '.stage-'));
  try {
    const directory = await unpack(archive, scratch);
    const before = await inventory(directory);
    const original = JSON.parse(await readFile(join(directory, 'package.json'), 'utf8'));
    const manifest = releasePackageMetadata(original, name, cohort);
    await writeFile(join(directory, 'package.json'), `${JSON.stringify(manifest, null, 2)}\n`);
    await copyFile(license, join(directory, 'LICENSE'));
    const output = JSON.parse(run('npm', ['pack', '--ignore-scripts', '--json', '--pack-destination',
      destination, '--cache', join(destination, '.npm-cache')], directory));
    const packed = Array.isArray(output) ? output : Object.values(output);
    assert.equal(packed.length, 1);
    assert.equal(packed[0].name, packageName(name));
    assert.equal(packed[0].version, cohort.packageVersion);
    const file = packed[0].filename;
    assert.equal(file, `actql-${name}-${cohort.packageVersion}.tgz`);
    const verification = await mkdtemp(join(destination, '.verify-'));
    let after;
    try {after = await inventory(await unpack(join(destination, file), verification));}
    finally {await rm(verification, {recursive: true});}
    const payload = entries => entries.filter(v => !['package.json', 'LICENSE'].includes(v.path));
    assert.deepEqual(payload(after), payload(before), 'Staging must preserve every runtime byte and mode');
    assert(after.some(v => v.path === 'LICENSE'));
    const bytes = await readFile(join(destination, file));
    return {name: manifest.name, version: manifest.version, file, bytes: bytes.length,
      sha256: hash(bytes), integrity: `sha512-${hash(bytes, 'sha512', 'base64')}`,
      originalFile: basename(archive), originalSha256: hash(await readFile(archive)),
      dependencies: manifest.dependencies ?? {}, files: after};
  } finally {await rm(scratch, {recursive: true});}
}

export async function preparePackageRelease({repository = root, destination, cohortPath}) {
  assert(typeof cohortPath === 'string' && cohortPath.length, 'Supply an explicit cohort file; no default release version');
  const cohort = admitCohort(JSON.parse(await readFile(cohortPath, 'utf8')));
  const source = checkoutState(repository);
  assert(source.clean, 'Release needs clean source HEAD');
  destination = resolve(destination);
  // Unique output preserves previous RCs and makes accidental overwrite fail.
  await mkdir(destination);
  const originals = join(destination, 'development');
  await packClientPackages({repository, destination: originals, names: cohort.packages,
    pack: name => packedClientPackage({repository, name, destination: originals, pack: () => {
      run('npm', ['pack', '--json', '--pack-destination', originals, '--cache', join(destination, '.npm-cache')],
        join(repository, 'packages', name));
    }}),
  });
  const packages = [];
  for (const name of cohort.packages) {
    const original = JSON.parse(await readFile(join(repository, 'packages', name, 'package.json'), 'utf8'));
    packages.push(await stagePackage({archive: join(originals, `actql-${name}-${original.version}.tgz`),
      destination, name, cohort, license: join(repository, 'LICENSE')}));
  }
  assert.deepEqual(checkoutState(repository), source, 'Source changed during release preparation');
  const manifest = {version: 'actql-package-release/0.1', sourceSha: source.revision,
    preparedAt: new Date().toISOString(), cohort,
    recipeSha256: hash(await readFile(join(repository, 'scripts/package-release.mjs'))),
    cohortSha256: hash(await readFile(cohortPath)),
    toolchain: {node: process.version, npm: run('npm', ['--version']).trim(), moon: run('moon', ['version'], repository).trim(),
      platform: process.platform, arch: process.arch},
    generation: 'normal-prepack-then-metadata-and-license-only', packages};
  await writeFile(join(destination, 'release.json'), `${JSON.stringify(manifest, null, 2)}\n`, {flag: 'wx'});
  return manifest;
}

export async function verifyPackageRelease(directory) {
  const manifest = JSON.parse(await readFile(join(directory, 'release.json'), 'utf8'));
  exact(manifest, ['version', 'sourceSha', 'preparedAt', 'cohort', 'recipeSha256', 'cohortSha256', 'toolchain', 'generation', 'packages']);
  assert.equal(manifest.version, 'actql-package-release/0.1');
  assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  const cohort = admitCohort(manifest.cohort);
  const originalManifest = JSON.parse(await readFile(join(directory, 'development/packed-client-packages.json'), 'utf8'));
  assert.equal(originalManifest.revision, manifest.sourceSha);
  assert.deepEqual(manifest.packages.map(v => v.name), cohort.packages.map(packageName));
  for (const item of manifest.packages) {
    assert.equal(item.version, cohort.packageVersion);
    assert.equal(item.file, `${item.name.replace('@', '').replace('/', '-')}-${item.version}.tgz`);
    const bytes = await readFile(join(directory, item.file));
    assert.equal(bytes.length, item.bytes);
    assert.equal(hash(bytes), item.sha256);
    assert.equal(`sha512-${hash(bytes, 'sha512', 'base64')}`, item.integrity);
    assert.equal(item.originalFile, `actql-${item.name.slice(7)}-0.0.0-development.tgz`);
    const original = join(directory, 'development', item.originalFile);
    assert.equal(hash(await readFile(original)), item.originalSha256);
    assert.equal(originalManifest.tarballs[item.name.slice(7)], item.originalSha256);
    const scratch = await mkdtemp(join(directory, '.inspect-'));
    try {
      const payload = await unpack(join(directory, item.file), scratch);
      assert.deepEqual(await inventory(payload), item.files);
      const metadata = JSON.parse(await readFile(join(payload, 'package.json'), 'utf8'));
      assert.deepEqual(releasePackageMetadata(metadata, item.name.slice(7), cohort), metadata);
      assert.deepEqual(metadata.dependencies ?? {}, item.dependencies);
      const originalDirectory = await unpack(original, join(scratch, 'original'));
      const originalMetadata = JSON.parse(await readFile(join(originalDirectory, 'package.json'), 'utf8'));
      assert.deepEqual(releasePackageMetadata(originalMetadata, item.name.slice(7), cohort), metadata);
      const runtime = entries => entries.filter(v => !['package.json', 'LICENSE'].includes(v.path));
      assert.deepEqual(runtime(await inventory(originalDirectory)), runtime(item.files));
    } finally {await rm(scratch, {recursive: true});}
  }
  return manifest;
}

// A missing immutable version is distinct from registry failure or a mismatch.
export async function publishedVersion(item, registry, fetchMetadata = fetch) {
  const response = await fetchMetadata(`${registry}${encodeURIComponent(item.name)}/${item.version}`,
    {signal: AbortSignal.timeout(15_000), redirect: 'error'});
  if (response.status === 404) return 'absent';
  assert.equal(response.status, 200, `Registry unavailable: ${response.status}`);
  const metadata = await response.json();
  assert.equal(metadata.name, item.name);
  assert.equal(metadata.version, item.version);
  assert.equal(metadata.dist?.integrity, item.integrity, `Occupied version has different bytes: ${item.name}`);
  return 'published-identical';
}

export async function publicationPlan(manifest, fetchMetadata = fetch) {
  const plan = [];
  for (const item of manifest.packages) plan.push({name: item.name, version: item.version,
    file: item.file, integrity: item.integrity,
    state: await publishedVersion(item, manifest.cohort.registry, fetchMetadata)});
  return plan;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, directory, cohortPath] = process.argv.slice(2);
  assert(directory && ['prepare', 'verify', 'plan'].includes(command),
    'usage: package-release.mjs prepare <unique-directory> <explicit-cohort-json> | verify|plan <directory>');
  assert(process.argv.length <= 5 && (cohortPath === undefined || command === 'prepare'));
  if (command === 'prepare') assert(cohortPath, 'Supply an explicit cohort file; no default release version');
  const manifest = command === 'prepare' ? await preparePackageRelease({destination: directory,
    cohortPath: resolve(cohortPath)}) : await verifyPackageRelease(resolve(directory));
  console.log(JSON.stringify(command === 'plan' ? await publicationPlan(manifest) : {
    sourceSha: manifest.sourceSha, manifest: join(resolve(directory), 'release.json'),
    packages: manifest.packages.map(({name, version, file, sha256, integrity}) => ({name, version, file, sha256, integrity}))}, null, 2));
}
