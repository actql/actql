// Actual Common Plan DATA controls; no native database, process, capture or
// business operation runs here. The ordinary CTAS case supplies that boundary.
import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import * as moon from '../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {createInstalledTableEffect} from './installed-table-effect.mjs';
import {createIcebergPhysicalBridge} from '../connectors/local/host/iceberg-process.mjs';
import {withFixtureConnector} from '../host-common/connector-manifest.fixture.mjs';
import {canonicalJson, contentCid} from './local-account-config.mjs';
import {checked} from '../host-common/runtime-result.mjs';
import {runtimeField, runtimeIsError} from '../host-common/compiler-binding.generated.mjs';
const cid = digit => `sha256:${digit.repeat(64)}`;
const targetRef = 'connector://table/catalog', mappingRef = 'mapping:table.catalog.v1';
async function tablePlanFixture(empty) {
  const body = JSON.parse(await readFile(new URL('../../packages/sdk/fixtures/values.environment.json', import.meta.url), 'utf8'));
  const manifest = withFixtureConnector(body, targetRef);
  const targetSchema = {additional_properties: false, nullable: false, type: 'object',
    fields: {Id: {nullable: false, type: 'number'}, Name: {nullable: true, type: 'number'}}};
  const mapping = {connector_manifest_cid: manifest, conversions: [], mapping_ref: mappingRef,
    minimum_approval: 'required', permission_rules: [{effect_kind: 'store', permissions: ['scope:store'],
      selector_class: 'none', write_fields: ['Name']}], primary_identity: 'Id', required_fields: [],
    required_permissions: [], resource_identity_cid: cid('b'),
    row_mapping: {Name: {field: 'id', null_behavior: 'reject'}},
    schema: 'actql.mapping_contract/0.1', target_ref: targetRef, target_schema: targetSchema,
    target_schema_identity: contentCid(targetSchema), version: 'reference-v1', writable_fields: ['Name']};
  mapping.mapping_contract_cid = contentCid(mapping);
  body.mapping_contracts = [mapping];
  delete body.evidence_bundle_cid;
  body.evidence_bundle_cid = contentCid(body);
  const environment = moon.clientProgramCheckEnvironment(canonicalJson(body), body.evidence_bundle_cid,
    false, false, true, false, false, false, false);
  assert.ok(environment);
  const document = {version: 'actql/0.1', id: 'whole-table-demand', stages: [{id: 'source', inputs: {},
    steps: [{values: {schema: {id: {nullable: false, type: 'number'}},
      rows: empty ? [] : [{id: 1}]}, as: 'rows'}],
    results: {}, table_inputs: {rows: {from: 'rows', fields: ['id']}},
    effects: Object.fromEntries(['first', 'second'].map(id => [id,
      {store: {target: targetRef, mapping: mappingRef, from: {table_input: 'rows'}}}]))}], results: {}};
  const preparation = moon.clientProgramPrepareEffectComputationWithParameters(
    JSON.stringify(document), 'json', environment, undefined, []);
  const prepared = moon.clientProgramEffectPreparationReady(preparation);
  assert.ok(prepared, 'the original VALUES/Table computation is admitted');
  return {moon, prepared, fixture: {mappingCid: mapping.mapping_contract_cid},
    directory: await mkdtemp(join(tmpdir(), 'actql-table-plan-data-'))};
}

