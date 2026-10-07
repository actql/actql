// Shared build-time Host declarations; no runtime discovery or provider imports.
import {readFileSync, existsSync, lstatSync, realpathSync} from 'node:fs';
import {dirname, isAbsolute, join, relative, resolve, sep} from 'node:path';
import {connectorManifestSelection} from './connector-manifest-selection.mjs';
import {reservedHttpHeader} from '../adapters/host-common/http-exchange.mjs';

// Installed Host bindings. A connector that the standard Host can install
// for Source and/or Effect declares, in its own `host-bundle.json`, the Host profile
// version it answers to, the module exporting its installation entries, its
// registration/revision, its compiled provider bundle and the response
// header names its drivers read. The common Host selects one entry by the
// installed profile's version; it never branches on a provider name.
const hostBundleKeys = ['installation'];
const installationKeys = ['providerBundle', 'registration', 'responseHeaders', 'revision'];
const optionalInstallationKeys = ['assets', 'effect', 'source'];
const sourceKeys = ['exports', 'module', 'profileVersion'];
// An Effect section may register the identity profile of its durable Effect
// records: the version of each identity the common installed row Effect
// issues, and the continuation's installation-binding field. Only these
// fixed names exist; the common factory reads them from the generated table.
const identityProfileKeys = ['continuation', 'continuationBinding', 'dispatch',
  'recovery', 'source', 'targetCheck', 'unit'];
const identityVersion = /^actql-[a-z0-9-]+\/0\.1$/;
const continuationBindings = ['binding_cid', 'publication_generation_cid'];
const sourceExports = ['check', 'identityParts', 'load', 'publish'];
const requiredSourceExports = ['check', 'identityParts', 'load'];
const headerName = /^[a-z0-9][a-z0-9-]*$/;

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
  if (typeof providerBundle !== 'string' ||
      !new RegExp(`^connectors/${name}/[a-z][a-z0-9_]*$`).test(providerBundle)) throw invalid('providerBundle');
  const bundlePackage = options.resolveProviderPackage === undefined
    ? join(root, 'src', providerBundle, 'moon.pkg')
    : options.resolveProviderPackage(providerBundle);
  if (!existsSync(bundlePackage)) throw invalid('providerBundle package');
  const bundleManifest = readFileSync(bundlePackage, 'utf8');
  if (!/^supported_targets = "js"$/m.test(bundleManifest) ||
      !/pkgtype\(kind: "foreign_library"\)/.test(bundleManifest)) throw invalid('providerBundle kind');
  if (!Array.isArray(responseHeaders) || responseHeaders.length > 16 ||
      new Set(responseHeaders).size !== responseHeaders.length ||
      responseHeaders.some(header => typeof header !== 'string' || !headerName.test(header) ||
        reservedHttpHeader(header))) {
    throw invalid('responseHeaders');
  }
  const checkSection = (section, label) => {
    const prefix = label === 'source' ? '' : `${label} `;
    const {identityProfile, ...rest} = section ?? {};
    if (label === 'effect' && identityProfile !== undefined) {
      if (!sameKeys(identityProfile, identityProfileKeys) ||
          !continuationBindings.includes(identityProfile.continuationBinding) ||
          identityProfileKeys.filter(key => key !== 'continuationBinding')
            .some(key => typeof identityProfile[key] !== 'string' ||
              !identityVersion.test(identityProfile[key]))) {
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
  // Only connector-owned static declarations are copied as data. Resolve
  // their actual location as well as their spelling before packaging.
  const prefix = `src/connectors/${name}/`;
  const connectorDirectory = join(root, prefix);
  if (!existsSync(connectorDirectory) || !lstatSync(connectorDirectory).isDirectory() ||
      realpathSync(connectorDirectory) !== resolve(realpathSync(root), prefix) ||
      !Array.isArray(assets) || new Set(assets).size !== assets.length ||
      assets.some(asset => typeof asset !== 'string' || !asset.startsWith(prefix) ||
        !asset.endsWith('.json') || !safeRelativePath(asset) ||
        !existsSync(join(root, asset)) || !lstatSync(join(root, asset)).isFile() ||
        !realpathSync(join(root, asset)).startsWith(realpathSync(connectorDirectory) + '/'))) {
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
export function generateInstallations(installations, output, root, {resolveModule} = {}) {
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
  return '// Generated by scripts/connector-node-bundles.mjs; edit connector host manifests.\n' +
    '// Installed Host bindings declared by connector-owned `host-bundle.json`\n' +
    '// manifests. The common Host selects one entry by the installed profile\'s\n' +
    '// version and loads only that connector\'s module and provider bundle.\n' +
    'export const installedConnectors = Object.freeze([\n' +
    installations.map(entry => `  Object.freeze({\n` +
        `    name: ${literal(entry.name)}, registration: ${literal(entry.registration)},\n` +
        `    revision: ${literal(entry.revision)},\n` +
        `    providerBundle: ${literal(entry.providerBundle)},\n` +
        `    responseHeaders: Object.freeze(${literal(entry.responseHeaders)}),\n` +
        (entry.source === undefined ? '' : section(entry, entry.source, 'source')) +
        (entry.effect === undefined ? '' : section(entry, entry.effect, 'effect')) +
        `  }),\n`).join('') +
    ']);\n';
}
