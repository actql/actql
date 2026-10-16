import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import * as moon from '../../../../_build/js/release/build/connectors/hubspot/host_node/host_node.js';
import * as common from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeField} from '../../../host-common/compiler-binding.generated.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {rowSourceCheckEnvironment} from '../../../host-node/installed-row-source.mjs';
import {recordWriteFixture} from './hubspot-record-write.fixture.mjs';

const metadata = {results: [
  {name: 'amount', type: 'number', fieldType: 'number', calculated: false,
    modificationMetadata: {readOnlyValue: false}},
  {name: 'tags', type: 'enumeration', fieldType: 'checkbox', calculated: false,
    modificationMetadata: {readOnlyValue: false}, options: [{value: 'a'}, {value: 'b'}]},
  {name: 'external_key', type: 'string', fieldType: 'text', hasUniqueValue: true,
    calculated: false, modificationMetadata: {readOnlyValue: false}},
]};
const limits = [100, 20, 256, 10000, 1000, 20];
const bodyLimits = [4096, 1000, 20, 10, 100, 1000, 4096, 10000, 4096, 1000, 20];
const original = Object.freeze({amount: '9007199254740993.0100000000', tags: ['a', 'b']});
const hash = value => `sha256:${createHash('sha256').update(canonicalJson(value)).digest('hex')}`;
const project = () => checked(moon.hubspotProjectProperties(Buffer.from(JSON.stringify(metadata)),
  'companies', 4096, 1000, 20, 100, 100));

function declaration(catalog) {
  const schemaWire = checked(moon.hubspotObjectSchemaWire(catalog, ['amount', 'tags', 'external_key'],
    10, 100, 10000, 1000, 20));
  const original = checked(common.clientProgramRowSourceRestoreRelationDeclaration('hubspot',
    'hubspot', 'hubspot/0.1', JSON.stringify({views: [{resource: 'companies', resource_kind: 'object',
      schema_wire: schemaWire, schema_cid: `sha256:${createHash('sha256').update(schemaWire).digest('hex')}`,
      facts_wire: moon.hubspotObjectRelationFactsWire()}]}), undefined));
  const declared = JSON.parse(common.clientProgramRowSourceDeclarationJson(original));
  return {original, declared, manifest: hash(JSON.parse(declared.manifest_entry))};
}

function mapping(catalog, declared, kind = 0, fields = ['amount', 'tags'], sources) {
  return checked(moon.hubspotPrepareExecutionMapping(catalog, 'hubspot', declared.manifest,
    'companies', kind, ['', 'id', 'external_key'][kind], fields,
    sources ?? (kind === 0 ? fields.map(name => moon.hubspotMappingSource(name, name, 'reject')) : []),
    ...limits));
}

async function environment(catalog, derived) {
  const {declared} = declaration(catalog);
  const base = await readFile(new URL('../../../../spec/local-check-environment.json', import.meta.url), 'utf8');
  const environment = rowSourceCheckEnvironment(base, declared,
    derived.map(value => moon.hubspotExecutionMappingBody(value)));
  return common.clientProgramCheckEnvironment(environment.wire, environment.evidenceCid,
    false, false, true, false, false, false, false);
}

test('actual Common admits original full Decimal38/array create update upsert mapping contracts', async () => {
  const catalog = project(), original = declaration(catalog);
  const mappings = [0, 1, 2].map(kind => mapping(catalog, original, kind));
  assert.ok(await environment(catalog, mappings));
  const expectedSchema = {type: 'object', nullable: false, additional_properties: false,
    fields: {id: {type: 'string', nullable: false},
      amount: {type: 'decimal', nullable: true, precision: 38, scale: 10},
      tags: {type: 'array', nullable: true, items: {type: 'string', nullable: false}}}};
  for (const [index, prepared] of mappings.entries()) {
    const value = JSON.parse(moon.hubspotExecutionMappingBody(prepared));
    assert.equal(moon.hubspotExecutionMappingBody(prepared), canonicalJson(value));
    const {mapping_contract_cid: actualCid, ...preimage} = value;
    const requestIdentity = {key: index === 2 ? 'external_key' : null,
      kind: ['create', 'update', 'upsert'][index], resource: 'companies',
      row_mapping: value.row_mapping, target_schema: value.target_schema, write_fields: ['amount', 'tags']};
    const suffix = hash(requestIdentity).slice(7, 23);
    assert.equal(value.mapping_ref, `mapping:hubspot/companies/${requestIdentity.kind}-${suffix}.v1`);
    assert.equal(actualCid, hash(preimage));
    assert.equal(value.connector_manifest_cid, original.manifest);
    assert.deepEqual(value.target_schema, index === 2 ? {...expectedSchema,
      fields: {...expectedSchema.fields, external_key: {type: 'string', nullable: true}}} : expectedSchema);
    assert.equal(value.target_schema_identity, hash(value.target_schema));
    assert.deepEqual(value.permission_rules[0], {effect_kind: ['create', 'update', 'upsert'][index],
      selector_class: ['none', 'id', 'key'][index], write_fields: ['amount', 'tags'],
      permissions: [`hubspot:objects:batch-${['create', 'update', 'upsert'][index]}`]});
  }
});

