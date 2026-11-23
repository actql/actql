import {checkInterfaceOwners, checkedOriginalInterface} from './check-interface-owners.mjs';
import {retainNativeMockCampaignInputs} from './native-mock-campaign-inputs.mjs';
// Frozen OS binary packages use the same inventory/registry/publisher as SDK.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, copyFile, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState, CLIENT_PACKAGES, normalNpmPackJsonArgs, parseNpmPackJson} from './packed-client-packages.mjs';
import {inventory, unpack, publicationPlan, publishPackageRelease} from './package-release.mjs';
import {refuseUnconfiguredPublication} from './release-authority.mjs';
import {releaseVersion} from './release-version.mjs';
import {admitReleaseChannel} from './release-policy.mjs';
import {admitInstalledLocalRuntime} from '../packages/native-cli/lib/local-runtime.mjs';
import {PRODUCT_MEMBERS_FILE} from '../packages/native-cli/lib/product-members.mjs';
import {stageProductMembers, verifyStagedProductMembers, launcherMemberPlatform} from './native-cli-product-members.mjs';

import {nativeCliPackageInputs, nativeCliPlatforms as platforms} from './native-cli-package-inputs.mjs';
import {admitNativeArtifact, admitInstalledNativeArtifactMaterial, requireNativePackageVersion} from './native-cli-artifact-reader.mjs';
export {admitNativeArtifact} from './native-cli-artifact-reader.mjs';
import {checkStagedNativeCliInterfaces} from './native-cli-interface-check.mjs';
import type {BinaryLike, BinaryToTextEncoding} from 'node:crypto';

type Cohort = {packageVersion: string; registry: string; access: string; tag: string};
type Artifact = Awaited<ReturnType<typeof admitNativeArtifact>>;
type ProductMembers = Awaited<ReturnType<typeof stageProductMembers>>;
type NativePackage = Awaited<ReturnType<typeof pack>>;
type PlatformRecord = {
  package: string; sourceSha: string; binarySha256: string; binaryBytes: number;
  localRuntimeSha256?: string; productMembers?: ProductMembers;
};
type NativeReleaseManifest = {
  version: string; sourceSha: string; preparedAt: string; recipeSha256: string;
  cohort: Cohort; platforms: Record<string, PlatformRecord>; artifacts: Artifact[]; packages: NativePackage[];
};
type LauncherMetadata = {
  name: string; files: string[]; scripts?: Record<string, string>;
  optionalDependencies?: Record<string, string>;
};
type Admission = Readonly<{verify(): Promise<NativeReleaseManifest>; assertCurrent(): void}>;
type RetainedAdmission = {
  source: ReturnType<typeof checkoutState>; manifest: string;
  assertInputs: ReturnType<typeof retainNativeMockCampaignInputs>;
  checked?: string; assertActive(): void;
};

// Same callback handle only. This binds the existing scoped admission, not a
// second verifier, cross-campaign cache or serialized preparation authority.
const nativeMockAdmissions = new WeakMap<object, {directory: string}>();

const repository = fileURLToPath(new URL('../', import.meta.url));
const hash = (bytes: BinaryLike, algorithm = 'sha256', encoding: BinaryToTextEncoding = 'hex') =>
  createHash(algorithm).update(bytes).digest(encoding);
const exact = (v: unknown, keys: readonly string[]) => assert.deepEqual(Object.keys(v as object).sort(), [...keys].sort());

// The two RCs retain distinct source SHAs. Their shared Host and protocol
// packages must agree too: generated wire and SDK code live outside src/.
export function sharedRuntimeSourceDelta(root: string, hostSha: string, cliSha: string) {
  for (const revision of [hostSha, cliSha]) assert.match(revision, /^[a-f0-9]{40}$/u);
  return execFileSync('git', ['--no-replace-objects', 'diff', '--name-only', hostSha, cliSha, '--',
    'src', 'adapters', 'spec', 'moon.mod', 'moon.lock', 'toolchain.json', 'package-lock.json',
    ...CLIENT_PACKAGES.map(name => `packages/${name}`)], {cwd: root, encoding: 'utf8'}).trim();
}


