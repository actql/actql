// The standard Host selects this installation from the connector manifest.
// Metadata is an explicit installed snapshot, not permission or a fresh read.
// Original SQL/row/credential/capture meanings stay with their existing Owners.
import {createHash} from 'node:crypto';
import {isAbsolute} from 'node:path';
import {readFile} from 'node:fs/promises';
import {canonicalJson} from '../../../../packages/sdk/host-port.mjs';
import {checked} from '../../../host-common/runtime-result.mjs';
import {readSourceProfileJson, captureConfigurationReaders} from '../../../host-node/source-profile-json.mjs';
import {readSnowflakeSqlApi, SNOWFLAKE_SQL_READ_OPERATION} from '../site/snowflake-sql-read.mjs';
import {checkSnowflakeKeyPairProfile, openSnowflakeKeyPairMaterial} from '../site/snowflake-key-pair.mjs';

type ReadOptions = Parameters<typeof readSnowflakeSqlApi>[0];
type ReadLimits = ReadOptions['limits'];
type InstalledLimits = ReadLimits & Readonly<{
  maxDescriptionBytes: number; maxDeclarationBytes: number; maxDeclarationNodes: number;
}>;
type TargetIdentity = Readonly<{
  connectorId: string; resource: string; database: string; schema: string; table: string;
}>;
type SourceProfile = TargetIdentity & Readonly<{
  version: typeof INSTALLED_SNOWFLAKE_SOURCE_VERSION; metadataPath: string; siteProfilePath: string;
  accountConfigurationWire: string; limits: InstalledLimits;
}>;
type SiteBase = Readonly<{
  version: typeof INSTALLED_SNOWFLAKE_SITE_VERSION; apiOrigin: string; warehouse: string; role: string;
  authenticationType: NonNullable<ReadOptions['authenticationType']>; credentialAuthorityId: string;
  credentialKeyId: string; credentialPrivateKeyPath: string; environment: string; journalRoot: string;
  namespaceId: string; siteGeneration: number; siteKey: string; tokenEnvironment?: string;
}>;
type KeyPair = ReturnType<typeof checkSnowflakeKeyPairProfile>;
type SiteProfile = SiteBase & Readonly<{caPath?: string; keyPair?: KeyPair}>;
type SiteInput = SiteBase & Readonly<{caPath?: string; keyPair?: unknown}>;
type Metadata = TargetIdentity & Readonly<{version: string; apiOrigin: string; bodies: readonly unknown[]}>;
type Reader = Readonly<{readJson(path: string): unknown;
  readOriginalBytes(path: string): Uint8Array | PromiseLike<Uint8Array>}>;
type Runtime = ReadOptions['moon'] & Readonly<{
  clientProgramSnowflakeDescriptionLimits(columns: number, nameUnits: number, bytes: number, nodes: number, depth: number): unknown;
  clientProgramSnowflakeDeclarationLimits(bytes: number, nodes: number, depth: number, views: number, fields: number): unknown;
  clientProgramSnowflakeReadDeclarationConstructionCapacity(bodyBytes: number[], encodedBytes: number,
    targetUnits: number, resourceUnits: number, connectorUnits: number, revisionUnits: number,
    responseLimits: unknown, descriptionLimits: unknown, declarationLimits: unknown): unknown;
  clientProgramSnowflakeDescribeTable(database: string, schema: string, table: string,
    decoded: Uint8Array[], responseLimits: unknown, descriptionLimits: unknown): unknown;
  clientProgramSnowflakeGenerateReadDeclaration(description: unknown, resource: string, connector: string,
    revision: string, descriptionLimits: unknown, declarationLimits: unknown): unknown;
  clientProgramSnowflakePrepareRead(description: unknown, declaration: unknown, requirement: unknown,
    queryContract: unknown, evidenceContract: unknown, descriptionLimits: unknown, declarationLimits: unknown): unknown;
}>;
type Declaration = Readonly<{catalog_cid: string; views: readonly Readonly<{fields: readonly string[]}>[]}>;
type SiteOptions = Readonly<{
  profile: SiteProfile & Readonly<{resourceOrigin: string}>; accountConfiguration: string; connection: string;
  ca?: Uint8Array; admitsApprovalTarget(binding: unknown, resource: string): boolean;
  prepareSecretMaterial?: () => ReturnType<typeof openSnowflakeKeyPairMaterial>;
  responseHeaders: readonly string[]; resolveSecret: ReadOptions['credential']['resolveSecret'];
}>;
type RowAcquisition = Readonly<{declaration: unknown; requirement: unknown; queryContract: unknown; evidenceContract: unknown}>;
type ReadPages = Omit<ReadOptions, 'moon' | 'prepared' | 'limits' | 'warehouse' | 'role' |
  'authenticationType' | 'credential' | 'callResource'>;
