// Stage public release metadata over normal, clean-HEAD prepacked artifacts.
// Compiled bytes and contracts are never regenerated or relabelled in staging.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {copyFile, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {basename, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState, packClientPackages, packedClientPackage} from './packed-client-packages.mjs';
import {releaseVersion} from './release-version.mjs';
import {admitReleaseChannel} from './release-policy.mjs';
import {inventory} from './package-inventory.mjs';

export {inventory} from './package-inventory.mjs';

import type {BinaryLike, BinaryToTextEncoding} from 'node:crypto';

type ReleaseCohort = {version: string; packageVersion: string; registry: string;
  access: string; tag: string; packages: string[]};
type PackageMetadata = {name: string; version: string; private?: boolean;
  license?: string; repository?: unknown; publishConfig?: unknown; files?: string[];
  dependencies?: Record<string, string>; peerDependencies?: Record<string, string>;
  optionalDependencies?: Record<string, string>; scripts?: Record<string, string>;
  [key: string]: unknown};
type FileFact = {path: string; bytes: number; mode: number; sha256: string};
type ReleasePackage = Awaited<ReturnType<typeof stagePackage>>;
type ReleaseManifest = {version: string; sourceSha: string; preparedAt: string;
  cohort: ReleaseCohort; recipeSha256: string; cohortSha256: string;
  toolchain: {node: string; npm: string; moon: string; platform: string; arch: string};
  generation: string; packages: ReleasePackage[]};
type MetadataFetcher = (input: string, init: Pick<RequestInit, 'signal' | 'redirect'>) =>
  Promise<{status: number; json(): Promise<unknown>}>;

const root = fileURLToPath(new URL('../', import.meta.url));
const hash = (bytes: BinaryLike, algorithm = 'sha256', encoding: BinaryToTextEncoding = 'hex') => createHash(algorithm).update(bytes).digest(encoding);
const exact = (object: object, keys: readonly string[]) => assert.deepEqual(Object.keys(object).sort(), [...keys].sort());
const packageName = (name: string) => `@actql/${name}`;
export const nodePackages = Object.freeze(['client-wire', 'sdk', 'local-node', 'node']);
const nodeOpenAIPackages = Object.freeze([...nodePackages, 'provider-ai-sdk']);
const run = (command: string, args: readonly string[], cwd?: string) => execFileSync(command, args, {
  cwd, encoding: 'utf8', timeout: 600_000, maxBuffer: 16 * 1024 * 1024});

export function nodeReleaseIncludesProvider(packages: readonly string[]) {
  const includesProvider = packages.length === nodeOpenAIPackages.length;
  assert.deepEqual(packages, includesProvider ? nodeOpenAIPackages : nodePackages,
    'Select the complete standard Node cohort or the explicit Node and Provider cohort');
  return includesProvider;
}

export function admitCohort(value: ReleaseCohort) {
  exact(value, ['version', 'packageVersion', 'registry', 'access', 'tag', 'packages']);
  assert(['actql-package-release-cohort/0.1', 'actql-explorer-release-cohort/0.1'].includes(value.version));
  releaseVersion(value.packageVersion);
  assert.equal(value.registry, 'https://registry.npmjs.org/');
  assert.equal(value.access, 'public');
  admitReleaseChannel(value.tag);
  assert(Array.isArray(value.packages));
  if (value.version === 'actql-explorer-release-cohort/0.1')
    assert.deepEqual(value.packages, [...nodePackages, 'explorer-ui', 'explorer']);
  else nodeReleaseIncludesProvider(value.packages);
  return structuredClone(value);
}