for (const empty of [false, true]) {
  test(`Table managed demand keeps one whole-Relation dispatch per ${empty ? 'empty' : 'nonempty'} member`,
    async t => {
        const f = await tablePlanFixture(empty);
        const {moon} = f;
        const bridge = createIcebergPhysicalBridge({python: new URL('file:///usr/bin/python3'),
          run: 'table-managed-demand', catalog: {database: join(f.directory, 'catalog.db'),
            warehouse: join(f.directory, 'warehouse'), catalogCid: cid('3'),
            limits: {bytes: 1048576, files: 16, operations: 8}}});
        const options = {moon, environmentWire: '{}', connectorId: 'table',
          connectorRegistration: 'table', connectorRevision: 'table/0.1', connection: 'table',
          runtimeBundleCid: cid('8'), bindingCid: cid('9'), catalogCid: cid('3'),
          targets: ['first', 'second'].map((effectId, index) => ({effectId,
            resource: 'catalog', targetRef, mappingRef, mappingCid: f.fixture.mappingCid,
            action: 'create', catalogCid: cid('3'), namespace: ['analytics'],
            tableName: `rows_${index}`, expectedTable: null, permissions: ['scope:store'],
            footprint: {kind: 'collection', resource_identity_scheme_cid: cid('f'),
              provider_namespace: 'table', provider_boundary_cid: cid(String(index)),
              resource_kind: 'Table', provider_object_identity_cids: []}})), bridge,
          authorization: {authorize() {assert.fail('Plan DATA cannot authorize');}},
          ledgerRoot: join(f.directory, 'managed-table-ledger'),
          limits: {maxMembers: 2, maxInputBytes: 4096,
            preview: {maxWireBytes: 65536, maxNodes: 4096, maxDepth: 16}}};
        const factory = await createInstalledTableEffect(options);
        const identity = moon.clientProgramEffectRequestIdentity(f.prepared, cid('e'), 'table-demand', cid('b'));
        const compilation = checked(moon.clientProgramCompileLocalEffects(f.prepared));
        const [registry, contract] = await Promise.all([
          readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json', import.meta.url), 'utf8'),
          readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url), 'utf8'),
        ]);
        const values = JSON.stringify(JSON.parse(contract).execution_contracts['REL.values']);
        const inputs = {values, installedContracts: checked(
          moon.clientPrepareInstalledSequenceContracts(registry, values, undefined, undefined))};
        const facts = Object.freeze({prepared: f.prepared, identity, compilation});
        const plan = factory.prepareManagedPlan(facts, inputs);
        const shape = moon.clientProgramInstalledEffectManagedPlanShape(plan);
        assert.equal(runtimeField(shape, 1), 2);
        if (empty) assert.equal(runtimeField(shape, 0), 0);
        else assert.ok(runtimeField(shape, 0) > 0);
        for (const index of [0, 1]) {
          const write = checked(moon.clientProgramInstalledEffectManagedPlanOperation(
            plan, index, false, 2, 'table.commit'));
          assert.equal(moon.clientProgramInstalledEffectOperationExtentPhysical(write), true);
          assert.equal(moon.clientProgramInstalledEffectOperationExtentTransfer(write),
            2n * (BigInt(bridge.frameLimits.maxBytes) + 4n));
          // No operation slot per input row: zero rows still have this same
          // whole-Relation member, and nonempty Relations cannot multiply sends.
          assert.equal(runtimeIsError(moon.clientProgramInstalledEffectManagedPlanOperation(
            plan, index, true, 0, 'table.commit')), true);
          assert.equal(runtimeIsError(moon.clientProgramInstalledEffectManagedPlanOperation(
            plan, index, false, 2, 'foreign-operation')), true);
        }
        const missing = await createInstalledTableEffect({...options,
          ledgerRoot: join(f.directory, 'unfunded-table-ledger'),
          bridge: {...bridge, effectPlanConstruction: undefined}});
        assert.throws(() => missing.prepareManagedPlan(facts, inputs),
          {code: 'InstalledPhysicalWriteConstructionUnavailable'});
        const unrepresentable = await createInstalledTableEffect({...options,
          ledgerRoot: join(f.directory, 'invalid-table-ledger'),
          limits: {...options.limits, maxInputBytes: 2147483648}});
        assert.throws(() => unrepresentable.prepareManagedPlan(facts, inputs),
          {code: 'InstalledTableConstructionUnavailable'});
        // The existing native quantity Owner also rejects an actually
        // unrepresentable construction, rather than replacing it with zero.
        const overflowing = await createInstalledTableEffect({...options,
          ledgerRoot: join(f.directory, 'overflow-table-ledger'), bridge: {...bridge,
            effectPlanConstruction: Object.freeze({retained: Object.freeze({
              nodes: 1n << 63n, text: 0n, wire: 0n}), workspace: Object.freeze({
              nodes: 0n, text: 0n, wire: 0n})})}});
        assert.throws(() => overflowing.prepareManagedPlan(facts, inputs), {code: 'MoonBitHostFailure'});
      });
}