type SourceOptions = Readonly<{
  readOperation: string; physicalTarget(resource: string, fields: readonly string[]): Readonly<{fields: readonly string[]}>;
  bindingCid: string;
  limits: Readonly<{maxPages: number; maxPageBytes: number; maxPageRows: number; maxCaptureRows: number}>;
  prepareAcquisition(options: RowAcquisition): object;
  readPages(options: ReadPages): Promise<void>;
}>;
type Construction = Readonly<{
  configurationReader: Reader;
  prepareNativeDeclaration(input: Readonly<{
    capacity(): unknown; project(): Readonly<{description: unknown; declaration: unknown}>;
  }>): Readonly<{description: unknown; declaration: unknown; declared: Declaration}>;
  openRowSite(options: SiteOptions): PromiseLike<Readonly<{
    site: Readonly<{credential: ReadOptions['credential']; callResource: NonNullable<ReadOptions['callResource']>}>;
    authorization: Readonly<{context: Readonly<{contextCid: string}>}>;
  }>>;
  createRowSource(options: SourceOptions): unknown;
}>;
type Installation = Readonly<{
  root?: string; principalId?: string; moon: Runtime; baseEnvironmentWire?: string; runtimeBundleCid: string;
  resolveSecret?: ReadOptions['credential']['resolveSecret']; installation?: Readonly<{responseHeaders?: readonly string[]}>;
  construction?: Construction;
}>;

export const INSTALLED_SNOWFLAKE_SOURCE_VERSION = 'actql-installed-snowflake-source/0.1';
export const INSTALLED_SNOWFLAKE_SITE_VERSION = 'actql-installed-snowflake-site/0.1';
const registration = 'snowflake', revision = 'snowflake/0.1';
const profileKeys = ['version', 'connectorId', 'resource', 'database', 'schema', 'table',
  'metadataPath', 'siteProfilePath', 'accountConfigurationWire', 'limits'];
const siteKeys = ['version', 'apiOrigin', 'warehouse', 'role', 'authenticationType',
  'credentialAuthorityId', 'credentialKeyId', 'credentialPrivateKeyPath', 'environment',
  'journalRoot', 'namespaceId', 'siteGeneration', 'siteKey', 'tokenEnvironment'];
const limitKeys = ['maxBytes', 'maxNodes', 'maxDepth', 'maxColumns', 'maxNameUnits',
  'maxHandleUnits', 'maxPartitions', 'maxRows', 'maxTotalRows', 'maxRequests',
  'maxRequestBytes', 'maxContractPairs', 'timeoutSeconds', 'maxSecretBytes', 'pollDelayMs',
  'maxDescriptionBytes', 'maxDeclarationBytes', 'maxDeclarationNodes'] as const;
const fail: (code: string, cause?: unknown) => never = (code, cause) => {throw Object.assign(new Error(code, {cause}), {code});};
const text = (value: unknown): value is string => typeof value === 'string' && value.length > 0 && value.isWellFormed() &&
  !/[\u0000-\u001f\u007f]/u.test(value);
const absolute = (value: unknown): value is string => text(value) && isAbsolute(value);
const closed = (value: unknown, keys: readonly string[]) => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
const canonical = (value: unknown) => canonicalJson(value, {dataKeys: true});
const cid = (value: unknown) => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;

