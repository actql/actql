import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid, documentCid} from './actql-spec-family.mjs';

const registryPath = 'spec/contracts/actql-production-profile-schemas.json';
const lookupPath = 'spec/contracts/actql-lookup-identities.json';
const cid = {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'};
const text = {type: 'string', minLength: 1};
const closed = properties => ({type: 'object', additionalProperties: false,
  required: Object.keys(properties), properties});

// Implementation DATA for the existing Native file -> ContentRef reader.
// This neither issues a request nor proves a physical attempt or byte custody.
function fileReadProfileSchema(implementation) {
  return {$schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: `https://smooth.dev/schemas/actql-${implementation}-file-content-read-0.1.json`,
    ...closed({version: {const: `actql-${implementation}-file-content-read/0.1`},
      source_view_contract_cid: cid, physical_source_view_contract_cid: cid,
      request_schema_cid: cid, response_schema_cid: cid,
      projection: closed({identity_field: text, name_field: text,
        version_field: text, media_type_field: text, content_utf8_field: text,
        path_field: {anyOf: [text, {type: 'null'}]},
        items_path: {type: 'array', items: text},
        key_path: {type: 'array', items: text}}),
      transport_cid: cid})};
}

export const nativeFileReadProfileSchema = () => fileReadProfileSchema('native');
export const declaredFileReadProfileSchema = () => fileReadProfileSchema('declared');
export const verifyNativeFileReadProfile = (write = false) => verifyFileReadProfile('native', write);
export const verifyDeclaredFileReadProfile = (write = false) => verifyFileReadProfile('declared', write);

function verifyFileReadProfile(implementation, write) {
  const name = `${implementation}_file_content_read`;
  const version = `actql-${implementation}-file-content-read/0.1`;
  const registry = JSON.parse(readFileSync(registryPath, 'utf8'));
  const lookup = JSON.parse(readFileSync(lookupPath, 'utf8'));
  const schema = fileReadProfileSchema(implementation);
  const pin = machineCid(schema);
  const binding = {path: registryPath, pointer: `/schemas/${name}`,
    self_field: 'transport_cid', schema_cid: pin,
    selection: implementation === 'native'
      ? 'Native declared-file keyed Content reader; same SourceView, physical provider and projection; not HTTP or query Source evidence'
      : 'Installed Node declared-file keyed Content reader; same SourceView, physical provider and projection; not Native or query Source evidence'};
  if (write) {
    registry.schemas[name] = schema;
    registry.schema_cids[name] = pin;
    const {registry_cid: _previous, ...body} = registry;
    registry.registry_cid = machineCid(body);
    // Keep existing bindings byte-for-byte. Select this implementation by its
    // declared version; an unknown implementation has no fallback.
    lookup.external_contracts['checked-read-profile'].implementations = {
      ...lookup.external_contracts['checked-read-profile'].implementations,
      [version]: binding,
    };
    writeFileSync(registryPath, JSON.stringify(registry, null, 2) + '\n');
    writeFileSync(lookupPath, JSON.stringify(lookup, null, 2) + '\n');
    const familyPath = 'spec/spec-family.json';
    const family = JSON.parse(readFileSync(familyPath, 'utf8'));
    const owner = family.documents.find(item => item.document_id === 'artifacts');
    assert.ok(owner);
    const pointer = `/schemas/${name}`;
    let reference = owner.machine_contracts.find(item =>
      item.path === registryPath && item.pointer === pointer);
    const previousPin = reference?.cid;
    if (reference) reference.cid = pin;
    else owner.machine_contracts.push({path: registryPath, pointer, cid: pin,
      version: 'actql-production-profile-schema-registry/0.1'});
    let text = readFileSync(owner.path, 'utf8');
    const marker = `../../../${registryPath}#${pointer} ${pin}`;
    text = text.replace(`${implementation.toUpperCase()}_FILE_READ_PROFILE_MACHINE_PIN`, marker);
    if (previousPin) text = text.replace(
      `../../../${registryPath}#${pointer} ${previousPin}`, marker);
    writeFileSync(owner.path, text);
    for (const item of family.documents) {
      let document = readFileSync(item.path, 'utf8');
      for (const imported of item.machine_contracts ?? []) {
        if (![registryPath, lookupPath].includes(imported.path)) continue;
        let value = JSON.parse(readFileSync(imported.path, 'utf8'));
        for (const part of imported.pointer.split('/').slice(1)) {
          value = value[part.replaceAll('~1', '/').replaceAll('~0', '~')];
        }
        const next = machineCid(value);
        document = document.replaceAll(
          `../../../${imported.path}#${imported.pointer} ${imported.cid}`,
          `../../../${imported.path}#${imported.pointer} ${next}`);
        imported.cid = next;
      }
      writeFileSync(item.path, document);
    }
    const documents = new Map(family.documents.map(item => [item.spec_id,
      documentCid(readFileSync(item.path, 'utf8'))]));
    for (const item of family.documents) {
      for (const imported of item.normative_imports ?? []) {
        imported.document_cid = documents.get(imported.owner);
      }
    }
    writeFileSync(familyPath, JSON.stringify(family, null, 2) + '\n');
  }
  assert.deepEqual(registry.schemas[name], schema);
  assert.equal(registry.schema_cids[name], pin);
  const {registry_cid: registryCid, ...body} = registry;
  assert.equal(registryCid, machineCid(body));
  assert.deepEqual(lookup.external_contracts['checked-read-profile']
    .implementations?.[version], binding);
  return {schema, cid: pin};
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(JSON.stringify({native_file_read_profile:
    verifyNativeFileReadProfile(process.argv.includes('--write')).cid,
    declared_file_read_profile: verifyDeclaredFileReadProfile(process.argv.includes('--write')).cid}));
}
