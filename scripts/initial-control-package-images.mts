import {createHash} from 'node:crypto';
import {existsSync, lstatSync, readFileSync, readdirSync, realpathSync} from 'node:fs';
import {dirname, isAbsolute, join} from 'node:path';
import {createRequire} from 'node:module';
import {admitCohort, releasePackageMetadata} from './package-release.mjs';
import {ordinaryCompatibilityNode} from './build-node-directory-native.mjs';

import type {BinaryLike} from 'node:crypto';

type Cohort = ReturnType<typeof admitCohort>;
// Unchecked package and producer DATA; the original runtime checks remain below.
type Manifest = Parameters<typeof releasePackageMetadata>[0] & {
  peerDependenciesMeta?: Record<string, {optional?: unknown}>; exports?: unknown};
type ImageFact = {path: string; bytes: number; sha256: string;
  npmRelease?: {version: string; bytes: number; sha256: string}};
type Dependency = {name: string; package: number} | {name: string; local: true};
type PackageImage = {name: string; version: string; releaseVersion?: string;
  images: ImageFact[]; dependencies: Dependency[]};
type Engine = {node: string; v8: string; openssl: string; platform: string; arch: string;
  libraries: NodeJS.ProcessVersions | Record<string, string>};
type EngineProfile = {engine?: Engine & {eager: boolean}; ordinaryEngine: Engine & {eager: boolean}};
type NativeDescriptor = {version: string; source?: {packageVersion?: string}; targets: {
  platform: string; arch: string; engine: Engine; compatibilityEngine?: Engine;
  original: {platform: string; arch: string; binary: ImageFact};
  originalSource: string; originalSha256: string}[]};
type RenderOptions = {root: string; destination: string;
  inputs: {runtimeFiles: readonly string[]; buildInputs?: unknown};
  outputs: ReadonlyMap<string, Buffer>; nativeOutputs?: ReadonlyMap<string, Buffer>; compatibilityEngine?: Engine};

export const initialControlPackageOriginal = 'adapters/host-node/initial-control-package-original.cjs';
const digest = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');
const concrete = (path: unknown): path is string => typeof path === 'string' && !isAbsolute(path) &&
  !path.split('/').some(part => part === '..' || part === '.' || part === '') && !path.includes('\\');
