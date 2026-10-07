// Local Connector Table Source and Effect installation. The generic Host
// selects the declared roles; Programs cannot supply paths or authority.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {pathToFileURL} from 'node:url';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checkpointApprovalFacts} from '../../../host-common/checkpoint-approval.mjs';
import {composeInstalledCheckEnvironment} from '../../../host-node/installed-check-environment.mjs';
import {installRowSourceAuthorization} from '../../../host-node/installed-row-source.mjs';
import {createInstalledTableSource} from '../../../host-node/installed-table-source.mjs';
import {createInstalledTableEffect, checkInstalledTableEffectLimits} from '../../../host-node/installed-table-effect.mjs';
import {createIcebergPhysicalBridge} from './iceberg-process.mjs';
import {encodeProcessFrame} from '../../../host-node/process-frames.mjs';

export const INSTALLED_TABLE_SOURCE_VERSION = 'actql-installed-local-table-source/0.1';
export const INSTALLED_TABLE_EFFECT_VERSION = 'actql-installed-local-table-effect/0.1';
const registration = 'local', revision = 'local/0.1';
const fail = (code, cause) => { throw Object.assign(new TypeError(code, {cause}), {code}); };
const text = value => typeof value === 'string' && value.length > 0;
const cid = value => /^sha256:[0-9a-f]{64}$/u.test(value ?? '');
const keys = (value, names) => value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...names].sort().join(',');
const dataWire = value => canonicalJson(value, {dataKeys: true});
const dataCid = value => `sha256:${createHash('sha256').update(dataWire(value)).digest('hex')}`;
const deepFreeze = value => {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
};
const snapshot = value => {
  try {
    return JSON.parse(encodeProcessFrame(value,
      {maxBytes: 8 * 1024 * 1024, maxNodes: 100000, maxDepth: 64})
      .subarray(4).toString('utf8'));
  } catch (cause) { fail('InvalidInstalledTableProfile', cause); }
};
const bridgeOf = profile => createIcebergPhysicalBridge({
  python: pathToFileURL(profile.python), run: 'installed-table', catalog: profile.catalog});

function commonProfile(profile, version, extraKeys) {
  const value = snapshot(profile);
  if (!keys(value, ['version', 'connectorId', 'connection', 'python', 'catalog',
    'accountConfigurationWire', 'targets', 'limits', ...extraKeys]) ||
      value.version !== version || !text(value.connectorId) || !text(value.connection) ||
      !text(value.python) || !isAbsolute(value.python) ||
      !text(value.accountConfigurationWire) || value.limits === null ||
      typeof value.limits !== 'object' || Array.isArray(value.limits) ||
      !Array.isArray(value.targets) || value.targets.length < 1 || value.targets.length > 64) {
    fail('InvalidInstalledTableProfile');
  }
  // This validates the physical configuration without starting Python, opening
  // Catalog files or installing a dependency. Installation is not publication.
  const bridge = bridgeOf(value);
  return {value, bridge};
}

export function checkInstalledTableSourceProfile(profile) {
  const {value, bridge} = commonProfile(profile, INSTALLED_TABLE_SOURCE_VERSION, []);
  if (!keys(value.limits, ['maxPages', 'maxPageBytes', 'maxPageRows', 'maxCaptureRows']) ||
      Object.values(value.limits).some(bound => !Number.isSafeInteger(bound) || bound < 1 ||
        bound > 2147483647)) fail('InvalidInstalledTableProfile');
  for (const target of value.targets) {
    if (!keys(target, ['resource', 'selector', 'schemaWire']) || !text(target.resource) ||
        !text(target.schemaWire)) fail('InvalidInstalledTableReadTarget');
    bridge.checkReadSelector(target.selector);
  }
  if (new Set(value.targets.map(target => target.resource)).size !== value.targets.length) {
    fail('DuplicateInstalledTableReadTarget');
  }
  return deepFreeze(value);
}

