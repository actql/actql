// Shared real Iceberg/Catalog fixture; setup grants no Program or Effect authority.
import {spawnSync} from 'node:child_process';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath, pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
import {canonicalText} from '../../../scripts/check-canonical-json.mjs';
import {machineCid} from '../../../scripts/actql-spec-family.mjs';
import {tableTestAsset, tableTestModule} from './table-test-modules.mjs';
const moon = await tableTestModule(new URL(
  '../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', import.meta.url),
'@actql/local-node/runtime');
const {runtimeCore} = await tableTestModule(new URL('../../host-common/runtime-core.mjs', import.meta.url),
  'adapters/host-common/runtime-core.mjs');
const {openEffectLedger} = await tableTestModule(new URL('../effect-ledger.mjs', import.meta.url),
  'adapters/host-node/effect-ledger.mjs');
const {createIcebergPhysicalBridge} = await tableTestModule(new URL('../../connectors/local/host/iceberg-process.mjs', import.meta.url),
  'adapters/connectors/local/host/iceberg-process.mjs');
const python = pathToFileURL(process.env.ACTQL_TABLE_PYTHON ?? fileURLToPath(new URL('../../../.venv-table/bin/python', import.meta.url)));
const directory = await tableTestAsset(new URL('../../connectors/local/iceberg/', import.meta.url), 'adapters/connectors/local/iceberg');
const cid = digit => 'sha256:'+digit.repeat(64);
const control = runtimeCore(moon).effectApplicationControl;
const seal = (value, field) => ({...value, [field]: machineCid(value)});

export async function tablePhysicalFixture(t, entry) {
  const root = await mkdtemp(join(tmpdir(), 'actql-table-process-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const catalog = {database: join(root, 'catalog.db'), warehouse: join(root, 'warehouse'),
    catalogCid: cid('3'), limits: {bytes: 16777216, files: 256, operations: 32}};
  // Explicit Host installation setup. No operation or user data is written.
  const setup = spawnSync(fileURLToPath(python), ['-c',
    'import json,sys; from catalog import TableCatalog; c=json.loads(sys.argv[1]); t=TableCatalog(c["database"],c["warehouse"],c["catalogCid"],c["limits"]); t.create_namespace("test"); t.engine.dispose()',
    JSON.stringify(catalog)], {cwd: directory, encoding: 'utf8', timeout: 20000});
  assert.ifError(setup.error);
  assert.equal(setup.status, 0, setup.stderr);
  const mapping = JSON.parse(await readFile(new URL('../../connectors/local/iceberg/fixtures/presence-mapping.json', import.meta.url), 'utf8'));
  const schemaWire = (await readFile(new URL('../../connectors/local/iceberg/fixtures/presence-schema.json', import.meta.url), 'utf8')).trimEnd();
  const scope = control.logicalRequestScope(cid('a'), 'table-operation', 32);
  const operation = (action = 'create', expected = null, suffix = 'rows') => seal({
    version: 'actql-table-operation/0.1', logical_request_scope_cid: control.logicalRequestScopeCid(scope),
    effect_identity_cid: cid('2'), action, catalog_identity_cid: catalog.catalogCid,
    namespace: ['test'], table_name: suffix, expected_table: expected,
    input_artifact_cid: cid('4'), input_relation_cid: cid('5'),
    schema_cid: mapping.schema_cid, storage_mapping_cid: mapping.mapping_cid,
    data_policy_cid: cid('6')}, 'request_cid');
  const bridge = createIcebergPhysicalBridge({python, run: 'table-run', catalog, ...(entry ? {entry} : {})});
  const prepare = (operation, rows) => bridge.prepareWrite({operation, mapping, rows, schemaWire,
    reservation: {bytes: 1048576, files: 16}});
  const claim = operation => {
    // One logical whole-Relation operation; no per-row content/item key. This
    // test constructs a common claim directly, not a Program approval fixture.
    const key = control.dispatchKey(scope, cid('b'), canonicalText({operation: operation.request_cid}), 256, 16, 4);
    const locator = control.logicalItemLocator(scope, 'program-1', 'node-1', 'Store',
      canonicalText({operation: operation.request_cid}), 256, 512, 16, 4);
    const basis = control.ledgerBasis(scope, locator, key, cid('c'), cid('d'), cid('e'),
      operation.request_cid, cid('0'), 'unavailable', cid('1'), cid('2'));
    return {scope, locator, key, basis, intentFingerprintCid: cid('e'), canonicalRequestCid: operation.request_cid};
  };
  const open = () => openEffectLedger({moon, root: join(root, 'ledger'), authorityScopeCid: cid('a'),
    callerRequestId: 'table-operation', maxEntryBytes: 4096});
  return {root, catalog, mapping, schemaWire, operation, bridge, prepare, claim, open};
}