const fail: (name: string) => never = name => { throw new Error(name); };
const fact = (path: string, bytes: Buffer): ImageFact => ({path, bytes: bytes.length, sha256: digest(bytes)});
// Bind the existing publication transform BEFORE packing, never normalize an
// installed manifest or infer a release version from it at startup. Every
// runtime and non-manifest Source retains its one exact byte/hash identity.
function manifestFact(path: string, bytes: Buffer, cohort: Cohort | undefined) {
  const result = fact(path, bytes);
  if (path !== 'package.json' || cohort === undefined) return result;
  const original = JSON.parse(bytes as unknown as string) as Manifest, name = original.name?.replace(/^@actql\//u, '');
  if (original.name !== '@actql/' + name || !cohort.packages.includes(name)) return result;
  const released = Buffer.from(JSON.stringify(releasePackageMetadata(original, name, cohort), null, 2) + '\n');
  result.npmRelease = {version: cohort.packageVersion, bytes: released.length, sha256: digest(released)};
  return result;
}
const releaseVersion = (manifest: Manifest, cohort: Cohort | undefined) => cohort !== undefined &&
  cohort.packages.some(name => manifest.name === '@actql/' + name)
  ? {releaseVersion: cohort.packageVersion} : {};
// Generated nested DATA has no callable factory. Freeze each literal before
// entry so an escaped module-cache reference cannot rewrite the selected facts.
function frozenLiteral(value: unknown): string | undefined {
  if (Array.isArray(value)) return 'Object.freeze([' + value.map(frozenLiteral).join(',') + '])';
  if (value !== null && typeof value === 'object') {
    return 'Object.freeze({' + Object.entries(value).map(([key, child]) =>
      JSON.stringify(key) + ':' + frozenLiteral(child)).join(',') + '})';
  }
  return JSON.stringify(value);
}
function regularFile(root: string, path: string, code: string) {
  if (!concrete(path)) fail('InvalidInitialControlImage');
  const parts = path.split('/');
  for (let index = 0; index < parts.length; index++) {
    const info = lstatSync(join(root, ...parts.slice(0, index + 1)));
    if (index === parts.length - 1 ? !info.isFile() : !info.isDirectory()) fail(code);
  }
  return readFileSync(join(root, path));
}

function publicCodeFiles(root: string, manifest: Manifest, cohort: Cohort | undefined) {
  const files = new Map<string, Buffer>();
  function walk(path: string) {
    if (!concrete(path)) fail('InvalidInitialControlPackagePath');
    const info = lstatSync(join(root, path));
    if (info.isSymbolicLink()) fail('AliasedInitialControlPackageImage');
    if (info.isDirectory()) {
      for (const name of readdirSync(join(root, path)).sort()) {
        if (name !== 'node_modules') walk(path + '/' + name);
      }
    } else if (!info.isFile()) fail('NonregularInitialControlPackageImage');
    else if (/\.(?:[cm]?js|json|wasm)$/u.test(path)) files.set(path, readFileSync(join(root, path)));
  }
  if (!Array.isArray(manifest.files) && manifest.name.startsWith('@actql/')) fail('MissingInitialControlPackageFiles');
  if (!manifest.name.startsWith('@actql/')) {
    // These are already installed third-party package contents. Include all
    // executable/JSON/wasm files, not an incomplete interpretation of npm globs.
    for (const name of readdirSync(root).sort()) if (name !== 'node_modules') walk(name);
  } else for (const selected of manifest.files!) {
    const path = selected.endsWith('/') ? selected.slice(0, -1) : selected;
    // Type declarations, readmes and licenses are not executable image inputs.
    if (/\.(?:d\.[cm]?ts|md)$/u.test(path) || !existsSync(join(root, path))) continue;
    walk(path);
  }
  files.set('package.json', readFileSync(join(root, 'package.json')));
  return [...files].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
    .map(([path, bytes]) => manifestFact(path, bytes, cohort));
}

function packageRoot(name: string, from: string) {
  const require = createRequire(join(from, 'package.json'));
  let file;
  try { file = require.resolve(name); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'MODULE_NOT_FOUND' && (error as NodeJS.ErrnoException).code !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') throw error;
    // A declared type-only package can have no runtime export. Its actual
    // nearest package manifest still belongs to this dependency selection.
    for (const directory of require.resolve.paths(name) ?? []) {
      const candidate = join(directory, name, 'package.json');
      if (existsSync(candidate) && JSON.parse(readFileSync(candidate, 'utf8')).name === name) {
        return realpathSync(dirname(candidate));
      }
    }
    return undefined;
  }
  let at = dirname(realpathSync(file));
  for (;;) {
    const path = join(at, 'package.json');
    if (existsSync(path) && JSON.parse(readFileSync(path, 'utf8')).name === name) return at;
    const parent = dirname(at);
    if (parent === at) fail('MissingInitialControlDependencyPackage');
    at = parent;
  }
}

// Use the installed package's declared dependency graph, not a parallel list of
// Connector modules. Paths in the recipe are package-relative; build locations
// and operational receipts never enter the published image inventory.
function dependencyImages(root: string, destination: string, localManifest: Manifest, cohort: Cohort | undefined) {
  const packages: PackageImage[] = [], roots = new Map<string, number>();
  function rollback(before: number) {
    packages.length = before;
    for (const [directory, index] of roots) if (index >= before) roots.delete(directory);
  }
  function exactVersion(manifest: Manifest, expectedVersion: string | undefined, name: string) {
    if (expectedVersion !== undefined && /^[0-9]+\.[0-9]+\.[0-9]+(?:[-+].*)?$/u.test(expectedVersion) &&
        manifest.version !== expectedVersion) fail('WrongInitialControlDependencyVersion:' + name);
  }
  function collect(name: string, directory: string, expectedVersion?: string): number {
    directory = realpathSync(directory);
    const manifest = JSON.parse(readFileSync(join(directory, 'package.json'), 'utf8')) as Manifest;
    if (manifest.name !== name || typeof manifest.version !== 'string') fail('WrongInitialControlDependency');
    exactVersion(manifest, expectedVersion, name);
    if (roots.has(directory)) return roots.get(directory)!;
    const index = packages.length;
    roots.set(directory, index);
    const item: PackageImage = {name, version: manifest.version, ...releaseVersion(manifest, cohort),
      images: publicCodeFiles(directory, manifest, cohort), dependencies: []};
    packages.push(item);
    const dependencies = {...manifest.dependencies, ...manifest.peerDependencies};
    for (const dependency of Object.keys(dependencies).sort()) {
      if (manifest.peerDependenciesMeta?.[dependency]?.optional === true) continue;
      const resolved = packageRoot(dependency, directory);
      if (resolved === undefined) fail('UnpreparedInitialControlDependency:' + dependency);
      item.dependencies.push({name: dependency, package: collect(dependency, resolved, dependencies[dependency])});
    }
    return index;
  }
  const bindings: Dependency[] = [];
  for (const name of Object.keys(localManifest.dependencies ?? {}).sort()) {
    // Public ActQL dependencies are Source-owned packages in the same normal
    // build. Their actual installed correspondence is checked again in preload.
    const own = name.startsWith('@actql/') ? join(root, 'packages', name.slice('@actql/'.length)) : undefined;
    const directory = own !== undefined && existsSync(join(own, 'package.json')) ? own : packageRoot(name, destination);
    if (directory === undefined) fail('UnpreparedInitialControlDependency:' + name);
    bindings.push({name, package: collect(name, directory, localManifest.dependencies![name])});
  }
  // This is the existing startup's optional SDK resolution, not a new public
  // dependency or a Provider invocation. Missing coverage refuses its adoption.
  const sdk = join(root, 'packages/provider-ai-sdk');
  let optionalSdk, optionalSdkCoverage = 'absent';
  if (existsSync(join(sdk, 'package.json'))) {
    const before = packages.length;
    try { optionalSdk = collect('@actql/provider-ai-sdk', sdk); optionalSdkCoverage = 'prepared'; }
    catch (error) {
      if (!(error as Error).message.startsWith('UnpreparedInitialControlDependency:')) throw error;
      rollback(before);
      optionalSdkCoverage = 'unprepared';
    }
  }
  // The standard Node facade is not a Local dependency. Capture its distinct
  // original Sources explicitly, without recursively including the generated
  // Local inventory in itself or treating a package name as a startup issuer.
  const node = join(root, 'packages/node');
  let publicNode: PackageImage | undefined, publicNodeCoverage = 'absent';
  if (existsSync(join(node, 'package.json'))) {
    const before = packages.length;
    try {
      const manifest = JSON.parse(readFileSync(join(node, 'package.json'), 'utf8')) as Manifest;
      if (manifest.name !== '@actql/node' || typeof manifest.version !== 'string') {
        fail('WrongInitialControlDependency');
      }
      const dependencies: Dependency[] = [];
      for (const name of Object.keys(manifest.dependencies ?? {}).sort()) {
        if (name === '@actql/local-node') {
          exactVersion(localManifest, manifest.dependencies![name], name);
          dependencies.push({name, local: true});
        } else {
          const directory = packageRoot(name, node);
          if (directory === undefined) fail('UnpreparedInitialControlDependency:' + name);
          dependencies.push({name, package: collect(name, directory, manifest.dependencies![name])});
        }
      }
      if (!dependencies.some(value => value.name === '@actql/local-node')) {
        fail('MissingInitialControlLocalDependency');
      }
      publicNode = {name: manifest.name, version: manifest.version, ...releaseVersion(manifest, cohort),
        images: publicCodeFiles(node, manifest, cohort), dependencies};
      publicNodeCoverage = 'prepared';
    } catch (error) {
      if (!(error as Error).message.startsWith('UnpreparedInitialControlDependency:')) throw error;
      rollback(before);
      publicNodeCoverage = 'unprepared';
    }
  }
  return {packages, bindings, optionalSdk, optionalSdkCoverage, publicNode, publicNodeCoverage};
}

// The caller supplies exactly the bytes it will publish after its ordinary
// import rewrite. Normal runtime assets are read from that same destination.
// This returns only generated Source; it cannot issue or price a scope.
export function renderInitialControlPackageOriginal({
  root, destination, inputs, outputs, nativeOutputs = new Map(), compatibilityEngine,
}: RenderOptions) {
  if (!(outputs instanceof Map) || !outputs.has(initialControlPackageOriginal)) {
    fail('MissingInitialControlPackageTemplate');
  }
  const absent = outputs.get(initialControlPackageOriginal)!;
  if (inputs.buildInputs !== undefined) return absent;
  const images = new Map(outputs);
  images.delete(initialControlPackageOriginal);
  // Native executable bytes are never UTF8 Source and must not pass through
  // the JS image loader. Their separate facts still do not authorize loading.
  const nativeImages: ImageFact[] = [];
  for (const [path, bytes] of nativeOutputs) {
    if (!concrete(path) || !path.startsWith('_build/native/')) fail('InvalidInitialControlNativeImage');
    if (path.endsWith('.node')) nativeImages.push(fact(path, bytes));
    else if (path === '_build/native/directory-original.json') images.set(path, bytes);
    else fail('InvalidInitialControlNativeImage');
  }
  nativeImages.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  let engineProfiles: EngineProfile[] | undefined, nativeReleaseVersion: string | undefined;
  const ordinaryCompatibilityProfile = (engine: Engine | undefined, platform: string, arch: string) => {
    if (engine?.node !== ordinaryCompatibilityNode || engine.platform !== platform || engine.arch !== arch ||
        ['node', 'v8', 'openssl'].some(name => typeof engine[name as 'node' | 'v8' | 'openssl'] !== 'string' ||
          engine[name as 'node' | 'v8' | 'openssl'] !== engine.libraries?.[name])) {
      fail('InvalidInitialControlNativeImage');
    }
    return {ordinaryEngine: {...engine, eager: false}};
  };
  const descriptorBytes = nativeOutputs.get('_build/native/directory-original.json');
  if (descriptorBytes !== undefined) {
    const descriptor = JSON.parse(descriptorBytes as unknown as string) as NativeDescriptor;
    if (descriptor.version === 'actql-node-directory-native-cohort/0.1') {
      nativeReleaseVersion = descriptor.source?.packageVersion;
      if (compatibilityEngine !== undefined || !Array.isArray(descriptor.targets) ||
          descriptor.targets.length !== 2 || nativeImages.length !== 2) fail('InvalidInitialControlNativeImage');
      const targets = new Set();
      engineProfiles = descriptor.targets.map(target => {
        const name = `${target.platform}-${target.arch}`, engine = target.engine;
        const path = name === 'darwin-arm64' ? '_build/native/directory-darwin-arm64.node'
          : name === 'linux-x64' ? '_build/native/local-files-linux-x64.node' : undefined;
        const original = target.original;
        if (path === undefined || targets.has(name) || engine?.platform !== target.platform ||
            engine?.arch !== target.arch || engine?.node !== '22.22.0' ||
            engine?.libraries?.node !== engine.node || engine?.libraries?.v8 !== engine.v8 ||
            engine?.libraries?.openssl !== engine.openssl ||
            original?.platform !== target.platform || original?.arch !== target.arch ||
            original?.binary?.path !== path || digest(Buffer.from(target.originalSource ?? '')) !== target.originalSha256 ||
            JSON.stringify(JSON.parse(target.originalSource)) !== JSON.stringify(original) ||
            !nativeImages.some(image => image.path === path && image.bytes === original.binary.bytes &&
              image.sha256 === original.binary.sha256)) fail('InvalidInitialControlNativeImage');
        targets.add(name);
        return {engine: {...engine, eager: true}, ordinaryEngine: {...engine, eager: false}};
      });
      engineProfiles.sort((a, b) => `${a.engine!.platform}-${a.engine!.arch}` <
        `${b.engine!.platform}-${b.engine!.arch}` ? -1 : 1);
      const compatibilityTargets = descriptor.targets.filter(target => target.compatibilityEngine !== undefined);
      if (compatibilityTargets.length !== 0 && compatibilityTargets.length !== 2) fail('InvalidInitialControlNativeImage');
      for (const {compatibilityEngine, platform, arch} of compatibilityTargets) {
        engineProfiles.push(ordinaryCompatibilityProfile(compatibilityEngine, platform, arch));
      }
    }
  }
  for (const file of inputs.runtimeFiles) {
    if (!concrete(file)) fail('InvalidInitialControlRuntimePath');
    const path = '_build/js/release/build/' + file, source = join(destination, path);
    if (!existsSync(source)) return absent;
    images.set(path, regularFile(destination, path, 'AliasedInitialControlRuntime'));
  }
  const manifestPath = join(destination, 'package.json');
  if (!existsSync(manifestPath)) return absent;
  const manifestBytes = regularFile(destination, 'package.json', 'AliasedInitialControlManifest');
  const manifest = JSON.parse(manifestBytes as unknown as string) as Manifest;
  const cohortPath = join(root, 'release/client-cohort.json');
  const cohort = existsSync(cohortPath) ? admitCohort(JSON.parse(readFileSync(cohortPath, 'utf8'))) : undefined;
  if (engineProfiles !== undefined && nativeReleaseVersion !== cohort?.packageVersion) {
    fail('InvalidInitialControlNativeImage');
  }
  images.set('package.json', manifestBytes);
  function exported(value: unknown): void {
    if (typeof value === 'string') {
      if (!value.startsWith('./') || !/\.[cm]?js$/u.test(value)) return;
      const path = value.slice(2);
      if (!concrete(path)) fail('InvalidInitialControlPublicImage');
      if (images.has(path)) return;
      images.set(path, regularFile(destination, path, 'AliasedInitialControlPublicImage'));
    } else if (value !== null && typeof value === 'object') {
      for (const child of Object.values(value)) exported(child);
    }
  }
  exported(manifest.exports);
  // Private root-level implementation modules participate in the SAME normal
  // package payload even when they are not public export subpaths. In
  // particular, a pre-entry facade dispatch cannot be an uncaptured dependency.
  for (const path of manifest.files ?? []) {
    if (typeof path === 'string' && !path.includes('/') && /\.[cm]?js$/u.test(path)) {
      exported('./' + path);
    }
  }
  const dependencies = dependencyImages(root, destination, manifest, cohort);
  const facts = [...images].sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0)
    .map(([path, bytes]) => {
      if (!concrete(path)) fail('InvalidInitialControlImage');
      return manifestFact(path, bytes, cohort);
    });
  // Preserve the legacy profile and the exact process observations. A
  // compatibility observation attests ordinary startup only.
  const buildEngine = {node: process.versions.node, v8: process.versions.v8,
    openssl: process.versions.openssl, platform: process.platform, arch: process.arch,
    libraries: {...process.versions}};
  const engine = engineProfiles?.[0].engine ?? {...buildEngine, eager: true};
  const ordinaryEngine = engineProfiles?.[0].ordinaryEngine ?? {...buildEngine, eager: false};
  if (compatibilityEngine !== undefined) {
    if (nativeImages.length !== 1) fail('InvalidInitialControlNativeImage');
    engineProfiles = [{engine, ordinaryEngine},
      ordinaryCompatibilityProfile(compatibilityEngine, buildEngine.platform, buildEngine.arch)];
  }
  const recipe = {engine, ordinaryEngine,
  ...(engineProfiles === undefined ? {} : {engineProfiles}),
  images: facts, nativeImages, packages: dependencies.packages, dependencies: dependencies.bindings,
  localVersion: manifest.version,
  ...(releaseVersion(manifest, cohort).releaseVersion === undefined ? {} : {localReleaseVersion: cohort!.packageVersion}),
  optionalSdk: dependencies.optionalSdk ?? null, optionalSdkCoverage: dependencies.optionalSdkCoverage,
  publicNode: dependencies.publicNode ?? null, publicNodeCoverage: dependencies.publicNodeCoverage,
  sourceBytes: facts.reduce((sum, value) => sum + value.bytes, 0),
  localPublicModule: 'index.mjs',
  hostModule: 'adapters/host-node/embedded-local.mjs',
  hostValidator: 'assertInitialControlHostPreparation'};
  return Buffer.from("'use strict';\n\n// Generated by the normal Local package builder from its exact selected images.\n// Source inventory only; the actual selected preload remains the operational issuer.\nmodule.exports = Object.freeze({imageInventory:" +
    frozenLiteral(recipe) + '});\n');
}