function effectProgram(prepared, kind = 0) {
  const schema = {id: {type: 'string', nullable: false},
    external_key: {type: 'string', nullable: false},
    amount: {type: 'decimal', precision: 38, scale: 10, nullable: false},
    tags: {type: 'array', nullable: false, items: {type: 'string', nullable: false}}};
  const operation = ['create', 'update', 'upsert'][kind];
  const effect = {target: 'connector://hubspot/companies',
    mapping: moon.hubspotExecutionMappingRef(prepared), from: {result: 'rows'}};
  if (kind !== 0) Object.assign(effect, {set: {amount: {field: 'amount'}, tags: {field: 'tags'}},
    ...(kind === 1 ? {id: 'id'} : {key: 'external_key'})});
  return JSON.stringify({version: 'actql/0.1', id: 'hubspot-mapped-values', stages: [{id: 'source', inputs: {},
    steps: [{values: {schema, rows: [{...original, id: '9007199254740993', external_key: 'original-key'}]}, as: 'values'}],
    results: {rows: {from: 'values', fields: ['amount', 'external_key', 'id', 'tags']}},
    effects: {save: {[operation]: effect}}}],
    results: {answer: {from: {stage: 'source', result: 'rows'}}}});
}

function prepareEffect(environmentHandle, prepared, kind = 0) {
  const outcome = common.clientProgramPrepareEffectComputationWithParameters(
    effectProgram(prepared, kind), 'json', environmentHandle, undefined, []);
  return {value: common.clientProgramEffectPreparationReady(outcome),
    issue: common.clientProgramEffectPreparationIssueCode(outcome)};
}

test('actual Common prepares and compiles Result-backed create update upsert with full typed values', async () => {
  const catalog = project(), declared = declaration(catalog);
  for (const kind of [0, 1, 2]) {
    const prepared = mapping(catalog, declared, kind);
    const environmentHandle = await environment(catalog, [prepared]);
    const result = prepareEffect(environmentHandle, prepared, kind);
    assert.ok(result.value, `${kind}: ${result.issue}`);
    assert.match(common.clientProgramEffectDefinitionCid(result.value), /^sha256:[0-9a-f]{64}$/);
    const descriptor = checked(common.clientProgramEffectMemberDescriptor(result.value, 0, 'save', 1000));
    assert.equal(runtimeField(descriptor, 4), moon.hubspotExecutionMappingRef(prepared));
    assert.equal(runtimeField(descriptor, 5), moon.hubspotExecutionMappingCid(prepared));
    const compiled = common.clientProgramCompileLocalEffects(result.value);
    assert.equal(common.clientProgramEffectCompilationIssueCode(compiled), undefined);
    assert.ok(checked(compiled));
    for (const foreignKind of [0, 1, 2].filter(value => value !== kind)) {
      assert.equal(prepareEffect(environmentHandle, prepared, foreignKind).value, undefined,
        `Mapping for ${kind} cannot authorize operation ${foreignKind}`);
    }
  }
});

test('original metadata/schema/manifest binding is neither mutable output nor a replacement authority', async () => {
  const catalog = project(), declared = declaration(catalog), prepared = mapping(catalog, declared);
  const names = moon.hubspotExecutionMappingFields(prepared); names[0] = 'external_key';
  assert.deepEqual(moon.hubspotExecutionMappingFields(prepared), ['amount', 'tags']);
  const changed = structuredClone(metadata); changed.results[0].modificationMetadata.readOnlyValue = true;
  const current = checked(moon.hubspotProjectProperties(Buffer.from(JSON.stringify(changed)),
    'companies', 4096, 1000, 20, 100, 100));
  assert.throws(() => checked(moon.hubspotRecheckExecutionMapping(prepared, current, 100)),
    {code: 'MoonBitHostFailure'});
  // A well-formed foreign manifest is DATA, not a valid installed Mapping.
  // Common admission, not a fake new public reference, must refuse it.
  const foreign = mapping(catalog, {...declared, manifest: `sha256:${'e'.repeat(64)}`});
  const foreignEnvironment = await environment(catalog, [foreign]);
  assert.equal(prepareEffect(foreignEnvironment, foreign).value, undefined);
});

test('actual original mapped value reaches one Credential/Account/SQLite/TLS POST without decimal or array loss', async t => {
  let derived;
  const f = await recordWriteFixture(t, 'create', ['effect', 'read'], {metadataOverride: metadata,
    requestFactory: ({catalog}) => {
      const declared = declaration(catalog); derived = mapping(catalog, declared);
      const body = checked(moon.hubspotPrepareExecutionWriteBody(derived, catalog,
        Buffer.from(JSON.stringify(original)), 100, ...bodyLimits));
      assert.equal(moon.hubspotWriteBodyValueJson(body), canonicalJson(original));
      return checked(moon.hubspotPrepareRecordBatch(catalog, 0, '',
        [moon.hubspotCreateRecordWriteInput(body, 'original-mapped-write')], 100, 100, 100, 4096, 1000, 20));
    }});
  const raw = await f.send();
  assert.deepEqual(f.writeState.writes, ['{"inputs":[{"objectWriteTraceId":"original-mapped-write","properties":{"amount":"9007199254740993.0100000000","tags":"a;b"}}]}']);
  assert.equal(f.state.requests.length, 3); assert.equal(f.state.charges, 3);
  assert.equal(f.project(raw.observation).kind, 'typed-success-response');
  assert.equal(moon.hubspotExecutionMappingFields(derived).length, 2);
  f.row.assertNoCapture();
});
