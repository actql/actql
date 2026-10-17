// Consume the actual same-runtime Common/Connector original, not a handwritten
// Mapping issuer or a generated success fixture. This unit performs no I/O.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test from 'node:test';
import * as moon from '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {checked} from '../../../host-common/runtime-result.mjs';
import {runtimeIsError} from '../../../host-common/compiler-binding.generated.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';

const bytes = value => Buffer.from(JSON.stringify(value));
const cid = value => 'sha256:' + createHash('sha256').update(canonicalJson(value)).digest('hex');
const form = {revision: '7', properties: {Subject: {code: 'Subject', type: 'SINGLE_LINE_TEXT'}}};
const catalog = () => checked(moon.clientProgramKintoneProjectForm(bytes(form), '12',
  moon.clientProgramKintoneFormLimits(8192, 1000, 16, 16, 512)));
const declaration = original => checked(moon.clientProgramKintoneDeclareRecords(original, undefined,
  ['Subject'], 'kintone', 'kintone/0.1', 'inquiries',
  moon.clientProgramKintoneValueLimits(8, 128, 1000, 16, 8192),
  moon.clientProgramKintoneDeclarationLimits(100000, 10000, 32, 1, 8)));
const mapping = original => checked(moon.clientProgramKintonePrepareDeleteMapping(original,
  'inquiries', 'required', moon.clientProgramKintoneDeclarationLimits(100000, 10000, 32, 1, 8)));
const request = (original, fields = ['Subject']) => {
  const page = checked(moon.clientProgramKintoneProjectRecordPage(bytes({records: [{
    $id: {type: '__ID__', value: '9007199254740993'},
    $revision: {type: '__REVISION__', value: '9007199254740994'},
    Subject: {type: 'SINGLE_LINE_TEXT', value: 'original'},
  }], totalCount: null}), original, fields,
  moon.clientProgramKintonePageLimits(8192, 1000, 16, 4, 8, 32, 16)));
  return checked(moon.clientProgramKintoneDeleteRequest([
    checked(moon.clientProgramKintoneOriginalRecordTarget(page, 0, 1000)),
  ], moon.clientProgramKintoneMutationLimits(100, 1000, 10000, 8192, 1000, 16)));
};

test('actual Common runtime derives delete Mapping from the original declared App schema', () => {
  const original = declaration(catalog()), owned = mapping(original);
  const wire = moon.clientProgramKintoneDeleteMappingBody(owned), value = JSON.parse(wire);
  const {mapping_contract_cid: identity, ...preimage} = value;
  assert.equal(identity, cid(preimage));
  assert.equal(value.target_ref, 'connector://kintone/inquiries');
  assert.equal(value.primary_identity, '$id');
  assert.deepEqual(value.target_schema.fields, {$id: {nullable: false, type: 'string'},
    Subject: {nullable: true, type: 'string'}});
  assert.deepEqual(value.writable_fields, []);
  assert.deepEqual(value.row_mapping, {});
  assert.deepEqual(value.permission_rules, [{effect_kind: 'delete',
    permissions: ['kintone:records:delete'], selector_class: 'id', write_fields: []}]);
  assert.equal(value.minimum_approval, 'required');
  assert.equal(moon.clientProgramKintoneDeleteMappingMatchesDeclaration(owned, original), true);
});

test('actual original matching rejects equal foreign declaration, Catalog and incomplete page', () => {
  const first = catalog(), original = declaration(first), owned = mapping(original);
  assert.equal(moon.clientProgramKintoneDeleteMappingMatchesRequest(owned, request(first)), true);
  assert.equal(moon.clientProgramKintoneDeleteMappingMatchesDeclaration(owned, declaration(first)), false);
  assert.equal(moon.clientProgramKintoneDeleteMappingMatchesRequest(owned, request(catalog())), false);
  assert.equal(moon.clientProgramKintoneDeleteMappingMatchesRequest(owned, request(first, [])), false);
  assert.equal(moon.clientProgramKintoneDeleteBody(request(first)),
    '{"app":"12","ids":["9007199254740993"],"revisions":["9007199254740994"]}');
});

test('actual Mapping Owner refuses foreign resource, invalid approval and zero ceiling', () => {
  const original = declaration(catalog());
  for (const [resource, approval, maxBytes] of [
    ['foreign', 'required', 100000], ['inquiries', 'allow', 100000], ['inquiries', 'required', 0],
  ]) assert.equal(runtimeIsError(moon.clientProgramKintonePrepareDeleteMapping(original,
    resource, approval, moon.clientProgramKintoneDeclarationLimits(maxBytes, 10000, 32, 1, 8))), true);
});