export function checkInstalledTableEffectProfile(profile) {
  const {value} = commonProfile(profile, INSTALLED_TABLE_EFFECT_VERSION, ['environmentWire']);
  if (!text(value.environmentWire) || value.targets.length > 16) fail('InvalidInstalledTableProfile');
  checkInstalledTableEffectLimits(value.limits);
  for (const target of value.targets) {
    if (!keys(target, ['effectId', 'resource', 'targetRef', 'mappingRef', 'mappingCid',
      'action', 'catalogCid', 'namespace', 'tableName', 'expectedTable', 'permissions', 'footprint']) ||
        !['effectId', 'resource', 'targetRef', 'mappingRef', 'tableName'].every(key => text(target[key])) ||
        !cid(target.mappingCid) || target.catalogCid !== value.catalog.catalogCid ||
        !['create', 'replace'].includes(target.action) || !Array.isArray(target.namespace) ||
        target.namespace.length < 1 || target.namespace.length > 32 ||
        target.namespace.some(part => !text(part) || part.length > 256 || /[.\0\r\n]/u.test(part)) ||
        target.tableName.length > 256 || /[\0\r\n]/u.test(target.tableName) ||
        target.action === 'create' && target.expectedTable !== null ||
        target.action === 'replace' && (!keys(target.expectedTable, ['table_uuid', 'generation_cid']) ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test(target.expectedTable.table_uuid ?? '') ||
          !cid(target.expectedTable.generation_cid)) ||
        !Array.isArray(target.permissions) || target.permissions.length < 1 ||
        !target.permissions.every(text) || new Set(target.permissions).size !== target.permissions.length ||
        !target.footprint) fail('InvalidInstalledTableTarget');
  }
  return deepFreeze(value);
}

// The generic installation identity canonicalizes descriptive strings. An
// additional exact-data digest prevents that from aliasing different physical
// namespace/name values. No operation, Table head or data receipt is inferred.
function identityParts(profile, checked) {
  return [{...profile, accountConfigurationWire: JSON.parse(checked.accountConfigurationWire)},
    {exact_table_profile_cid: dataCid(checked)}];
}
export function installedTableSourceIdentityParts(profile, providerProfile) {
  return identityParts(profile, checkInstalledTableSourceProfile(providerProfile));
}
export function installedTableEffectIdentityParts(profile) {
  return identityParts(profile, checkInstalledTableEffectProfile(profile));
}

// No external credential is needed for local Catalog I/O. This Site only
// admits decisions issued by the installed gate or the existing Checkpoint
// owner for this exact physical binding. It is not an approval/Run owner.
export function installedTableReadSite({connection, authorization, principalId, targets}) {
  let closed = false;
  const approvals = new WeakMap();
  const ensureOpen = () => { if (closed) fail('InstalledTableSiteClosed'); };
  return Object.freeze({connection,
    admitCheckpointReadApproval(decision) {
      ensureOpen();
      const facts = checkpointApprovalFacts(decision);
      const binding = facts?.physicalBinding;
      const target = targets().find(target => target.resource === decision?.tuple?.resource);
      if (!facts || !target || decision.action !== 'dispatch' || decision.basis !== 'resumed_approval' ||
          decision.boundary !== 'acquisition' || facts.principalId !== principalId ||
          facts.readTuple?.connection !== connection || facts.readTuple?.operation !== 'read' ||
          facts.readTuple?.resource !== target.resource || decision.tuple?.connection !== connection ||
          decision.tuple?.operation !== 'read' ||
          !keys(binding, ['version', 'catalog_cid', 'selector', 'selector_cid', 'resource', 'fields']) ||
          binding.version !== target.version || binding.catalog_cid !== target.catalog_cid ||
          binding.selector_cid !== target.selector_cid || dataWire(binding.selector) !== dataWire(target.selector) ||
          binding.resource !== target.resource || !Array.isArray(binding.fields) ||
          binding.fields.length === 0 ||
          new Set(binding.fields).size !== binding.fields.length ||
          binding.fields.some(field => !target.fields.includes(field))) fail('TableSourceReadApprovalNotAdmitted');
      approvals.set(decision, target.resource);
      return decision;
    },
    issueReadGrant({operation, decision, resource, runInvocationCid, dispatchRequestCid, maxUses}) {
      ensureOpen();
      if (operation !== 'table.read' || !cid(runInvocationCid) || !cid(dispatchRequestCid) ||
          !Number.isSafeInteger(maxUses) || maxUses < 1 ||
          !targets().some(target => target.resource === resource) ||
          decision?.action !== 'dispatch' || decision.boundary !== 'acquisition' ||
          decision.tuple?.connection !== connection || decision.tuple?.resource !== resource ||
          decision.tuple?.operation !== 'read' ||
          (approvals.get(decision) !== resource &&
            (!authorization.issued(decision) || decision.contextCid !== authorization.context.contextCid))) {
        fail('TableSourceReadGrantNotAuthorized');
      }
      return Object.freeze({runInvocationCid, dispatchRequestCid});
    },
    close() { closed = true; },
  });
}

