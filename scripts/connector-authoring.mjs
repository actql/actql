// Build-time author DATA projection. Existing Source declarations and Host
// manifests remain the semantic and installation authorities.
import {existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {dirname, join, parse, resolve, sep} from 'node:path';
import {checkHostBundle, renderHostInstallations} from './connector-host-bundle-contract.mjs';
import {createRequire} from 'node:module';
import {releaseVersion} from './release-version.mjs';

const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const shape = (value, required, optional = []) => record(value) &&
  required.every(key => Object.hasOwn(value, key)) &&
  Object.keys(value).every(key => required.includes(key) || optional.includes(key));
const fail = reason => { throw new Error(`InvalidRestConnectorDefinition:${reason}`); };
const name = value => typeof value === 'string' && /^[a-z][a-z0-9_]*$/u.test(value);
const finite = value => Number.isSafeInteger(value) && value > 0 && value <= 2147483647;
const propertyPath = value => Array.isArray(value) && value.length <= 16 &&
  value.every(key => typeof key === 'string' && key.length > 0 &&
    !['__proto__', 'prototype', 'constructor'].includes(key));
const relative = value => typeof value === 'string' &&
  /^[A-Za-z0-9_.-]+(?:\/[A-Za-z0-9_.-]+)*$/u.test(value) &&
  value.split('/').every(part => !['.', '..'].includes(part));
const freeze = value => {
  if (record(value) || Array.isArray(value)) {
    Object.values(value).forEach(freeze); Object.freeze(value);
  }
  return value;
};

function installedHostVersion(entry) {
  try {
    const manifest = JSON.parse(readFileSync(join(dirname(entry), 'package.json'), 'utf8'));
    if (manifest?.name !== '@actql/local-node') throw new Error('Unexpected author validator package');
    return manifest.version === '0.0.0-development' ? manifest.version : releaseVersion(manifest.version).version;
  } catch (cause) {
    throw Object.assign(new Error('RestAuthoringValidatorUnavailable: invalid selected Host manifest', {cause}),
      {code: 'RestAuthoringValidatorUnavailable'});
  }
}

function installedReadValidator(authorRoot) {
  // CLI callers resolve the author's explicitly installed dependency. The
  // repository's source/component caller selects its SAME prepared public
  // package entry; neither route falls back to a raw runtime or compiler.
  const selected = authorRoot === undefined
    ? new URL('../packages/local-node/package.json', import.meta.url)
    : join(resolve(authorRoot), 'package.json');
  const require = createRequire(selected);
  let namespace, version;
  try {
    const entry = require.resolve('@actql/local-node/connector-authoring');
    version = installedHostVersion(entry);
    namespace = require('@actql/local-node/connector-authoring');
  }
  catch (cause) {
    if (cause?.code === 'MODULE_NOT_FOUND' || cause?.code === 'ERR_PACKAGE_PATH_NOT_EXPORTED') {
      throw Object.assign(new Error('RestAuthoringValidatorUnavailable: install a matching @actql/local-node in the author project'),
        {code: 'RestAuthoringValidatorUnavailable'});
    }
    throw cause;
  }
  const method = Object.getOwnPropertyDescriptor(namespace, 'validateRestReadDeclaration');
  if (!method || !Object.hasOwn(method, 'value') || typeof method.value !== 'function') {
    throw Object.assign(new Error('RestAuthoringValidatorUnavailable'), {code: 'RestAuthoringValidatorUnavailable'});
  }
  return {validateRead: method.value.bind(namespace), version};
}

// The packed author runner uses the same manifest contract as the generator
// before npm can run a caller-owned lifecycle or resolve another dependency.
export function restConnectorPackageMetadata(id, hostPackageVersion) {
  return {name: `@actql-connectors/${id.replaceAll('_', '-')}`,
    version: '0.0.1', type: 'module',
    peerDependencies: {'@actql/local-node': hostPackageVersion},
    exports: {'.': './index.mjs'}, files: ['index.mjs', 'src/connectors', 'adapters/connectors']};
}

export function projectRestConnector(definition, {hostPackageVersion, authorRoot} = {}) {
  if (!shape(definition, ['version', 'id', 'origin', 'auth', 'sources'], ['transform']) ||
      definition.version !== 'actql-rest-connector/0.1' || !name(definition.id) ||
      !shape(definition.auth, ['kind']) || definition.auth.kind !== 'bearer' ||
      !record(definition.sources) || Object.keys(definition.sources).length === 0 ||
      Object.keys(definition.sources).length > 64) fail('shape');
  let origin;
  try { origin = new URL(definition.origin); } catch { fail('origin'); }
  if (origin.protocol !== 'https:' || origin.origin !== definition.origin ||
      origin.username || origin.password) fail('origin');
  if (definition.transform !== undefined && (!relative(definition.transform) ||
      !definition.transform.endsWith('.mjs'))) fail('transform');
  const {validateRead, version} = installedReadValidator(authorRoot);
  if (hostPackageVersion !== undefined && hostPackageVersion !== version) fail('host version');
  const sources = Object.entries(definition.sources).map(([resource, source]) => {
    if (!name(resource) || !shape(source, ['fields', 'read', 'pagination', 'limits']) ||
        !Array.isArray(source.fields) || source.fields.length === 0 || !record(source.read)) fail('source');
    const p = source.pagination;
    const cursor = shape(p, ['kind', 'items', 'next', 'parameter']) && p.kind === 'cursor' &&
      propertyPath(p.next) && typeof p.parameter === 'string' &&
      /^[a-zA-Z][a-zA-Z0-9_]*$/u.test(p.parameter);
    const single = shape(p, ['kind', 'items']) && p.kind === 'none';
    if ((!cursor && !single) || !propertyPath(p.items)) fail('pagination');
    let readWire;
    try {readWire = validateRead(JSON.stringify(source.read), cursor ? p.parameter : undefined);}
    catch (cause) {
      if (cause?.code === 'RestAuthoringValidatorUnavailable') throw cause;
      throw new Error('InvalidRestConnectorDefinition:read', {cause});
    }
    const limits = source.limits;
    const keys = ['maxPageRows', 'maxPageBytes', 'maxPages', 'maxRows',
      'maxNodes', 'maxDepth', 'maxCursorBytes'];
    if (!shape(limits, keys) || !keys.every(key => finite(limits[key])) ||
        limits.maxPageRows > limits.maxRows) fail('limits');
    // Pass the original typed schema DATA to Common. This is not a second
    // schema/type checker, no generated hash or independent business oracle.
    return {resource, resource_kind: 'record', fields: source.fields,
      readWire, pagination: p, limits};
  });
  const id = definition.id, profileVersion = `actql-installed-${id.replaceAll('_', '-')}-rest-source/0.1`;
  const module = `adapters/connectors/${id}/host/installation.mjs`;
  const definitionPath = `src/connectors/${id}/rest-source.json`;
  const viewsPath = `src/connectors/${id}/source-views.json`;
  const manifest = {installation: {registration: id, revision: `${id}/0.1`,
    responseHeaders: [], assets: [definitionPath, viewsPath], source: {
      profileVersion, module, exports: {check: 'checkProfile', identityParts: 'identityParts',
        publish: 'publish', load: 'load'}}}};
  const authoredViewsWire = JSON.stringify({views: sources.map(({resource, resource_kind, fields}) =>
    ({resource, resource_kind, fields}))});
  const projected = {registration: id, revision: `${id}/0.1`, profileVersion,
    origin: definition.origin, auth: definition.auth, sources, authoredViewsWire};
  const moduleSource = `// Generated by connector-authoring.mjs; edit connector.json.\n` +
    `import {createInstalledRestSource} from '@actql/local-node/connector-installation';\n` +
    (definition.transform === undefined ? '' : `import {decodePage} from './transform.mjs';\n`) +
    `const installation = createInstalledRestSource(${JSON.stringify(projected, null, 2)}` +
    (definition.transform === undefined ? '' : ', {decodePage}') + `);\n` +
    `export const checkProfile = installation.checkProfile;\n` +
    `export const identityParts = installation.identityParts;\n` +
    `export const publish = installation.publish;\n` +
    `export const load = installation.load;\n`;
  return freeze({registration: id, profileVersion, manifest,
    files: {'package.json': JSON.stringify(restConnectorPackageMetadata(id, version), null, 2) + '\n',
      [`src/connectors/${id}/host-bundle.json`]: JSON.stringify(manifest, null, 2) + '\n',
      [definitionPath]: JSON.stringify(projected, null, 2) + '\n',
      [viewsPath]: JSON.stringify({views: sources.map(({resource, resource_kind, fields}) =>
        ({resource, resource_kind, fields}))}, null, 2) + '\n',
      [module]: moduleSource},
    ...(definition.transform === undefined ? {} : {transform: {source: definition.transform,
      destination: `adapters/connectors/${id}/host/transform.mjs`}})});
}

function unaliasedOutput(path) {
  path = resolve(path);
  let current = parse(path).root;
  const parts = path.slice(current.length).split(sep).filter(Boolean);
  for (let index = 0; index < parts.length; index++) {
    current = join(current, parts[index]);
    let info;
    try { info = lstatSync(current); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    if (info.isSymbolicLink() || index < parts.length - 1 && !info.isDirectory()) {
      fail('aliased output');
    }
  }
}

export function writeRestConnector({definitionPath, outputRoot, check = false, installedToolkit = false}) {
  const authorRoot = dirname(resolve(definitionPath)), root = resolve(outputRoot);
  const projection = projectRestConnector(JSON.parse(readFileSync(definitionPath, 'utf8')),
    {authorRoot});
  const files = {...projection.files};
  if (projection.transform !== undefined) {
    let path = authorRoot;
    for (const part of projection.transform.source.split('/')) {
      path = join(path, part);
      if (lstatSync(path).isSymbolicLink()) fail('aliased transform');
    }
    const transform = readFileSync(path, 'utf8');
    if (installedToolkit) {
      const checked = spawnSync(process.execPath, ['--input-type=module', '--check'],
        {input: transform, stdio: ['pipe', 'ignore', 'ignore']});
      if (checked.error) throw checked.error;
      if (checked.status !== 0) fail('transform syntax');
    }
    files[projection.transform.destination] = transform;
  }
  // Validate every selected destination before the first write, including
  // dangling links and aliases above a new output directory.
  for (const path of [...Object.keys(files), 'index.mjs']) unaliasedOutput(join(root, path));
  for (const [path, contents] of Object.entries(files)) {
    const destination = join(root, path);
    if (check) {
      if (!existsSync(destination) || readFileSync(destination, 'utf8') !== contents) {
        throw new Error(`StaleRestConnectorProjection:${path}`);
      }
    } else {
      mkdirSync(dirname(destination), {recursive: true}); writeFileSync(destination, contents);
    }
  }
  const entry = checkHostBundle(root, projection.registration,
    join(root, `src/connectors/${projection.registration}/host-bundle.json`));
  const index = join(root, 'index.mjs');
  let registration;
  if (installedToolkit) {
    // The installed standard generator owns its entry and the one selected
    // transform. It uses the same Host renderer over that finite inventory.
    const modules = [entry.source.module];
    if (projection.transform !== undefined) modules.push(projection.transform.destination);
    registration = renderHostInstallations([entry], index, root, {implementationModules: () => modules});
  } else {
    const {generateInstallations} = createRequire(import.meta.url)('./connector-host-bundles.mjs');
    registration = generateInstallations([entry], index, root);
  }
  if (check) {
    if (!existsSync(index) || readFileSync(index, 'utf8') !== registration) {
      throw new Error('StaleRestConnectorProjection:index.mjs');
    }
  } else writeFileSync(index, registration);
  return Object.freeze({registration: projection.registration,
    files: Object.freeze([...Object.keys(files), 'index.mjs'].sort()),
    authorFiles: Object.freeze(['connector.json', ...(projection.transform ? [projection.transform.source] : [])]),
    customMoonBitPackages: 0, runtimeExecuted: true,
    pureCommonValidation: true, hostRuntimeExecuted: false});
}

export function initRestConnector(directory, id) {
  if (!name(id)) fail('id');
  if (existsSync(directory) && readdirSync(directory).length !== 0) fail('nonempty scaffold');
  mkdirSync(directory, {recursive: true});
  const definition = {version: 'actql-rest-connector/0.1', id, origin: 'https://api.example.invalid',
    auth: {kind: 'bearer'}, sources: {records: {
      fields: [{name: 'id', type: 'string', nullable: false}],
      read: {method: 'GET', path: '/v1/records'},
      pagination: {kind: 'cursor', items: ['data'], next: ['next_cursor'], parameter: 'after'},
      limits: {maxPageRows: 100, maxPageBytes: 1048576, maxPages: 10,
        maxRows: 1000, maxNodes: 10000, maxDepth: 16, maxCursorBytes: 1024}}}};
  writeFileSync(join(directory, 'connector.json'), JSON.stringify(definition, null, 2) + '\n');
  return join(directory, 'connector.json');
}