async function pack(directory: string, output: string, productMembers?: ProductMembers) {
  const json = parseNpmPackJson(execFileSync('npm', normalNpmPackJsonArgs(['pack', '--json', '--pack-destination', output,
    '--cache', join(output, '.npm-cache')]), {cwd: directory, encoding: 'utf8', timeout: 60_000,
    env: {...process.env, npm_config_ignore_scripts: 'false'}}));
  type PackItem = {name: string; version: string; filename: string};
  const result: PackItem[] = Array.isArray(json) ? json : Object.values(json as Record<string, PackItem>); assert.equal(result.length, 1);
  const item = result[0], bytes = await readFile(join(output, item.filename));
  return {name: item.name, version: item.version, file: item.filename, bytes: bytes.length, sha256: hash(bytes),
    integrity: `sha512-${hash(bytes, 'sha512', 'base64')}`, files: await inventory(directory),
    ...(productMembers ? {productMembers} : {})};
}

export function admitNativeReleaseCohort(value: Cohort) {
  assert(value && typeof value === 'object' && !Array.isArray(value), 'Supply an explicit Native release cohort');
  exact(value, ['packageVersion', 'registry', 'access', 'tag']);
  releaseVersion(value.packageVersion);
  assert.notEqual(value.packageVersion, '0.0.1', 'The published placeholder remains immutable');
  assert.equal(value.registry, 'https://registry.npmjs.org/');
  assert.equal(value.access, 'public');
  admitReleaseChannel(value.tag);
  return structuredClone(value);
}

// Apply only package metadata to an isolated clone; this does not choose a
// number, modify source metadata or qualify a platform/profile for publication.
export function nativeReleaseMetadata<Metadata extends LauncherMetadata>(original: Metadata, selected: Cohort) {
  const cohort = admitNativeReleaseCohort(selected);
  assert.equal(original.name, 'actql');
  assert.equal(original.scripts, undefined);
  return {...structuredClone(original), version: cohort.packageVersion,
    publishConfig: {registry: cohort.registry, access: cohort.access}};
}

export async function prepareNativeCliRelease(destination: string, artifacts: readonly string[], selected: Cohort) {
  return prepareNativeCliProfile(destination, artifacts, selected, false);
}

// Profile selection after original artifact admission, not another receipt or
// a substitute for installed acceptance. Generic/Remote preparation is intact.
export function requireLinuxLocalReleaseArtifacts(records: readonly Pick<Artifact, 'platform' | 'localRuntime'>[]) {
  assert(Array.isArray(records));
  const linux = records.filter(record => record.platform === 'linux-x64-gnu');
  assert.equal(linux.length, 1, 'Local release selection requires one Linux x64 artifact');
  assert(linux[0].localRuntime && typeof linux[0].localRuntime === 'object',
    'Local release selection cannot use a Remote-only Linux artifact');
  for (const record of records) assert(record.localRuntime && typeof record.localRuntime === 'object',
    'Every included platform in a Local release requires its admitted Local payload');
}

export async function prepareNativeCliLocalRelease(destination: string, artifacts: readonly string[], selected: Cohort) {
  return prepareNativeCliProfile(destination, artifacts, selected, true);
}

