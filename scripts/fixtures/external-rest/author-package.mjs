// Snapshot the exact author inputs before invoking the normal package tools.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join, posix} from 'node:path';
import {restConnectorPackageMetadata} from '../../connector-authoring.mjs';
import {checkHostBundle} from '../../connector-host-bundles.mjs';
import {inventory, unpack} from '../../package-release.mjs';
import {assertAuthorRestSchema, readAuthorBytes} from './conformance-input.mjs';

const maxAuthorBytes = 1024 * 1024;
const registrationDirectory = (root, registration) => join(root, 'src/connectors', registration);
const readJson = async path => JSON.parse(await readFile(path, 'utf8'));

export function selectAuthorPackage(casePath, author) {
  const {connector, schema} = author;
  const root = dirname(casePath);
  const packed = connector.kind === 'packed';
  const bytes = readAuthorBytes(root, connector.path, connector.sha256,
    packed ? 16 * maxAuthorBytes : maxAuthorBytes);
  if (packed) return {bytes};
  const definition = JSON.parse(bytes);
  assert.equal(definition?.id, schema.registration, 'REST author registration mismatch');
  const declaredOrigin = new URL(definition.origin);
  assert(declaredOrigin.protocol === 'https:' && declaredOrigin.origin === definition.origin,
    'REST author definition must declare an HTTPS origin before fixture binding');
  assertAuthorRestSchema(schema, {views: [{resource: schema.resource, resource_kind: 'record',
    fields: definition.sources?.[schema.resource]?.fields}]});
  assert.equal(definition.transform === undefined, connector.transformSha256 === undefined,
    'Pin the original author transform bytes with the definition');
  const transform = definition.transform === undefined ? undefined
    : readAuthorBytes(dirname(join(root, connector.path)), definition.transform,
      connector.transformSha256, maxAuthorBytes);
  return {definition, transform};
}

export async function stageAuthorDefinition(authorDirectory, selected, origin) {
  const definitionPath = join(authorDirectory, 'connector.json');
  const definition = {...selected.definition, origin};
  await writeFile(definitionPath, JSON.stringify(definition, null, 2) + '\n');
  if (selected.transform !== undefined) {
    const transformPath = join(authorDirectory, definition.transform);
    await mkdir(dirname(transformPath), {recursive: true});
    await writeFile(transformPath, selected.transform, {flag: 'wx'});
  }
  return definitionPath;
}

export async function readAuthorPackage(root, schema, origin, hostPackageVersion) {
  const {registration} = schema;
  assert.equal(typeof hostPackageVersion, 'string');
  const metadata = await readJson(join(root, 'package.json'));
  assert.deepEqual(metadata, restConnectorPackageMetadata(registration, hostPackageVersion),
    'REST package manifest must match the generated package without lifecycle hooks or extra dependencies');
  const path = registrationDirectory(root, registration);
  const declaration = await readJson(join(path, 'rest-source.json'));
  assert.equal(declaration.registration, registration, 'REST package registration mismatch');
  assert.equal(declaration.origin, origin, 'REST package origin must match the controlled loopback fixture');
  const bundle = checkHostBundle(root, registration, join(path, 'host-bundle.json'));
  const profileVersion = bundle.source?.profileVersion;
  assert.equal(typeof profileVersion, 'string');
  assert.equal(profileVersion, declaration.profileVersion);
  assert(bundle.effect === undefined && bundle.providerBundle === undefined, 'Select a standard REST Read package');
  const views = await readJson(join(path, 'source-views.json'));
  assertAuthorRestSchema(schema, views);
  assert.deepEqual(JSON.parse(declaration.authoredViewsWire), views);
  const files = await inventory(root);
  const owned = new Set(['package.json', 'index.mjs', `src/connectors/${registration}/host-bundle.json`,
    ...bundle.assets, bundle.source.module, posix.join(posix.dirname(bundle.source.module), 'transform.mjs')]);
  assert(files.every(file => owned.has(file.path) || /^(?:README|LICENSE)(?:[.][a-z]+)?$/iu.test(file.path)),
    'REST packed payload contains files outside the generated installation');
  return {name: metadata.name, profileVersion, files};
}

export async function stagePackedAuthorPackage(output, author, bytes, hostPackageVersion) {
  const tar = join(output, 'author-connector.tgz');
  await writeFile(tar, bytes, {flag: 'wx'});
  const root = await unpack(tar, join(output, 'packed-connector-inventory'));
  const origin = `https://127.0.0.1:${author.protocol.port}`;
  const pkg = await readAuthorPackage(root, author.schema, origin, hostPackageVersion);
  return {...pkg, tar, bytes, integrity: 'sha512-' + createHash('sha512').update(bytes).digest('base64')};
}
