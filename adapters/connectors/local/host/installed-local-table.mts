// Local Connector Table Source and Effect installation. The generic Host
// selects the declared roles; Programs cannot supply paths or authority.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {pathToFileURL} from 'node:url';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {composeInstalledCheckEnvironment} from '../../../host-node/installed-check-environment.mjs';
// @ts-expect-error TS7016: the original Row Source still has an authored JavaScript entry.
import {installRowSourceAuthorization} from '../../../host-node/installed-row-source.mjs';
export {installedTableReadSite} from '../../../host-node/installed-table-source.mjs';
import {createInstalledTableEffect, checkInstalledTableEffectLimits} from '../../../host-node/installed-table-effect.mjs';
import {createIcebergPhysicalBridge, validateIcebergPhysicalConfiguration, validateIcebergReadSelector} from './iceberg-process.mjs';
import {snapshotProcessValue} from '../../../host-node/process-frames.mjs';
import {captureInstalledConnectorImplementation} from '../../../host-node/installed-connector-implementation.mjs';

type Data = Readonly<Record<string, unknown>>;
type PhysicalCatalog = Parameters<typeof validateIcebergPhysicalConfiguration>[0]['catalog'];
type Catalog = Omit<PhysicalCatalog, 'catalogCid'> & Readonly<{catalogCid: unknown}>;
type Selector = Parameters<typeof validateIcebergReadSelector>[0];
type Implementation = ReturnType<typeof captureInstalledConnectorImplementation>;
type Installation = Parameters<typeof captureInstalledConnectorImplementation>[0];
type Bridge = ReturnType<typeof createIcebergPhysicalBridge>;
type Target = Readonly<{
  effectId: string;
  resource: string;
  targetRef: string;
  mappingRef: string;
  mappingCid: unknown;
  catalogCid: unknown;
  action: 'create' | 'replace';
  namespace: readonly string[];
  tableName: string;
  expectedTable: Readonly<{table_uuid: unknown; generation_cid: unknown}> | null;
  permissions: readonly string[];
  queryName?: string;
  footprint: unknown;
}>;
type SourceTarget = Readonly<{resource: string; selector: unknown; schemaWire: string}>;
type SourceLimits = Readonly<Record<'maxPages' | 'maxPageBytes' | 'maxPageRows' | 'maxCaptureRows', number>>;
type Profile<Targets, Limits> = Readonly<{
  version: string;
  connectorId: string;
  connection: string;
  python: string;
  catalog: Catalog;
  accountConfigurationWire: string;
  targets: readonly Targets[];
  limits: Limits;
}>;
type SourceProfile = Profile<SourceTarget, SourceLimits>;
type EffectLimits = ReturnType<typeof checkInstalledTableEffectLimits>;
type EffectProfile = Profile<Target, EffectLimits> & Readonly<{environmentWire: string}>;
type LoaderInput = Readonly<{root: unknown; principalId: unknown; installation: Installation}>;
type SourceBinding = Pick<SourceProfile, 'connection' | 'targets' | 'limits'> & Readonly<{
  accountConfiguration: string;
  createBridge(): Bridge;
  publicationBindingCid: string;
}>;
type EffectBinding = Pick<EffectProfile, 'connection' | 'targets' | 'limits'> & Readonly<{
  accountConfiguration: string;
  bindingCid: string;
  catalogCid: unknown;
  createBridge(): Bridge;
  ledgerRoot: unknown;
}>;
type PublishedEnvironment = Readonly<{body: Readonly<{
  connector_catalogs: readonly Readonly<{connector_id?: unknown}>[];
  mapping_contracts: readonly Readonly<{
    mapping_ref?: unknown;
    mapping_contract_cid?: unknown;
    target_ref?: unknown;
    minimum_approval?: unknown;
    permission_rules: readonly Readonly<{effect_kind?: unknown; selector_class?: unknown}>[];
  }>[];
}>}>;

