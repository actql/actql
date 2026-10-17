// Real Common capture, SQLite request/publication journals and the existing
// generic Row Effect. The finite observation driver below is not a Provider,
// installed kintone, token send or a new approval/cleanup Owner.
import assert from 'node:assert/strict';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {canonicalJson} from './local-account-config.mjs';
import {createInstalledRowEffect} from './installed-row-effect.mjs';
import {installRowSourceAuthorization, openRowSourceCredentialSite} from './installed-row-source.mjs';
import {effectHost} from './fixtures/installed-row-effect.fixture.mjs';

const repo = new URL('../../', import.meta.url);
const cid = value => 'sha256:' + createHash('sha256').update(
  typeof value === 'string' || Buffer.isBuffer(value) ? value : canonicalJson(value)).digest('hex');
const program = mapping => ({version: 'actql/0.1', id: 'original-generic-upsert', stages: [{
  id: 'source', inputs: {}, steps: [{values: {schema: {
    id: {type: 'string', nullable: false}, value: {type: 'string', nullable: false}},
  rows: [{id: 'original-id', value: 'original before'}]}, as: 'selected'}],
  results: {rows: {from: 'selected', fields: ['id', 'value']}},
  effects: {save: {upsert: {target: mapping.target_ref, mapping: mapping.mapping_ref,
    from: {result: 'rows'}, id: 'id', set: {id: {field: 'id'}, value: {field: 'value'}}}}}}],
results: {answer: {from: {stage: 'source', result: 'rows'}}}});