async function prepareNativeCliProfile(destination: string, artifacts: readonly string[], selected: Cohort,
  requireLinuxLocal: boolean): Promise<NativeReleaseManifest> {
  const cohort = admitNativeReleaseCohort(selected);
  const source = checkoutState(repository); assert(source.clean, 'CLI release requires clean source HEAD');
  const checkedSource = await checkInterfaceOwners(repository, {manifests: ['packages/native-cli/package.json']});
  const records = await Promise.all(artifacts.map(path => admitNativeArtifact(resolve(path), source.revision)));
  assert(records.length > 0 && records.length <= 2); assert.equal(new Set(records.map(v => v.platform)).size, records.length);
  if (requireLinuxLocal) requireLinuxLocalReleaseArtifacts(records);
  const pinDigest = hash(await readFile(join(repository, 'toolchain.json')));
  for (const record of records) assert.equal(record.toolchainPinSha256, pinDigest);
  for (const record of records) {
    requireNativePackageVersion(record, cohort.packageVersion);
    exact(record.notices, ['MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE']);
    for (const [filename, digest] of Object.entries(record.notices as Record<string, unknown>)) {
      assert.equal(digest, hash(await readFile(join(repository, 'packages/local-node', filename))));
    }
  }
  const cli = nativeReleaseMetadata(JSON.parse(await readFile(join(repository, 'packages/native-cli/package.json'), 'utf8')) as LauncherMetadata, cohort);
  destination = resolve(destination); await mkdir(destination);
  const scratch = await mkdtemp(join(destination, '.stage-')), packages: NativePackage[] = [],
    mapping: Record<string, PlatformRecord> = {};
  try {
    for (const [index, record] of records.entries()) {
      const name = `@actql/cli-${record.platform}`, directory = join(scratch, record.platform);
      await mkdir(join(directory, 'bin'), {recursive: true});
      const target: {os: string; cpu: string; libc?: string} = platforms[record.platform as keyof typeof platforms];
      const metadata = {name, version: cli.version, description: 'ActQL Native Remote transport executable',
        license: 'Apache-2.0', os: [target.os], cpu: [target.cpu], ...(target.libc ? {libc: [target.libc]} : {}),
        files: ['bin', 'artifact.json', 'LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE', PRODUCT_MEMBERS_FILE,
          ...(record.localRuntime ? ['local-runtime.json', 'lib', 'data', 'licenses'] : [])],
        repository: {type: 'git', url: 'git+https://github.com/actql/actql.git'}, publishConfig: cli.publishConfig};
      await writeFile(join(directory, 'package.json'), `${JSON.stringify(metadata, null, 2)}\n`);
      await writeFile(join(directory, 'artifact.json'), `${JSON.stringify(record, null, 2)}\n`);
      await copyFile(join(resolve(artifacts[index]), 'actql-native-client'), join(directory, 'bin/actql-native-client'));
      await chmod(join(directory, 'bin/actql-native-client'), 0o755);
      await copyFile(join(repository, 'LICENSE'), join(directory, 'LICENSE'));
      for (const filename of Object.keys(record.notices as object)) await copyFile(join(repository, 'packages/local-node', filename), join(directory, filename));
      if (record.localRuntime) {
        const root = resolve(artifacts[index]);
        const local = admitInstalledLocalRuntime({root,
          expected: {sourceSha: record.sourceSha, platform: record.platform, localRuntimeSha256: record.localRuntime.sha256}, metadata: record.localRuntime});
        await copyFile(join(root, 'local-runtime.json'), join(directory, 'local-runtime.json'));
        for (const child of ['lib', 'data', 'licenses']) await mkdir(join(directory, child));
        for (const item of [...local.libraries, ...local.assets, ...local.licenses]) await copyFile(join(root, item.path), join(directory, item.path));
        admitInstalledLocalRuntime({root: directory,
          expected: {sourceSha: record.sourceSha, platform: record.platform, localRuntimeSha256: record.localRuntime.sha256}, metadata: record.localRuntime});
      }
      const productMembers = await stageProductMembers(directory, {
        sourceSha: source.revision, platform: record.platform, packageName: name});
      await checkStagedNativeCliInterfaces({repository, directory, source: source.revision, checkedSource, artifact: record});
      packages.push(await pack(directory, destination, productMembers));
      mapping[record.platform] = {package: name, sourceSha: record.sourceSha, binarySha256: record.binarySha256, binaryBytes: record.binaryBytes,
        ...(record.localRuntime ? {localRuntimeSha256: record.localRuntime.sha256} : {}), productMembers};
    }
    const directory = join(scratch, 'cli'); await mkdir(join(directory, 'bin'), {recursive: true});
    cli.optionalDependencies = Object.fromEntries(Object.values(mapping).map(v => [v.package, cli.version]));
    const memberPlatform = launcherMemberPlatform(records);
    if (memberPlatform !== undefined) cli.files = [...new Set([...cli.files, PRODUCT_MEMBERS_FILE])];
    await mkdir(join(directory, 'lib'));
    for (const {member, source: path} of nativeCliPackageInputs(repository)!.copies) await copyFile(join(repository, path), join(directory, member));
    await chmod(join(directory, 'bin/actql.mjs'), 0o755);
    await copyFile(join(repository, 'LICENSE'), join(directory, 'LICENSE'));
    await writeFile(join(directory, 'package.json'), `${JSON.stringify(cli, null, 2)}\n`);
    await writeFile(join(directory, 'platforms.json'), `${JSON.stringify(mapping, null, 2)}\n`);
    const productMembers = memberPlatform === undefined ? undefined : await stageProductMembers(directory, {
      sourceSha: source.revision, platform: memberPlatform, packageName: 'actql'});
    await checkStagedNativeCliInterfaces({repository, directory, source: source.revision, checkedSource});
    packages.push(await pack(directory, destination, productMembers));
    assert.deepEqual(checkoutState(repository), source);
    const manifest = {version: 'actql-native-cli-release/0.1', sourceSha: source.revision,
      preparedAt: new Date().toISOString(), recipeSha256: hash(await readFile(join(repository, 'scripts/native-cli-release.mjs'))),
      cohort,
      platforms: mapping, artifacts: records, packages};
    await writeFile(join(destination, 'release.json'), `${JSON.stringify(manifest, null, 2)}\n`, {flag: 'wx'});
    return manifest;
  } finally {await rm(scratch, {recursive: true});}
}