export function checkInstalledSnowflakeSourceProfile(profile: unknown) {
  if (!closed(profile, profileKeys) || (profile as SourceProfile).version !== INSTALLED_SNOWFLAKE_SOURCE_VERSION ||
      !(['connectorId', 'resource', 'database', 'schema', 'table'] as const).every(key =>
        text((profile as SourceProfile)[key]) && Buffer.byteLength((profile as SourceProfile)[key]) <= 4096) ||
      !absolute((profile as SourceProfile).metadataPath) || !absolute((profile as SourceProfile).siteProfilePath) ||
      !text((profile as SourceProfile).accountConfigurationWire) || !closed((profile as SourceProfile).limits, limitKeys)) {
    fail('InvalidInstalledSnowflakeSourceProfile');
  }
  const limits = {...(profile as SourceProfile).limits};
  if (!limitKeys.every(key => Number.isSafeInteger(limits[key]) && limits[key] <= 2147483647 &&
      limits[key] >= (key === 'pollDelayMs' ? 0 : 1)) ||
      limits.maxRows > limits.maxTotalRows || limits.maxRequests > 10000) {
    fail('InvalidInstalledSnowflakeSourceProfile');
  }
  return Object.freeze({...profile as SourceProfile, limits: Object.freeze(limits)});
}

function checkSite(site: unknown) {
  const {caPath, keyPair, ...rest} = (site ?? {}) as SiteInput;
  let origin;
  try {origin = new URL(rest.apiOrigin);} catch { /* Closed rejection below. */ }
  const materialKeys = Object.hasOwn(site ?? {}, 'keyPair')
    ? siteKeys.filter(key => key !== 'tokenEnvironment') : siteKeys;
  if (!closed(rest, materialKeys) || rest.version !== INSTALLED_SNOWFLAKE_SITE_VERSION ||
      origin?.protocol !== 'https:' || origin.origin !== rest.apiOrigin ||
      !(['warehouse', 'role', 'credentialAuthorityId', 'credentialKeyId', 'environment',
        'namespaceId', 'siteKey'] as const).every(key => text(rest[key]) && Buffer.byteLength(rest[key]) <= 4096) ||
      !['OAUTH', 'KEYPAIR_JWT'].includes(rest.authenticationType) ||
      !absolute(rest.credentialPrivateKeyPath) || !absolute(rest.journalRoot) ||
      (caPath !== undefined && !absolute(caPath)) ||
      !Number.isSafeInteger(rest.siteGeneration) || rest.siteGeneration < 0 ||
      (Object.hasOwn(site ?? {}, 'keyPair') ? rest.authenticationType !== 'KEYPAIR_JWT'
        : !/^[A-Z_][A-Z0-9_]{0,63}$/u.test(rest.tokenEnvironment!))) fail('InvalidInstalledSnowflakeSite');
  const selected = Object.hasOwn(site ?? {}, 'keyPair') ? checkSnowflakeKeyPairProfile(keyPair) : undefined;
  return Object.freeze({...rest, ...(caPath === undefined ? {} : {caPath}),
    ...(selected === undefined ? {} : {keyPair: selected})});
}

async function readInputs(profile: unknown, readJson: Reader['readJson'] = readSourceProfileJson) {
  const installed = checkInstalledSnowflakeSourceProfile(profile);
  const site = checkSite(await readJson(installed.siteProfilePath));
  const metadata = await readJson(installed.metadataPath) as Metadata;
  const keys = ['version', 'connectorId', 'resource', 'database', 'schema', 'table', 'apiOrigin', 'bodies'];
  if (!closed(metadata, keys) || metadata.version !== 'actql-snowflake-read-metadata/0.1' ||
      !(['connectorId', 'resource', 'database', 'schema', 'table'] as const).every(key => metadata[key] === installed[key]) ||
      metadata.apiOrigin !== site.apiOrigin || !Array.isArray(metadata.bodies) ||
      metadata.bodies.length < 1 || metadata.bodies.length > installed.limits.maxPartitions) {
    fail('InvalidInstalledSnowflakeMetadata');
  }
  const bodies = metadata.bodies.map(body => {
    // Store original bounded SQL API bytes, never a JS-reconstructed schema.
    if (typeof body !== 'string' || body.length > Math.ceil(installed.limits.maxBytes / 3) * 4) {
      fail('InvalidInstalledSnowflakeMetadata');
    }
    if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u.test(body)) {
      fail('InvalidInstalledSnowflakeMetadata');
    }
    const padding = body.endsWith('==') ? 2 : body.endsWith('=') ? 1 : 0;
    const bytes = body.length / 4 * 3 - padding;
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    if (bytes > installed.limits.maxBytes || padding !== 0 &&
        (alphabet.indexOf(body[body.length - padding - 1]) & (padding === 2 ? 15 : 3)) !== 0) {
      fail('InvalidInstalledSnowflakeMetadata');
    }
    return Object.freeze({encoded: body, bytes});
  });
  return {installed, site, metadata, bodies};
}

