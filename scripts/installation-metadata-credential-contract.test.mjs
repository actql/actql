import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import {project, structuralValidatorSource} from './generate-client-publication-wire.mjs';

const load = name => JSON.parse(readFileSync(new URL('../' + name, import.meta.url)));
const contract = load('spec/contracts/actql-installation-metadata-credential.json');
const vectors = load('spec/contracts/fixtures/installation-metadata-credential-vectors.json');
const digest = wire => 'sha256:' + createHash('sha256').update(wire).digest('hex');
// Resolve this finite contract's local definitions only. The reused structural
// validator deliberately does not claim canonical bytes, UTF16/UTF8 workspace,
// opaque originals, current authority or a durable physical claim.
function structural(schema) {
  if (schema.$ref) {
    assert.match(schema.$ref, /^#\/\$defs\/[^/]+$/u);
    return structural(contract.$defs[schema.$ref.slice('#/$defs/'.length)]);
  }
  const plain = Object.fromEntries(Object.entries(schema).filter(([key]) => !key.startsWith('x-actql-')));
  if (plain.properties) plain.properties = Object.fromEntries(Object.entries(plain.properties)
    .map(([key, value]) => [key, structural(value)]));
  return plain;
}
const shapes = Object.fromEntries(Object.entries(contract.schemas).map(([key, value]) => [key, project(structural(value))]));
const valid = new Function(structuralValidatorSource({extended: true}) + '\nreturn valid;')();
const subject = JSON.parse(vectors.subject_wire);
const grant = JSON.parse(vectors.grant_wire);

test('installation subject and grant retain independent exact literal bytes and machine pins', () => {
  assert.equal(machineCid(contract), vectors.contract_cid);
  for (const name of ['subject', 'grant']) {
    const body = JSON.parse(vectors[name + '_wire']);
    assert.equal(machineCid(contract.schemas[name]), vectors[name + '_schema_cid']);
    assert.equal(valid(body, shapes[name]), true);
    assert.deepEqual(Object.keys(body), contract.schemas[name].required.toSorted());
    assert.equal(JSON.stringify(body), vectors[name + '_wire']);
    assert.equal(digest(vectors[name + '_wire']), vectors[name + '_cid']);
  }
  assert.equal(grant.preparation_subject_cid, vectors.subject_cid);
  assert.equal(digest(vectors.use_wire), vectors.use_cid);
  assert.equal(JSON.parse(vectors.use_wire).grant_cid, vectors.grant_cid);
});

test('closed installation alternatives reject missing null Run and invented original fields', () => {
  for (const [name, original] of [['subject', subject], ['grant', grant]]) {
    for (const key of contract.schemas[name].required) {
      const missing = {...original}; delete missing[key];
      assert.equal(valid(missing, shapes[name]), false, `${name}/${key}/missing`);
      assert.equal(valid({...original, [key]: null}, shapes[name]), false, `${name}/${key}/null`);
    }
    for (const key of ['run_invocation_cid', 'task_attempt', 'dispatch_request_cid',
      'host_adoption_cid', 'authority_scope_cid', 'credential_installation_cid']) {
      assert.equal(valid({...original, [key]: 'invented'}, shapes[name]), false, key);
    }
  }
  for (const key of ['account_configuration_cid', 'declaration_source_cid', 'runtime_bundle_cid']) {
    assert.equal(valid({...subject, [key]: 'declaration-name'}, shapes.subject), false, key);
  }
});

test('metadata schema keeps exact GET empty-body purpose and finite scalar boundaries', () => {
  for (const request_method of ['POST', 'PATCH', 'DELETE']) assert.equal(valid({...grant, request_method}, shapes.grant), false);
  for (const request_path of ['//foreign', '/path?query=x', '/path#fragment', '/path\r\n', '/\0'])
    assert.equal(valid({...grant, request_path}, shapes.grant), false, request_path);
  for (const resource_origin of ['http://example.test', 'https://user@example.test', 'https://example.test/path', 'https://example.test?query'])
    assert.equal(valid({...grant, resource_origin}, shapes.grant), false, resource_origin);
  assert.equal(valid({...grant, request_body_cid: 'sha256:' + 'a'.repeat(64)}, shapes.grant), false);
  assert.equal(valid({...grant, subject_kind: 'run'}, shapes.grant), false);
  for (const max_uses of [0, 1025, 1.5, '1']) assert.equal(valid({...grant, max_uses}, shapes.grant), false);
  for (const site_generation of [-1, 2147483648, 1.5, '1']) assert.equal(valid({...subject, site_generation}, shapes.subject), false);
});

test('source identity and original occurrence differences remain identity relevant without normalization', () => {
  for (const principal of ['e\u0301\r\n', 'é\r\n', 'e\u0301\n']) {
    assert.equal(valid({...subject, principal}, shapes.subject), true);
  }
  assert.notEqual(digest(JSON.stringify({...subject, principal: 'e\u0301\r\n'})),
    digest(JSON.stringify({...subject, principal: 'é\r\n'})));
  for (const key of ['connection', 'principal', 'installation_request_id', 'connector_revision', 'site_key']) {
    assert.notEqual(digest(JSON.stringify({...subject, [key]: 'foreign'})), vectors.subject_cid);
  }
  for (const key of ['metadata_occurrence_id', 'operation', 'request_path']) {
    assert.notEqual(digest(JSON.stringify({...grant, [key]: 'foreign'})), vectors.grant_cid);
  }
});