export function admitNativeReleaseManifest(manifest: NativeReleaseManifest) {
  exact(manifest, ['version', 'sourceSha', 'preparedAt', 'recipeSha256', 'cohort', 'platforms', 'artifacts', 'packages']);
  assert.equal(manifest.version, 'actql-native-cli-release/0.1'); assert.match(manifest.sourceSha, /^[a-f0-9]{40}$/u);
  admitNativeReleaseCohort(manifest.cohort);
  const names = Object.keys(manifest.platforms); assert(names.length > 0 && names.length <= 2);
  assert.deepEqual(manifest.packages.map(v => v.name), [...names.map(key => `@actql/cli-${key}`), 'actql']);
  assert.deepEqual(manifest.artifacts.map(v => v.platform), names);
  return structuredClone(manifest);
}

export async function verifyNativeCliRelease(directory: string) {
  return verifyNativeCliReleaseOriginal(directory);
}

// One lexical admission belongs to this original sequential campaign only.
// The ordinary exported verifier never consumes it, and all Source checks still
// run for every consumer. No serialized report or matching SHA can create it.
export async function withNativeMockReleaseAdmission<Value>(directory: string, action: (admission: Admission) => Value,
  {sourceRepository = repository, controller = repository, checkSource = checkInterfaceOwners}:
  {sourceRepository?: string; controller?: string; checkSource?: typeof checkInterfaceOwners} = {}) {
  directory = resolve(directory);
  const manifest = admitNativeReleaseManifest(JSON.parse(await readFile(join(directory, 'release.json'), 'utf8')));
  const source = checkoutState(sourceRepository);
  assert(source.clean && source.revision === manifest.sourceSha, 'Native Mock campaign requires its exact clean source');
  const assertInputs = retainNativeMockCampaignInputs({repository: sourceRepository, controller,
    files: [join(directory, 'release.json'), ...manifest.packages.map(item => {
      assert.equal(item.file, `${item.name.replace('@', '').replace('/', '-')}-${item.version}.tgz`);
      return join(directory, item.file);
    })]});
  const retained = {source, manifest: JSON.stringify(manifest), assertInputs, checked: undefined} as RetainedAdmission;
  let active = true, pending = false;
  retained.assertActive = () => assert(active, 'Closed Native Mock release admission');
  const assertCurrent = () => {
    assert(active, 'Closed Native Mock release admission');
    try {
      assertInputs();
      assert.deepEqual(checkoutState(sourceRepository), source, 'Native Mock campaign source changed');
    } catch (error) {active = false; throw error;}
  };
  const verify = async () => {
    assert(active && !pending, 'Closed or overlapping Native Mock release admission');
    pending = true;
    try {
      assertCurrent();
      const manifest = await verifyNativeCliReleaseOriginal(directory, {repository: sourceRepository, retained, checkSource});
      retained.assertActive();
      return manifest;
    } catch (error) {
      // A failed/changed cohort stops this original campaign. It is never a
      // cache miss permitting another candidate or a replayed consumer.
      active = false;
      throw error;
    } finally {pending = false;}
  };
  const original = Object.freeze({verify, assertCurrent});
  nativeMockAdmissions.set(original, {directory});
  try {return await action(original);}
  finally {active = false; nativeMockAdmissions.delete(original);}
}

// The consumer receives the same original callback object. A copied bag of
// methods, matching manifest or foreign directory cannot select this entrance.
export function originalNativeMockReleaseAdmission(admission: unknown, directory: string): Admission {
  const original = nativeMockAdmissions.get(admission as object);
  assert(original && original.directory === resolve(directory), 'Untrusted or foreign Native Mock release admission');
  return admission as Admission;
}