// All exact target strings are semantic data, including Unicode normalization.
// Their digest supplements the standard Host's configuration canonicalizer.
export async function installedSnowflakeSourceIdentityParts(profile: Readonly<{accountConfigurationWire: string}>, providerProfile: unknown,
  read: unknown, _entry: unknown, {configurationReader}: Readonly<{configurationReader?: unknown}> = {}) {
  const readers = captureConfigurationReaders(configurationReader, read, () => fail('SnowflakeSourceConstructionUnavailable'));
  const {installed, site, metadata} = await readInputs(providerProfile, readers.readJson as Reader['readJson']);
  const ca = site.caPath === undefined ? undefined : await ((readers as Pick<Partial<Reader>, 'readOriginalBytes'>).readOriginalBytes ?? readFile)(site.caPath);
  return [{...profile, accountConfigurationWire: JSON.parse(profile.accountConfigurationWire)},
    site, {exactTargetCid: cid({connectorId: installed.connectorId, resource: installed.resource,
      database: installed.database, schema: installed.schema, table: installed.table,
      warehouse: site.warehouse, role: site.role}), metadataCid: cid(metadata),
    ...(ca === undefined ? {} : {caSha256: createHash('sha256').update(ca).digest('hex')})}];
}

export async function loadInstalledSnowflakeSource(profile: unknown, {root, principalId, moon,
  baseEnvironmentWire, runtimeBundleCid, resolveSecret, installation, construction}: Installation) {
  if (construction === undefined || typeof construction.prepareNativeDeclaration !== 'function' ||
      typeof construction.openRowSite !== 'function' || typeof construction.createRowSource !== 'function' ||
      typeof construction.configurationReader?.readOriginalBytes !== 'function') fail('SnowflakeSourceConstructionUnavailable');
  const readers = construction.configurationReader;
  const {installed, site: siteProfile, metadata, bodies} = await readInputs(profile, readers.readJson);
  const {limits} = installed;
  const responseLimits = moon.clientProgramSnowflakeResponseLimits(limits.maxBytes, limits.maxNodes,
    limits.maxDepth, limits.maxColumns, limits.maxNameUnits, limits.maxHandleUnits,
    limits.maxPartitions, limits.maxRows, BigInt(limits.maxTotalRows));
  const descriptionLimits = moon.clientProgramSnowflakeDescriptionLimits(limits.maxColumns,
    limits.maxNameUnits, limits.maxDescriptionBytes, limits.maxNodes, limits.maxDepth);
  const declarationLimits = moon.clientProgramSnowflakeDeclarationLimits(limits.maxDeclarationBytes,
    limits.maxDeclarationNodes, limits.maxDepth, 1, limits.maxColumns);
  const {description, declaration, declared} = construction.prepareNativeDeclaration(Object.freeze({
    capacity: () => moon.clientProgramSnowflakeReadDeclarationConstructionCapacity(
      bodies.map(body => body.bytes), bodies.reduce((sum, body) => sum + body.encoded.length, 0),
      installed.database.length + installed.schema.length + installed.table.length,
      installed.resource.length, installed.connectorId.length, revision.length,
      responseLimits, descriptionLimits, declarationLimits),
    project() {
      const decoded = bodies.map(body => Buffer.from(body.encoded, 'base64'));
      const description = checked(moon.clientProgramSnowflakeDescribeTable(installed.database,
        installed.schema, installed.table, decoded, responseLimits, descriptionLimits));
      const declaration = checked(moon.clientProgramSnowflakeGenerateReadDeclaration(description,
        installed.resource, installed.connectorId, revision, descriptionLimits, declarationLimits));
      return Object.freeze({description, declaration});
    },
  }));
  const connection = `snowflake:${installed.connectorId}`;
  const target = (resource: string, fields: readonly string[]) => Object.freeze({version: 'actql-installed-snowflake-target/0.1',
    apiOrigin: siteProfile.apiOrigin, database: installed.database, schema: installed.schema,
    table: installed.table, resource, warehouse: siteProfile.warehouse, role: siteProfile.role,
    metadataCid: cid(metadata), catalogCid: declared.catalog_cid, fields: Object.freeze([...fields])});
  const allFields = declared.views[0].fields;
  const admitsApprovalTarget = (binding: unknown, resource: string) =>
    resource === installed.resource && binding !== null && typeof binding === 'object' &&
    Array.isArray((binding as {fields?: unknown}).fields) &&
    new Set((binding as {fields: string[]}).fields).size === (binding as {fields: string[]}).fields.length &&
    (binding as {fields: string[]}).fields.every(field => allFields.includes(field)) &&
    canonical(binding) === canonical(target(resource, (binding as {fields: string[]}).fields));
  const ca = siteProfile.caPath === undefined ? undefined : await readers.readOriginalBytes(siteProfile.caPath);
  const {authorization, site} = await construction.openRowSite({
    profile: Object.freeze({...siteProfile, resourceOrigin: siteProfile.apiOrigin}),
    accountConfiguration: installed.accountConfigurationWire, connection, ca, admitsApprovalTarget,
    ...(siteProfile.keyPair === undefined ? {} : {prepareSecretMaterial: () =>
      openSnowflakeKeyPairMaterial(siteProfile.keyPair, {maxSecretBytes: limits.maxSecretBytes, resolveMaterial: resolveSecret})}),
    responseHeaders: installation?.responseHeaders ?? ['content-encoding'],
    resolveSecret: resolveSecret ?? (async () => {
      const secret = process.env[siteProfile.tokenEnvironment!];
      if (!text(secret)) fail('RemoteCredentialSecretUnavailable');
      return secret;
    })});
  {
    const preparedReads = new WeakMap<object, unknown>();
    return await construction.createRowSource({
      readOperation: SNOWFLAKE_SQL_READ_OPERATION, physicalTarget: target,
      bindingCid: cid({version: 'actql-installed-snowflake-binding/0.1',
        contextCid: authorization.context.contextCid, runtimeBundleCid,
        metadataCid: cid(metadata), site: siteProfile}),
      limits: {maxPages: limits.maxRequests, maxPageBytes: limits.maxBytes,
        maxPageRows: limits.maxRows, maxCaptureRows: limits.maxTotalRows},
      prepareAcquisition: options => {
        const prepared = checked(moon.clientProgramSnowflakePrepareRead(description,
          options.declaration, options.requirement, options.queryContract, options.evidenceContract,
          descriptionLimits, declarationLimits));
        const acquisition = moon.clientProgramSnowflakeReadAcquisition(prepared);
        preparedReads.set(acquisition, prepared);
        return acquisition;
      },
      readPages: async options => {
        const prepared = preparedReads.get(options.rowRun?.acquisition);
        if (prepared === undefined) fail('ForeignSnowflakeReadPreparation');
        // The standard Host passes the original nominal acquisition/run/frame.
        // No replacement reservation, Run or transport permission is issued.
        await readSnowflakeSqlApi({...options, moon, prepared, limits,
          warehouse: siteProfile.warehouse, role: siteProfile.role,
          authenticationType: siteProfile.authenticationType,
          credential: site.credential, callResource: site.callResource});
      }});
  }
}