export const INSTALLED_TABLE_SOURCE_VERSION = 'actql-installed-local-table-source/0.1';
export const INSTALLED_TABLE_EFFECT_VERSION = 'actql-installed-local-table-effect/0.1';
const registration = 'local', revision = 'local/0.1';
const checkedSources = new WeakSet<SourceProfile>(), checkedEffects = new WeakSet<EffectProfile>();
const fail: (code: string, cause?: unknown) => never = (code, cause) => { throw Object.assign(new TypeError(code, {cause}), {code}); };
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0;
const cid = (value: unknown) => /^sha256:[0-9a-f]{64}$/u.test((value ?? '') as string);
const keys = (value: unknown, names: readonly string[]): value is Data => (value && typeof value === 'object' && !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...names].sort().join(',')) as boolean;
const dataWire = (value: unknown) => canonicalJson(value, {dataKeys: true});
const dataCid = (value: unknown) => `sha256:${createHash('sha256').update(dataWire(value)).digest('hex')}`;
const deepFreeze = <T,>(value: T): T => {
  if (value && typeof value === 'object') {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
};
const snapshot = (value: unknown) => {
  try {
    return snapshotProcessValue(value,
      {maxBytes: 8 * 1024 * 1024, maxNodes: 100000, maxDepth: 64});
  } catch (cause) { fail('InvalidInstalledTableProfile', cause); }
};
const bridgeOf = (profile: Pick<SourceProfile, 'python' | 'catalog'>, implementation: Implementation) => createIcebergPhysicalBridge({
  python: pathToFileURL(profile.python), run: 'installed-table', catalog: profile.catalog,
  implementation});
const selectedImplementation = (installation: Installation) => {
  if (installation?.registration !== registration || installation.revision !== revision) {
    fail('InstalledConnectorRegistrationMismatch');
  }
  return captureInstalledConnectorImplementation(installation);
};

function commonProfile(profile: unknown, version: string, extraKeys: readonly string[]) {
  const value = snapshot(profile);
  if (!keys(value, ['version', 'connectorId', 'connection', 'python', 'catalog',
    'accountConfigurationWire', 'targets', 'limits', ...extraKeys]) ||
      value.version !== version || !text(value.connectorId) || !text(value.connection) ||
      !text(value.python) || !isAbsolute(value.python) ||
      !text(value.accountConfigurationWire) || value.limits === null ||
      typeof value.limits !== 'object' || Array.isArray(value.limits) ||
      !Array.isArray(value.targets) || value.targets.length < 1) {
    fail('InvalidInstalledTableProfile');
  }
  // This validates the physical configuration without starting Python, opening
  // Catalog files or installing a dependency. Installation is not publication.
  validateIcebergPhysicalConfiguration({python: pathToFileURL(value.python), catalog: value.catalog as PhysicalCatalog});
  return {value: value as Data & Profile<unknown, Data>};
}

export function checkInstalledTableSourceProfile(profile: unknown): SourceProfile {
  if (checkedSources.has(profile as SourceProfile)) return profile as SourceProfile;
  const {value} = commonProfile(profile, INSTALLED_TABLE_SOURCE_VERSION, []);
  if (!keys(value.limits, ['maxPages', 'maxPageBytes', 'maxPageRows', 'maxCaptureRows']) ||
      Object.values(value.limits).some(bound => !Number.isSafeInteger(bound) || (bound as number) < 1 ||
        (bound as number) > 2147483647)) fail('InvalidInstalledTableProfile');
  for (const target of value.targets) {
    if (!keys(target, ['resource', 'selector', 'schemaWire']) || !text(target.resource) ||
        !text(target.schemaWire)) fail('InvalidInstalledTableReadTarget');
    validateIcebergReadSelector(target.selector as Selector, value.catalog.catalogCid as string);
  }
  if (new Set(value.targets.map(target => (target as SourceTarget).resource)).size !== value.targets.length) {
    fail('DuplicateInstalledTableReadTarget');
  }
  checkedSources.add(value as SourceProfile);
  return deepFreeze(value as SourceProfile);
}

export function checkInstalledTableEffectProfile(profile: unknown): EffectProfile {
  if (checkedEffects.has(profile as EffectProfile)) return profile as EffectProfile;
  const {value} = commonProfile(profile, INSTALLED_TABLE_EFFECT_VERSION, ['environmentWire']);
  if (!text(value.environmentWire) || value.targets.length > 16) fail('InvalidInstalledTableProfile');
  checkInstalledTableEffectLimits(value.limits);
  for (const target of value.targets as readonly Data[]) {
    const {queryName, ...fixedTarget} = target;
    if (queryName !== undefined && (!text(queryName) || queryName.length > 1024)) {
      fail('InvalidInstalledTableTarget');
    }
    if (!keys(fixedTarget, ['effectId', 'resource', 'targetRef', 'mappingRef', 'mappingCid',
      'action', 'catalogCid', 'namespace', 'tableName', 'expectedTable', 'permissions', 'footprint']) ||
        !['effectId', 'resource', 'targetRef', 'mappingRef', 'tableName'].every(key => text(target[key])) ||
        !cid(target.mappingCid) || target.catalogCid !== value.catalog.catalogCid ||
        !['create', 'replace'].includes(target.action as string) || !Array.isArray(target.namespace) ||
        target.namespace.length < 1 || target.namespace.length > 32 ||
        target.namespace.some(part => !text(part) || part.length > 256 || /[.\0\r\n]/u.test(part)) ||
        (target.tableName as string).length > 256 || /[\0\r\n]/u.test(target.tableName as string) ||
        target.action === 'create' && target.expectedTable !== null ||
        target.action === 'replace' && (!keys(target.expectedTable, ['table_uuid', 'generation_cid']) ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/u.test((target.expectedTable.table_uuid ?? '') as string) ||
          !cid(target.expectedTable.generation_cid)) ||
        !Array.isArray(target.permissions) || target.permissions.length < 1 ||
        !target.permissions.every(text) || new Set(target.permissions).size !== target.permissions.length ||
        !target.footprint) fail('InvalidInstalledTableTarget');
  }
  checkedEffects.add(value as EffectProfile);
  return deepFreeze(value as EffectProfile);
}

// The generic installation identity canonicalizes descriptive strings. An
// additional exact-data digest prevents that from aliasing different physical
// namespace/name values. No operation, Table head or data receipt is inferred.
function identityParts(profile: object, checked: SourceProfile | EffectProfile, installation: Installation) {
  return [{...profile, accountConfigurationWire: JSON.parse(checked.accountConfigurationWire)},
    {exact_table_profile_cid: dataCid(checked),
      connector_implementation_cid: selectedImplementation(installation).identity}];
}
export function installedTableSourceIdentityParts(profile: object, providerProfile: unknown, _read: unknown, installation: Installation) {
  return identityParts(profile, checkInstalledTableSourceProfile(providerProfile), installation);
}
export function installedTableEffectIdentityParts(profile: object, _read: unknown, installation: Installation) {
  return identityParts(profile, checkInstalledTableEffectProfile(profile), installation);
}

const binding = (profile: SourceProfile | EffectProfile, root: unknown, principalId: unknown, implementation: Implementation) => dataCid({
  version: 'actql-installed-table-host-binding/0.1', root, principalId,
  connection: profile.connection, python: profile.python, catalog: profile.catalog,
  connectorId: profile.connectorId, targets: profile.targets,
  connector_implementation_cid: implementation.identity});

export async function loadInstalledTableSource(profile: unknown, {root, principalId, installation, construction}:
  LoaderInput & Readonly<{construction?: Readonly<{createTableSource(options: SourceBinding):
    ReturnType<typeof import('../../../host-node/installed-table-source.mjs').createInstalledTableSource>}>}>) {
  if (construction === undefined || typeof construction.createTableSource !== 'function') {
    fail('InstalledTableSourceConstructionUnavailable');
  }
  const checkedProfile = checkInstalledTableSourceProfile(profile);
  const implementation = selectedImplementation(installation);
  return construction.createTableSource({accountConfiguration: checkedProfile.accountConfigurationWire,
    connection: checkedProfile.connection,
    createBridge: () => bridgeOf(checkedProfile, implementation),
    publicationBindingCid: binding(checkedProfile, root, principalId, implementation),
    targets: checkedProfile.targets, limits: checkedProfile.limits});
}

export async function loadInstalledTableEffect(profile: unknown, {root, ledgerRoot, principalId,
  moon, runtimeBundleCid, baseEnvironmentWire, installation, construction}: LoaderInput & Readonly<{
    ledgerRoot?: unknown; moon?: unknown; runtimeBundleCid?: unknown; baseEnvironmentWire?: unknown;
    construction?: Readonly<{
      preparePublishedEnvironment(wire: string): PublishedEnvironment;
      createTableEffect(options: EffectBinding): ReturnType<typeof createInstalledTableEffect>;
    }>;
  }>): ReturnType<typeof createInstalledTableEffect> {
  if (construction === undefined || typeof construction.preparePublishedEnvironment !== 'function' ||
      typeof construction.createTableEffect !== 'function') fail('InstalledTableEffectConstructionUnavailable');
  const checkedProfile = checkInstalledTableEffectProfile(profile);
  const implementation = selectedImplementation(installation);
  const admitted = construction.preparePublishedEnvironment(checkedProfile.environmentWire);
  const environment = admitted.body;
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
  return construction.createTableEffect({accountConfiguration: checkedProfile.accountConfigurationWire,
    connection: checkedProfile.connection,
    bindingCid: binding(checkedProfile, root, principalId, implementation),
    catalogCid: checkedProfile.catalog.catalogCid, targets: checkedProfile.targets,
    createBridge: () => bridgeOf(checkedProfile, implementation), ledgerRoot, limits: checkedProfile.limits});
}