async function verifyNativeCliReleaseOriginal(directory: string,
  {repository: sourceRepository = repository, retained, checkSource = checkInterfaceOwners}:
  {repository?: string; retained?: RetainedAdmission; checkSource?: typeof checkInterfaceOwners} = {}) {
  const repository = sourceRepository;
  // Diagnostic DATA only. Ordinary calls retain full verification. Scoped
  // calls distinguish retained artifact admission from fresh Source checking;
  // unavailable timing or a failed stderr write cannot mask the primary result.
  let observedStart: bigint | undefined, sourceWallNs: number | undefined, sourceCompleted = false, completed = false, reused = false;
  try {if (process.env.ACTQL_CI_NATIVE_RELEASE_PHASES === '1') observedStart = process.hrtime.bigint();} catch {}
  try {
    const manifest = admitNativeReleaseManifest(JSON.parse(await readFile(join(directory, 'release.json'), 'utf8')));
    const names = Object.keys(manifest.platforms);
    const source = checkoutState(repository);
    assert(source.clean, 'CLI interface verification requires clean checked source');
    const checkedSource = await checkSource(repository, {manifests: ['packages/native-cli/package.json']});
    if (retained) {
      retained.assertActive();
      assert.deepEqual(source, retained.source, 'Native Mock campaign source changed');
      assert.equal(JSON.stringify(manifest), retained.manifest, 'Native Mock release manifest changed');
      // Consume a fresh real checker instance, never its public report as proof.
      checkedOriginalInterface(repository, 'packages/native-cli/bin/actql.mjs', checkedSource);
      const current = JSON.stringify({modules: checkedSource.modules, runtimeBindings: checkedSource.runtimeBindings,
        roots: checkedSource.roots, generated: checkedSource.generated, artifacts: checkedSource.artifacts});
      if (retained.checked !== undefined) {
        assert.equal(current, retained.checked, 'Native Mock original interface/binding subjects changed');
        reused = true;
      }
    }
    sourceCompleted = true;
    try {if (observedStart !== undefined) sourceWallNs = Number(process.hrtime.bigint() - observedStart);} catch {}
    if (!reused) {
      const scratch = await mkdtemp(join(directory, '.verify-'));
      try {
        for (const item of manifest.packages) {
          assert.equal(item.version, manifest.cohort.packageVersion);
          assert.equal(item.file, `${item.name.replace('@', '').replace('/', '-')}-${item.version}.tgz`);
          const bytes = await readFile(join(directory, item.file));
          assert.equal(bytes.length, item.bytes); assert.equal(hash(bytes), item.sha256);
          assert.equal(`sha512-${hash(bytes, 'sha512', 'base64')}`, item.integrity);
          const payload = await unpack(join(directory, item.file), join(scratch, item.name.replace('/', '-')));
          assert.deepEqual(await inventory(payload), item.files);
          const metadata = JSON.parse(await readFile(join(payload, 'package.json'), 'utf8'));
          assert.equal(metadata.name, item.name); assert.equal(metadata.version, item.version); assert.equal(metadata.private, undefined);
          assert.equal(metadata.scripts, undefined); assert.equal(metadata.license, 'Apache-2.0');
          if (item.name === 'actql') {
            if (item.productMembers !== undefined) {
              const platform = launcherMemberPlatform(manifest.artifacts);
              assert(platform !== undefined);
              await verifyStagedProductMembers(payload, {
                sourceSha: manifest.sourceSha, platform, packageName: item.name}, item.productMembers);
            }
            assert.deepEqual(metadata.bin, {actql: 'bin/actql.mjs'});
            assert.deepEqual(metadata.optionalDependencies, Object.fromEntries(names.map(key => [`@actql/cli-${key}`, item.version])));
            assert.deepEqual(JSON.parse(await readFile(join(payload, 'platforms.json'), 'utf8')), manifest.platforms);
            await checkStagedNativeCliInterfaces({repository, directory: payload, source: manifest.sourceSha, checkedSource});
          } else {
            const key = item.name.slice('@actql/cli-'.length),
              target: {os: string; cpu: string; libc?: string} = platforms[key as keyof typeof platforms]; assert(target);
            assert.deepEqual(metadata.os, [target.os]); assert.deepEqual(metadata.cpu, [target.cpu]);
            assert.deepEqual(metadata.libc, target.libc ? [target.libc] : undefined);
            const record = JSON.parse(await readFile(join(payload, 'artifact.json'), 'utf8')) as Artifact;
            assert.deepEqual(record, manifest.artifacts.find(v => v.platform === key)!);
            if (item.productMembers !== undefined) await verifyStagedProductMembers(payload, {
              sourceSha: manifest.sourceSha, platform: key, packageName: item.name}, item.productMembers);
            const checked = await checkStagedNativeCliInterfaces({repository, directory: payload,
              source: manifest.sourceSha, checkedSource, artifact: record});
            // Preserve the full post-await material reinspection in its actual
            // installed layout; no duplicate producer-layout binary is needed.
            assert.deepEqual(await admitInstalledNativeArtifactMaterial(payload, manifest.sourceSha), checked.artifactMaterial,
              'Native artifact/runtime changed during interface verification');
            exact(record.notices, ['MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE']);
            for (const [filename, digest] of Object.entries(record.notices as Record<string, unknown>))
              assert.equal(digest, hash(await readFile(join(payload, filename))));
            assert.deepEqual(manifest.platforms[key], {package: item.name, sourceSha: record.sourceSha,
              binarySha256: record.binarySha256, binaryBytes: record.binaryBytes,
              ...(record.localRuntime ? {localRuntimeSha256: record.localRuntime.sha256} : {}),
              ...(item.productMembers ? {productMembers: item.productMembers} : {})});
          }
        }
      } finally {await rm(scratch, {recursive: true});}
    }
    if (retained) {
      retained.assertActive();
      retained.assertInputs();
      retained.checked ??= JSON.stringify({modules: checkedSource.modules, runtimeBindings: checkedSource.runtimeBindings,
        roots: checkedSource.roots, generated: checkedSource.generated, artifacts: checkedSource.artifacts});
    }
    assert.deepEqual(checkoutState(repository), source, 'CLI checked source changed during verification');
    completed = true;
    return manifest;
  } finally {
    try {
      if (observedStart !== undefined) {
        const total = Number(process.hrtime.bigint() - observedStart);
        if (Number.isSafeInteger(total) && total >= 0 && (!sourceCompleted ||
          Number.isSafeInteger(sourceWallNs) && sourceWallNs! >= 0 && sourceWallNs! <= total)) {
          console.error('ACTQL_NATIVE_RELEASE_PHASES ' + JSON.stringify({
            sourcePreparation: {state: sourceCompleted ? 'completed' : 'failed', wallNs: sourceCompleted ? sourceWallNs : total},
            artifactVerification: sourceCompleted
              ? {state: completed ? (reused ? 'retained' : 'completed') : 'failed', wallNs: total - sourceWallNs!} : {state: 'unexecuted'},
          }));
        }
      }
    } catch { /* Optional observation never changes verification or cleanup. */ }
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, input, ...tail] = process.argv.slice(2);
  assert(input && ['prepare', 'prepare-local', 'verify', 'plan', '--publish'].includes(command),
    'usage: native-cli-release.mjs prepare|prepare-local <new-directory> <explicit-cohort-json> <artifact-directories...> | verify|plan <directory>');
  if (command === '--publish') refuseUnconfiguredPublication();
  const preparation = command === 'prepare' || command === 'prepare-local';
  assert(preparation ? tail.length >= 2 : tail.length === 0,
    'Native preparation requires an explicit cohort file and artifact directories');
  const directory = resolve(input);
  const prepare = command === 'prepare-local' ? prepareNativeCliLocalRelease : prepareNativeCliRelease;
  const manifest = preparation ? await prepare(directory, tail.slice(1),
    JSON.parse(await readFile(resolve(tail[0]), 'utf8'))) : await verifyNativeCliRelease(directory);
  if (command === '--publish') {
    execFileSync('npm', ['whoami', '--registry', manifest.cohort.registry, '--fetch-timeout=15000', '--fetch-retries=0'], {stdio: 'inherit', timeout: 20_000});
    console.log(JSON.stringify(await publishPackageRelease({directory, verify: verifyNativeCliRelease,
      executePublish({file, registry, access, tag}) {execFileSync('npm', ['publish', file, '--ignore-scripts', '--registry', registry,
        '--access', access, '--tag', tag], {stdio: 'inherit', timeout: 180_000});}}), null, 2));
  } else console.log(JSON.stringify(command === 'plan' ? await publicationPlan(manifest) : {
    sourceSha: manifest.sourceSha, platforms: manifest.platforms,
    packages: manifest.packages.map(({name, version, file, sha256}) => ({name, version, file, sha256}))}, null, 2));
}
