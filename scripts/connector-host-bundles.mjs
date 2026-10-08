// Shared build-time Host declarations; no runtime discovery or provider imports.
import {readFileSync, existsSync, lstatSync, realpathSync} from 'node:fs';
import {dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {connectorManifestSelection} from './connector-manifest-selection.mjs';
import {validInstalledEffectIdentityProfile, validInstalledResponseHeaders}
  from '../adapters/host-common/installed-connector-declaration.mjs';
import {adapterModuleGraph} from './adapter-module-graph.mjs';

// Installed Host bindings. A connector that the standard Host can install
// for Source and/or Effect declares, in its own `host-bundle.json`, the Host profile
// version it answers to, the module exporting its installation entries, its
// registration/revision, its compiled provider bundle and the response
// header names its drivers read. The common Host selects one entry by the
// installed profile's version; it never branches on a provider name.
const hostBundleKeys = ['installation'];
const installationKeys = ['registration', 'responseHeaders', 'revision'];
const optionalInstallationKeys = ['assets', 'effect', 'providerBundle', 'source'];
const sourceKeys = ['exports', 'module', 'profileVersion'];
const sourceExports = ['check', 'identityParts', 'load', 'publish'];
const requiredSourceExports = ['check', 'identityParts', 'load'];

const sameKeys = (value, keys) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join() === keys.join();

const safeRelativePath = value => typeof value === 'string' &&
  /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/.test(value) &&
  value.split('/').every(part => part !== '.' && part !== '..');

function ownedFile(root, path, invalid) {
  if (!safeRelativePath(path)) throw invalid();
  let current = resolve(root);
  const parts = path.split('/');
  for (let index = 0; index < parts.length; index++) {
    current = join(current, parts[index]);
    if (!existsSync(current)) throw invalid();
    const info = lstatSync(current);
    if (info.isSymbolicLink() ||
        !(index === parts.length - 1 ? info.isFile() : info.isDirectory())) throw invalid();
  }
  return current;
}

export function moduleSpecifier(output, path) {
  const value = relative(dirname(output), path);
  if (isAbsolute(value)) throw new Error('UnsupportedExternalModuleVolume');
  const encoded = value.split(sep).map(part =>
    encodeURIComponent(part).replaceAll('%40', '@')).join('/');
  return encoded.startsWith('./') || encoded.startsWith('../') ? encoded : './' + encoded;
}

// An explicit resolver passes its already-read declaration and owned path
// resolvers. Both layouts use these same semantic checks.
export function checkHostBundle(root, name, path, options = {}) {
  const manifest = Object.hasOwn(options, 'manifest')
    ? options.manifest : JSON.parse(readFileSync(path, 'utf8'));
  const invalid = reason => new Error(`Invalid Host bundle manifest (${reason}): ${path}`);
  const declaredKeys = manifest?.installation !== null && typeof manifest?.installation === 'object'
    ? Object.keys(manifest.installation) : [];
  if (!sameKeys(manifest, hostBundleKeys) ||
      !sameKeys(Object.fromEntries(declaredKeys.filter(key => !optionalInstallationKeys.includes(key))
        .map(key => [key, true])), installationKeys) ||
      declaredKeys.some(key => !installationKeys.includes(key) && !optionalInstallationKeys.includes(key))) {
    throw invalid('keys');
  }
  const {registration, revision, providerBundle, responseHeaders, source, effect, assets = []} = manifest.installation;
  if (source === undefined && effect === undefined) throw invalid('Host roles');
  if (registration !== name || !/^[a-z][a-z0-9_]*$/.test(name)) throw invalid('registration');
  if (typeof revision !== 'string' || !new RegExp(`^${name}/\\d+\\.\\d+$`).test(revision)) throw invalid('revision');
  if (providerBundle !== undefined) {
    if (typeof providerBundle !== 'string' ||
        !new RegExp(`^connectors/${name}/[a-z][a-z0-9_]*$`).test(providerBundle)) throw invalid('providerBundle');
    const bundlePackage = options.resolveProviderPackage === undefined
      ? join(root, 'src', providerBundle, 'moon.pkg')
      : options.resolveProviderPackage(providerBundle);
    if (!existsSync(bundlePackage)) throw invalid('providerBundle package');
    const bundleManifest = readFileSync(bundlePackage, 'utf8');
    if (!/^supported_targets = "js"$/m.test(bundleManifest) ||
        !/pkgtype\(kind: "foreign_library"\)/.test(bundleManifest)) throw invalid('providerBundle kind');
  }
  if (!validInstalledResponseHeaders(responseHeaders)) throw invalid('responseHeaders');
  const checkSection = (section, label) => {
    const prefix = label === 'source' ? '' : `${label} `;
    const {identityProfile, ...rest} = section ?? {};
    if (label === 'effect' && identityProfile !== undefined) {
      if (!validInstalledEffectIdentityProfile(identityProfile)) {
        throw invalid('effect identityProfile');
      }
      section = rest;
    }
    if (!sameKeys(section, sourceKeys)) throw invalid(`${label} keys`);
    if (typeof section.profileVersion !== 'string' ||
        !/^actql-installed-[a-z0-9-]+\/0\.1$/.test(section.profileVersion)) throw invalid(`${prefix}profileVersion`);
    if (typeof section.module !== 'string' ||
        !section.module.startsWith(`adapters/connectors/${name}/host/`) ||
        !/\.mjs$/.test(section.module) || !safeRelativePath(section.module) ||
        !existsSync(join(root, section.module))) throw invalid(`${prefix}module`);
    const modulePath = options.resolveFile === undefined
      ? ownedFile(root, section.module, () => invalid(`${prefix}module`))
      : options.resolveFile(section.module);
    if (section.exports === null || typeof section.exports !== 'object' || Array.isArray(section.exports) ||
        Object.keys(section.exports).some(key => !sourceExports.includes(key)) ||
        requiredSourceExports.some(key => !(key in section.exports))) throw invalid(`${prefix}exports keys`);
    const moduleText = readFileSync(modulePath, 'utf8');
    for (const [key, symbol] of Object.entries(section.exports)) {
      if (typeof symbol !== 'string' || !/^[A-Za-z_]\w*$/.test(symbol) ||
          !new RegExp(`^export (?:async )?function ${symbol}\\b|^export const ${symbol}\\b`, 'm').test(moduleText)) {
        throw invalid(`${prefix}export ${key}`);
      }
    }
    return {profileVersion: section.profileVersion, module: section.module, exports: {...section.exports},
      ...(options.resolveFile === undefined ? {} : {modulePath}),
      ...(identityProfile === undefined || label !== 'effect' ? {} : {identityProfile: {...identityProfile}})};
  };
  // Connector-owned declarations and explicitly listed physical I/O assets
  // share one finite inventory. A JS/Python installation needs no dummy Moon
  // provider bundle. Resolve actual ownership before packaging any asset.
  const prefix = `src/connectors/${name}/`;
  const connectorDirectory = join(root, prefix);
  const adapterPrefix = `adapters/connectors/${name}/`;
  const ownedAsset = asset => {
    const source = asset.startsWith(prefix) && asset.endsWith('.json');
    const physical = asset.startsWith(adapterPrefix) && /\.(?:py|in|lock|md)$/.test(asset);
    const contract = new RegExp(`^spec/contracts/actql-${name}-[a-z0-9-]+\\.json$`).test(asset);
    const owner = source ? connectorDirectory : physical ? join(root, adapterPrefix) :
      contract ? join(root, 'spec/contracts') : undefined;
    return owner !== undefined && existsSync(owner) && lstatSync(owner).isDirectory() &&
      realpathSync(owner) === resolve(realpathSync(root), source ? prefix :
        physical ? adapterPrefix : 'spec/contracts') &&
      realpathSync(join(root, asset)).startsWith(realpathSync(owner) + '/');
  };
  if (!existsSync(connectorDirectory) || !lstatSync(connectorDirectory).isDirectory() ||
      realpathSync(connectorDirectory) !== resolve(realpathSync(root), prefix) ||
      !Array.isArray(assets) || new Set(assets).size !== assets.length ||
      assets.some(asset => typeof asset !== 'string' || !safeRelativePath(asset) ||
        !existsSync(join(root, asset)) || !lstatSync(join(root, asset)).isFile() ||
        !ownedAsset(asset))) {
    throw invalid('assets');
  }
  const assetSources = assets.map(asset => ({path: asset, sourcePath:
    options.resolveFile === undefined
      ? ownedFile(root, asset, () => invalid('assets')) : options.resolveFile(asset)}));
  const checkedSource = source === undefined ? undefined : checkSection(source, 'source');
  const checkedEffect = effect === undefined ? undefined : checkSection(effect, 'effect');
  if (checkedEffect !== undefined && checkedEffect.profileVersion === checkedSource?.profileVersion) throw invalid('effect profileVersion');
  return {name, registration, revision, providerBundle, responseHeaders: [...responseHeaders], assets: [...assets],
    ...(options.resolveFile === undefined ? {} : {assetSources}),
    ...(checkedSource === undefined ? {} : {source: checkedSource}),
    ...(checkedEffect === undefined ? {} : {effect: checkedEffect})};
}

// Generation and distribution read exactly the same checked declarations.
// Selecting installed Host contributions does not require Compute support.
export function readHostBundles(root, {names, buildInputs} = {}) {
  if (buildInputs !== undefined) {
    if (names !== undefined || resolve(root) !== buildInputs.host.root) {
      throw new Error('InvalidResolvedHostBuildSelection');
    }
    return buildInputs.hostEntries;
  }
  return connectorManifestSelection(root, {names})
    .filter(entry => entry.host !== undefined)
    .map(entry => checkHostBundle(root, entry.name, entry.host));
}

export function checkHostProfiles(installations) {
  const versions = installations.filter(entry => entry.source !== undefined)
    .map(entry => entry.source.profileVersion);
  if (new Set(versions).size !== versions.length) throw new Error('Duplicate installed source profile version');
  const effectVersions = installations.filter(entry => entry.effect !== undefined)
    .map(entry => entry.effect.profileVersion);
  if (new Set(effectVersions).size !== effectVersions.length) throw new Error('Duplicate installed Effect profile version');
}

// Resolve concrete module paths at generation time. A distribution can map
// each checked entry into its packaged owner without changing declarations.
export function generateInstallations(installations, output, root, {resolveModule, resolveImplementationFile} = {}) {
  checkHostProfiles(installations);
  const section = (entry, section, label) => {
    const path = resolveModule === undefined
      ? section.modulePath ?? join(root, section.module) : resolveModule(entry, section, label);
    const module = moduleSpecifier(output, path);
    const exports = Object.entries(section.exports)
      .map(([key, symbol]) => `${key}: module.${symbol}`).join(', ');
    return `    ${label}: Object.freeze({\n` +
      `      profileVersion: ${JSON.stringify(section.profileVersion)},\n` +
      (section.identityProfile === undefined ? '' :
        `      identityProfile: Object.freeze(${JSON.stringify(section.identityProfile)}),\n`) +
      `      load: () => import(${JSON.stringify(module)})\n` +
      `        .then(module => Object.freeze({${exports}})),\n` +
      `    }),\n`;
  };
  const literal = value => JSON.stringify(value);
  const implementation = entry => {
    const ownerRoot = entry.root ?? root;
    const modules = [entry.source, entry.effect].filter(Boolean).map(role => role.module);
    const files = [...new Set([...entry.assets, ...adapterModuleGraph(ownerRoot, modules)
      .filter(path => path.startsWith(`adapters/connectors/${entry.name}/`))])].sort();
    if (files.length < 1 || files.length > 128) throw new Error('InvalidConnectorImplementationInventory');
    return `    implementationFiles: Object.freeze([\n` + files.map(path => {
      const source = resolveImplementationFile === undefined ? join(ownerRoot, path)
        : resolveImplementationFile(entry, path);
      return `      Object.freeze({path: ${literal(path)}, href: new URL(${literal(moduleSpecifier(output, source))}, import.meta.url).href}),\n`;
    }).join('') + `    ]),\n`;
  };
  return '// Generated by scripts/connector-node-bundles.mjs; edit connector host manifests.\n' +
    '// Installed Host bindings declared by connector-owned `host-bundle.json`\n' +
    '// manifests. The common Host selects one entry by the installed profile\'s\n' +
    '// version and loads only that connector\'s module and provider bundle.\n' +
    'export const installedConnectors = Object.freeze([\n' +
    installations.map(entry => `  Object.freeze({\n` +
        `    name: ${literal(entry.name)}, registration: ${literal(entry.registration)},\n` +
        `    revision: ${literal(entry.revision)},\n` +
        implementation(entry) +
        (entry.providerBundle === undefined ? '' :
          `    providerBundle: ${literal(entry.providerBundle)},\n`) +
        `    responseHeaders: Object.freeze(${literal(entry.responseHeaders)}),\n` +
        (entry.source === undefined ? '' : section(entry, entry.source, 'source')) +
        (entry.effect === undefined ? '' : section(entry, entry.effect, 'effect')) +
        `  }),\n`).join('') +
    ']);\n';
}
