// Table-specific physical projection of the existing installed row Source.
// The caller installs the same current authorization/Site as other Sources;
// this adapter issues no grant, runs no task scheduler and owns no capture.
import {createHash} from 'node:crypto';
import {checked} from '../host-common/runtime-result.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {createInstalledRowSource, rowSourceCheckEnvironment} from './installed-row-source.mjs';

const fail = code => { throw Object.assign(new Error(code), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const keys = (value, names) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...names].sort().join(',');
const identifier = value => /^sha256:[0-9a-f]{64}$/u.test(value ?? '');
const dataCid = value => `sha256:${createHash('sha256')
  .update(canonicalJson(value, {dataKeys: true})).digest('hex')}`;
const closedReply = (value, resultKeys) => {
  if (value?.ok === false && keys(value, ['ok', 'code']) && text(value.code)) fail(value.code);
  if (!keys(value, ['ok', 'result']) || value.ok !== true ||
      resultKeys !== undefined && !keys(value.result, resultKeys)) fail('InvalidTableReadReply');
  return value.result;
};

// Installation binds saved schema and Table UUID/name. It never reads provider
// metadata during Check or uses observed rows to issue a declaration. A new
// acquisition resolves one immutable generation under current read authority.
export async function createInstalledTableSource({moon, baseEnvironmentWire,
  connectorId, connectorRegistration, connectorRevision,
  site, authorization, bridge, targets, limits}) {
  if (!moon || !text(baseEnvironmentWire) || !text(connectorId) ||
      !text(connectorRegistration) || !text(connectorRevision) ||
      !text(site?.connection) || typeof site?.issueReadGrant !== 'function' ||
      typeof authorization?.authorize !== 'function' ||
      !['checkReadSelector', 'resolveGeneration', 'read'].every(key => typeof bridge?.[key] === 'function') ||
      !Array.isArray(targets) || targets.length < 1 || targets.length > 64) {
    fail('InvalidInstalledTableSource');
  }
  const installed = targets.map(target => {
    if (!keys(target, ['resource', 'selector', 'schemaWire']) ||
        !text(target.resource) || typeof target.schemaWire !== 'string') fail('InvalidInstalledTableReadTarget');
    return Object.freeze({resource: target.resource,
      selector: bridge.checkReadSelector(target.selector), schemaWire: target.schemaWire});
  });
  if (new Set(installed.map(target => target.resource)).size !== installed.length) {
    fail('DuplicateInstalledTableReadTarget');
  }
  const specification = JSON.stringify({views: installed.map(target => ({
    resource: target.resource, resource_kind: 'table',
    schema_wire: target.schemaWire, schema_cid: target.selector.schema_cid,
  }))});
  const declaration = checked(moon.clientProgramRowSourceRestoreRelationDeclaration(
    connectorId, connectorRegistration, connectorRevision, specification, undefined));
  const declared = JSON.parse(moon.clientProgramRowSourceDeclarationJson(declaration));
  const environment = rowSourceCheckEnvironment(baseEnvironmentWire, declared);
  const byResource = new Map(installed.map(target => [target.resource, target]));
  const physicalTarget = (resource, fields) => {
    const target = byResource.get(resource);
    if (!target || fields.some(field => !declared.views.find(view =>
      view.resource === resource).fields.includes(field))) fail('InstalledTableReadTargetMismatch');
    return Object.freeze({version: 'actql-installed-table-read-target/0.1',
      catalog_cid: declared.catalog_cid, selector: target.selector,
      // Bind exact namespace/name bytes even when a containing configuration
      // owner normalizes descriptive strings. This is not an operation key.
      selector_cid: dataCid(target.selector),
      resource, fields: Object.freeze([...fields])});
  };
  // These are installed configuration identities, not Table content, operation
  // identity or an inference about whether an uncertain commit succeeded.
  const bindingCid = dataCid({version: 'actql-installed-table-read-binding/0.1',
    connection: site.connection, connectorId, connectorRegistration,
    connectorRevision, catalogCid: declared.catalog_cid,
    targets: installed.map(({resource, selector}) => ({resource, selector}))});
  const readPages = async ({resource, columns, signal, authorizationFor,
    chargePage, consumePage}) => {
    const target = byResource.get(resource);
    const view = declared.views.find(view => view.resource === resource);
    if (!target || columns.some(column => !view.fields.includes(column))) fail('InstalledTableReadTargetMismatch');
    signal?.throwIfAborted();
    await authorizationFor(0);
    const frozen = closedReply(await bridge.resolveGeneration(target.selector, signal),
      ['receipt', 'mapping', 'schema_wire']);
    signal?.throwIfAborted();
    // The physical owner verified its immutable metadata and publication record.
    // Bind their exact logical material to the common-issued installed schema;
    // never default or reconstruct primitive contracts from this response.
    if (frozen.schema_wire !== target.schemaWire ||
        frozen.receipt?.catalog_identity_cid !== target.selector.catalog_identity_cid ||
        frozen.receipt?.table_uuid !== target.selector.table_uuid ||
        frozen.receipt?.schema_cid !== target.selector.schema_cid ||
        frozen.mapping?.schema_cid !== target.selector.schema_cid ||
        frozen.mapping?.mapping_cid !== frozen.receipt?.storage_mapping_cid ||
        !identifier(frozen.receipt?.generation_cid)) fail('InstalledTableReadGenerationMismatch');
    // Re-evaluation after the metadata await and after the data await uses the
    // existing acquisition gate. It does not renew original Effect authority.
    await authorizationFor(1);
    signal?.throwIfAborted();
    const rows = closedReply(await bridge.read(frozen.receipt, frozen.mapping, signal));
    if (!Array.isArray(rows) || rows.length !== frozen.receipt.row_count) fail('InvalidTableReadReply');
    await authorizationFor(2);
    signal?.throwIfAborted();
    // Keep original objects: omitted fields remain omitted. The existing common
    // checked-input owner validates and captures the rows, including empty input.
    const bytes = Buffer.from(JSON.stringify(rows), 'utf8');
    const charge = chargePage(bytes);
    consumePage(rows, {charge});
  };
  const adapter = await createInstalledRowSource({moon, declaration, declared,
    environmentWire: environment.wire, connectorId, connectorRegistration,
    connectorRevision, site, authorization, readOperation: 'table.read',
    physicalTarget, readPages, bindingCid, limits});
  return Object.freeze({...adapter,
    // Read-only metadata for the existing Host installation/approval boundary.
    declarationCatalogCid: declared.catalog_cid,
    tableReadTargets: Object.freeze(installed.map(target => physicalTarget(target.resource,
      declared.views.find(view => view.resource === target.resource).fields))),
  });
}