export function releasePackageMetadata(original: PackageMetadata, name: string, cohort: ReleaseCohort) {
  assert.equal(original.name, packageName(name));
  const manifest = structuredClone(original);
  manifest.version = cohort.packageVersion;
  manifest.private = false;
  manifest.license = 'Apache-2.0';
  manifest.repository = {type: 'git', url: 'git+https://github.com/actql/actql.git', directory: `packages/${name}`};
  manifest.publishConfig = {registry: cohort.registry, access: cohort.access};
  manifest.files = [...new Set([...(manifest.files ?? []), 'LICENSE'])];
  for (const field of ['dependencies', 'peerDependencies', 'optionalDependencies'] as const)
    for (const [dependency, version] of Object.entries(manifest[field] ?? {})) {
    if (dependency.startsWith('@actql/')) {
      assert(cohort.packages.map(packageName).includes(dependency), `Missing release dependency: ${dependency}`);
      assert(cohort.packages.indexOf(dependency.slice(7)) < cohort.packages.indexOf(name), 'Cohort must be dependency ordered');
      manifest[field]![dependency] = cohort.packageVersion;
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

export async function unpack(archive: string, destination: string, {rootName = 'package'} = {}) {
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

async function verifyProviderPackage(name: string, directory: string, metadata: PackageMetadata, files: readonly FileFact[]) {
  if (name !== 'provider-ai-sdk') return;
  assert.deepEqual(metadata.exports, {'.': {types: './index.d.ts', default: './index.mjs'}},
    'Provider has one matching public runtime and type entrance');
  for (const path of ['index.mjs', 'index.d.ts', 'npm-shrinkwrap.json'])
    assert(files.some(member => member.path === path), `Missing original Provider release member: ${path}`);
  const shrinkwrap = JSON.parse(await readFile(join(directory, 'npm-shrinkwrap.json'), 'utf8'));
  assert.equal(shrinkwrap.name, metadata.name);
  assert.equal(shrinkwrap.packages?.['']?.name, metadata.name);
  assert.equal(shrinkwrap.lockfileVersion, 3);
  assert.deepEqual(shrinkwrap.packages[''].dependencies ?? {}, metadata.dependencies ?? {},
    'Provider runtime dependencies must match the original packed shrinkwrap');
}

export async function stagePackage({archive, destination, name, cohort, license}: {
  archive: string; destination: string; name: string; cohort: ReleaseCohort; license: string;
}) {
  const scratch = await mkdtemp(join(destination, '.stage-'));
  try {
    const directory = await unpack(archive, scratch);
    const before = await inventory(directory);
    const original = JSON.parse(await readFile(join(directory, 'package.json'), 'utf8'));
    await verifyProviderPackage(name, directory, original, before);
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
    let after: FileFact[];
    try {after = await inventory(await unpack(join(destination, file), verification));}
    finally {await rm(verification, {recursive: true});}
    const payload = (entries: readonly FileFact[]) => entries.filter(v => !['package.json', 'LICENSE'].includes(v.path));
    assert.deepEqual(payload(after), payload(before), 'Staging must preserve every runtime byte and mode');
    assert(after.some(v => v.path === 'LICENSE'));
    const bytes = await readFile(join(destination, file));
    return {name: manifest.name, version: manifest.version, file, bytes: bytes.length,
      sha256: hash(bytes), integrity: `sha512-${hash(bytes, 'sha512', 'base64')}`,
      originalFile: basename(archive), originalSha256: hash(await readFile(archive)),
      dependencies: manifest.dependencies ?? {}, files: after};
  } finally {await rm(scratch, {recursive: true});}
}

export async function preparePackageRelease({repository = root, destination, cohortPath}: {repository?: string; destination: string; cohortPath: string}) {
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

export async function verifyPackageRelease(directory: string) {
  const manifest = JSON.parse(await readFile(join(directory, 'release.json'), 'utf8')) as ReleaseManifest;
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
      await verifyProviderPackage(item.name.slice(7), payload, metadata, item.files);
      assert.deepEqual(releasePackageMetadata(metadata, item.name.slice(7), cohort), metadata);
      assert.deepEqual(metadata.dependencies ?? {}, item.dependencies);
      const originalDirectory = await unpack(original, join(scratch, 'original'));
      const originalMetadata = JSON.parse(await readFile(join(originalDirectory, 'package.json'), 'utf8'));
      assert.deepEqual(releasePackageMetadata(originalMetadata, item.name.slice(7), cohort), metadata);
      const runtime = (entries: readonly FileFact[]) => entries.filter(v => !['package.json', 'LICENSE'].includes(v.path));
      assert.deepEqual(runtime(await inventory(originalDirectory)), runtime(item.files));
    } finally {await rm(scratch, {recursive: true});}
  }
  return manifest;
}

// A missing immutable version is distinct from registry failure or a mismatch.
export async function publishedVersion(item: Pick<ReleasePackage, 'name' | 'version' | 'integrity'>, registry: string, fetchMetadata: MetadataFetcher = fetch) {
  const response = await fetchMetadata(`${registry}${encodeURIComponent(item.name)}/${item.version}`,
    {signal: AbortSignal.timeout(15_000), redirect: 'error'});
  if (response.status === 404) return 'absent';
  assert.equal(response.status, 200, `Registry unavailable: ${response.status}`);
  const metadata = await response.json() as {name?: unknown; version?: unknown; dist?: {integrity?: unknown}};
  assert.equal(metadata.name, item.name);
  assert.equal(metadata.version, item.version);
  assert.equal(metadata.dist?.integrity, item.integrity, `Occupied version has different bytes: ${item.name}`);
  return 'published-identical';
}

type PublicationInventory = {
  packages: readonly Pick<ReleasePackage, 'name' | 'version' | 'file' | 'integrity'>[];
  cohort: {registry: string};
};

export async function publicationPlan(manifest: PublicationInventory, fetchMetadata: MetadataFetcher = fetch) {
  const plan = [];
  for (const item of manifest.packages) plan.push({name: item.name, version: item.version,
    file: item.file, integrity: item.integrity,
    state: await publishedVersion(item, manifest.cohort.registry, fetchMetadata)});
  return plan;
}

export async function publishPackageRelease({directory, executePublish, fetchMetadata = fetch,
  verify = verifyPackageRelease}: {
  directory: string;
  executePublish(request: {file: string; registry: string; access: string; tag: string}): void | Promise<void>;
  fetchMetadata?: MetadataFetcher;
  verify?(directory: string): Promise<PublicationInventory & {
    sourceSha: string; cohort: {registry: string; access: string; tag: string};
  }>;
}) {
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
  const [command, directory, cohortPath] = process.argv.slice(2);
  assert(directory && ['prepare', 'verify', 'plan'].includes(command),
    'usage: package-release.mjs prepare <unique-directory> <explicit-cohort-json> | verify|plan <directory>');
  assert(process.argv.length <= 5 && (cohortPath === undefined || command === 'prepare'));
  if (command === 'prepare') assert(cohortPath, 'Supply an explicit cohort file; no default release version');
  const manifest = command === 'prepare' ? await preparePackageRelease({destination: directory,
    cohortPath: resolve(cohortPath!)}) : await verifyPackageRelease(resolve(directory));
  console.log(JSON.stringify(command === 'plan' ? await publicationPlan(manifest) : {
    sourceSha: manifest.sourceSha, manifest: join(resolve(directory), 'release.json'),
    packages: manifest.packages.map(({name, version, file, sha256, integrity}) => ({name, version, file, sha256, integrity}))}, null, 2));
}