const binding = (profile, root, principalId) => dataCid({
  version: 'actql-installed-table-host-binding/0.1', root, principalId,
  connection: profile.connection, python: profile.python, catalog: profile.catalog,
  connectorId: profile.connectorId, targets: profile.targets});

export async function loadInstalledTableSource(profile, {root, principalId, moon, baseEnvironmentWire}) {
  const checkedProfile = checkInstalledTableSourceProfile(profile);
  const authorization = await installRowSourceAuthorization({
    accountConfiguration: checkedProfile.accountConfigurationWire, root, principalId,
    connectorRegistration: registration});
  let installedTargets = [];
  const site = installedTableReadSite({connection: checkedProfile.connection, authorization,
    principalId, targets: () => installedTargets});
  try {
    const adapter = await createInstalledTableSource({moon, baseEnvironmentWire,
      connectorId: checkedProfile.connectorId, connectorRegistration: registration,
      connectorRevision: revision, site, authorization,
      bridge: bridgeOf(checkedProfile), targets: checkedProfile.targets, limits: checkedProfile.limits});
    installedTargets = adapter.tableReadTargets;
    return Object.freeze({...adapter, connectorBindings: Object.freeze([Object.freeze({
      connectorId: checkedProfile.connectorId, bindingCid: binding(checkedProfile, root, principalId)})])});
  } catch (cause) { site.close(); throw cause; }
}

export async function loadInstalledTableEffect(profile, {root, ledgerRoot, principalId,
  moon, runtimeBundleCid, baseEnvironmentWire}) {
  const checkedProfile = checkInstalledTableEffectProfile(profile);
  const environmentWire = composeInstalledCheckEnvironment(moon, baseEnvironmentWire,
    undefined, checkedProfile.environmentWire);
  const environment = JSON.parse(environmentWire);
  if (!environment.connector_catalogs.some(catalog => catalog.connector_id === checkedProfile.connectorId)) {
    fail('InstalledTableMappingNotInstalled');
  }
  for (const target of checkedProfile.targets) {
    const mapping = environment.mapping_contracts.find(value => value.mapping_ref === target.mappingRef);
    if (!mapping || mapping.mapping_contract_cid !== target.mappingCid || mapping.target_ref !== target.targetRef ||
        !target.targetRef.startsWith(`connector://${checkedProfile.connectorId}/`) ||
        mapping.minimum_approval !== 'required' ||
        !mapping.permission_rules.some(rule => rule.effect_kind === 'store' && rule.selector_class === 'none')) {
      fail('InstalledTableMappingNotInstalled');
    }
  }
  const authorization = await installRowSourceAuthorization({
    accountConfiguration: checkedProfile.accountConfigurationWire, root, principalId,
    connectorRegistration: registration});
  return createInstalledTableEffect({moon, environmentWire,
    connectorId: checkedProfile.connectorId, connectorRegistration: registration,
    connectorRevision: revision, connection: checkedProfile.connection,
    runtimeBundleCid, bindingCid: binding(checkedProfile, root, principalId),
    catalogCid: checkedProfile.catalog.catalogCid, targets: checkedProfile.targets,
    bridge: bridgeOf(checkedProfile), authorization, ledgerRoot, limits: checkedProfile.limits});
}