async function fixture(t, {kind = 'upsert', observation = 'absent', targetSubstitution = false} = {}) {
  const parent = new URL('../../_build/generic-row-upsert-fixtures/', import.meta.url);
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent.pathname, 'capture-'));
  const closes = [], state = {observation, grants: 0, observations: 0, sends: 0, version: cid('original version')};
  let site;
  t.after(async () => {
    const errors = [];
    for (const close of closes.reverse()) try {await close();} catch (cause) {errors.push(cause);}
    try {site?.close();} catch (cause) {errors.push(cause);}
    t.diagnostic(`Retained owned generic UPSERT capture: ${root}`);
    if (errors.length) throw new AggregateError(errors, 'OriginalDeleteCaptureCleanupUnconfirmed');
  });
  // Explicit trusted test installation DATA, admitted by the real Common
  // checker below. No vendor uniqueness, remote observation or grant is
  // inferred from these independently authored schema/Mapping declarations.
  const manifest = {version: 'actql-connectors/0.1', connectors: [
    {connector: 'fixture', connector_id: 'archive', connector_version: 'fixture-1'}]};
  const catalog = {schema: 'actql.connector_catalog/0.1', connector_id: 'archive',
    connector_version: 'fixture-1', commands: [], contracts: [], source_views: []};
  const schema = {type: 'object', nullable: false, additional_properties: false,
    fields: {id: {type: 'string', nullable: false}, value: {type: 'string', nullable: false}}};
  const preimage = {schema: 'actql.mapping_contract/0.1', version: 'fixture-1',
    mapping_ref: 'mapping:fixture.upsert.v1', target_ref: 'connector://archive/records',
    connector_manifest_cid: cid(manifest.connectors[0]), target_schema: schema,
    target_schema_identity: cid(schema), resource_identity_cid: cid('fixture record identities'),
    primary_identity: 'id', required_fields: ['id', 'value'], writable_fields: ['id', 'value'],
    required_permissions: [], minimum_approval: 'required', conversions: [],
    row_mapping: {id: {field: 'id', null_behavior: 'reject'}, value: {field: 'value', null_behavior: 'reject'}},
    permission_rules: [{effect_kind: kind, permissions: ['fixture:upsert'],
      selector_class: 'id', write_fields: ['id', 'value']}]};
  const mapping = {...preimage, mapping_contract_cid: cid(preimage)};
  const {evidence_bundle_cid: _, ...base} = JSON.parse(await readFile(new URL('spec/local-check-environment.json', repo)));
  const environment = {...base, connector_manifest: manifest,
    connector_catalogs: [{...catalog, catalog_cid: cid(catalog)}], mapping_contracts: [mapping]};
  const environmentWire = canonicalJson({...environment, evidence_bundle_cid: cid(environment)});
  const accountConfiguration = canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'original-upsert-fixture', entries: [{entry_id: 'reads', outcome: 'allow',
      principal: {all: true}, connection: {any_of: ['fixture:archive']},
      resource: {any_of: ['records']}, operation: {any_of: ['read']}, exclusions: []}]});
  const authorization = await installRowSourceAuthorization({root, principalId: 'principal-a',
    connectorRegistration: 'fixture', accountConfiguration});
  const authority = generateKeyPairSync('ed25519');
  const key = join(root, 'credential.key');
  await writeFile(key, authority.privateKey.export({format: 'pem', type: 'pkcs8'}), {mode: 0o600});
  const runtimeBundleCid = cid(await readFile(new URL('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', repo)));
  site = await openRowSourceCredentialSite({profile: {credentialPrivateKeyPath: key,
    credentialAuthorityId: 'fixture-authority', credentialKeyId: 'fixture-key',
    journalRoot: join(root, 'credential-journal'), resourceOrigin: 'https://fixture.invalid',
    namespaceId: 'namespace-a', environment: 'test', siteKey: 'original-site', siteGeneration: 1},
    principalId: 'principal-a', authorization, connection: 'fixture:archive',
    connectorRegistration: 'fixture', connectorRevision: 'fixture-1', runtimeBundleCid,
    commonMoon: moon, admitsApprovalTarget: () => false,
    resolveSecret: async () => assert.fail('This capture test performs no Provider I/O')});
  const requestCid = request => cid(request);
  const effect = await createInstalledRowEffect({moon, environmentWire,
    mappings: [{resource: 'records', mappingRef: mapping.mapping_ref,
      mappingCid: mapping.mapping_contract_cid, body: canonicalJson(mapping)}],
    connectorId: 'archive', connectorRegistration: 'fixture', connectorRevision: 'fixture-1',
    connection: 'fixture:archive', site, authorization, runtimeBundleCid,
    bindingCid: cid('original fixture installation'), ledgerRoot: join(root, 'effect-ledger'),
    driver: {
      kinds: Object.freeze([kind]), targetRead: Object.freeze({operation: 'fixture:records:observe'}),
      writeOperation: () => 'fixture:records:upsert',
      prepareRequest({value, selector}) {
        const request = Object.freeze({target: selector, value: structuredClone(value)});
        return {request, requestCid: requestCid(request)};
      },
      requestFacts: request => ({target: request.target, value: request.value}),
      recheckRequests() {},
      async observeTargets({entries, authorizationForRow}) {
        const observations = [];
        for (const [index, entry] of entries.entries()) {
          const grant = await authorizationForRow(index);
          assert.equal(grant.scope.operation, 'fixture:records:observe');
          state.grants++; state.observations++;
          observations.push({identity: targetSubstitution ? 'foreign-id' : entry.target,
            ...(state.observation === 'absent' ? {state: 'absent'} :
              {versionCid: state.version, before: {id: 'original-id', value: 'original before'}})});
        }
        return observations;
      },
      footprint: () => ({kind: 'opaque', provider_namespace: 'fixture', resource_kind: 'records',
        provider_boundary_cid: cid('fixture boundary'),
        resource_identity_scheme_cid: cid('fixture original-id scheme'),
        provider_object_identity_cids: []}),
      requestCid,
      recoveryEntry: ({entries}) => ({kind: 'fixture-upsert-originals',
        observationCid: state.version, wire: canonicalJson({requests: entries.map(entry => entry.request)})}),
      recoverRequests() {assert.fail('Recovery is a separate physical consuming acceptance');},
      send() {state.sends++; assert.fail('A captured required-approval Set cannot send');},
      project() {assert.fail('No Provider response exists in this capture test');},
    }});
  const host = await effectHost(t, {onClose: close => closes.push(close)}, join(root, 'host'),
    {effect, stopBeforeApply: true});
  return {root, effect, host, state, mapping};
}

test('actual Common captures original explicit UPSERT absence without a synthetic before value or version', async t => {
  const f = await fixture(t);
  const result = await f.host.run(program(f.mapping), 'original-upsert-absent');
  assert.equal(result.started.value.status, 'captured');
  const stage = f.host.outcomes[0].stage;
  const preview = JSON.parse(f.host.control.effectComputationPreviewWire(stage.preview));
  const member = preview.effects[0], row = member.changes[0];
  assert.equal(member.effect_kind, 'upsert'); assert.equal(member.preview_strength, 'full_diff');
  assert.equal(member.approval, 'required');
  assert.equal(row.target_row_identity, 'original-id');
  assert.deepEqual(row.before, {state: 'absent'});
  assert.deepEqual(row.target_guard, {state: 'not_applicable'});
  assert.deepEqual(row.after, {state: 'present', value: {id: 'original-id', value: 'original before'}});
  assert.deepEqual(row.intended_changes, row.after);
  assert.deepEqual(stage.apply.preflight.observedRows, []);
  const current = await stage.apply.refreshPreflight({preflight: stage.apply.preflight});
  assert.deepEqual(current.guardVersions, []);
  assert.equal(f.state.observations, 2); assert.equal(f.state.sends, 0);
});
