// Host-owned physical DuckDB profile validation and read authorization.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {types as nodeTypes} from 'node:util';
import {createNodeAuthorizationGate} from './authorization.mjs';
import {createAuthorizationGate} from '../host-common/authorization-gate.mjs';
import {checkDuckDBAcquisitionPlanning} from '../connectors/duckdb/node/acquisition-planning.mjs';

type CheckedProfile = Readonly<{
  version: typeof INSTALLED_DUCKDB_SOURCE_VERSION;
  database: string;
  schema: string;
  table: string;
  sourceRef: string;
  checkEnvironmentWire: string;
  accountConfigurationWire: string;
  acquisitionPlanning: ReturnType<typeof checkDuckDBAcquisitionPlanning>;
}>;
type ProfileData = Readonly<Record<string, unknown>>;
type InstallationIdentity = Readonly<{root: string; principalId: string}>;
type GateOptions = NonNullable<Parameters<typeof createAuthorizationGate>[0]>;
type InstallationOptions = InstallationIdentity & Readonly<{
  runtime?: GateOptions['runtime'];
  retainAuthorization?: (gate: ReturnType<typeof createAuthorizationGate>) => void;
}>;

const sourceLimits = Object.freeze({
  maxRows: 10000, maxCells: 100000, maxTransportBytes: 10000000,
  maxSqlBytes: 10000, maxParameters: 100, maxColumns: 100,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
});

function cid(value: InstallationIdentity & {version: string}) {
  return `sha256:${createHash('sha256').update(JSON.stringify(value))
    .digest('hex')}`;
}

export const INSTALLED_DUCKDB_SOURCE_VERSION =
  'actql-installed-duckdb-source/0.1';

export async function loadInstalledDuckDBSource(path: unknown, {root, principalId}: InstallationIdentity) {
  if (path === undefined) return undefined;
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  return installDuckDBSourceProfile(JSON.parse(await readFile(path, 'utf8')),
    {root, principalId});
}

// Original checked DATA snapshots are reusable only by identity. This neither
// admits an Environment nor issues an Account decision or Source construction.
const checkedProfiles = new WeakSet<object>();
export function checkInstalledDuckDBSourceProfile(profile: unknown): CheckedProfile {
  if (checkedProfiles.has(profile as object)) return profile as CheckedProfile;
  if (profile === null || typeof profile !== 'object' || nodeTypes.isProxy(profile) ||
      Array.isArray(profile) ||
      Reflect.ownKeys(Object.getOwnPropertyDescriptors(profile)).some(name =>
        typeof name !== 'string' || !Object.hasOwn(Object.getOwnPropertyDescriptor(profile, name)!, 'value')) ||
      Object.keys(profile).sort().join('\0') !==
        ['accountConfigurationWire', 'acquisitionPlanning', 'checkEnvironmentWire', 'database',
          'schema', 'sourceRef', 'table', 'version'].join('\0') ||
      (profile as ProfileData).version !== 'actql-installed-duckdb-source/0.1' ||
      typeof (profile as ProfileData).database !== 'string' ||
      !isAbsolute((profile as {database: string}).database) ||
      !['schema', 'table', 'sourceRef', 'checkEnvironmentWire',
        'accountConfigurationWire'].every(key =>
        typeof (profile as ProfileData)[key] === 'string' &&
        (profile as Readonly<Record<string, string>>)[key].length > 0)) {
    throw new TypeError('InvalidInstalledSourceProfile');
  }
  const acquisitionPlanning = checkDuckDBAcquisitionPlanning((profile as ProfileData).acquisitionPlanning);
  const checked = Object.freeze({...profile, acquisitionPlanning});
  checkedProfiles.add(checked);
  return checked as CheckedProfile;
}

// Install one original checked profile on the selected Host runtime. The
// bound Source owner retains this gate before another fallible constructor.
export async function installDuckDBSourceProfile(profile: unknown,
  {root, principalId, runtime, retainAuthorization}: InstallationOptions) {
  const checkedProfile = checkInstalledDuckDBSourceProfile(profile);
  const acquisitionPlanning = checkedProfile.acquisitionPlanning;
  const context = Object.freeze({principal: principalId,
    contextCid: cid({version: 'actql-installed-source-context/0.1',
      root, principalId})});
  const options = {configuration: checkedProfile.accountConfigurationWire, context};
  const authorization = runtime === undefined
    ? await createNodeAuthorizationGate(options)
    : createAuthorizationGate({...options, runtime});
  // The bound caller owns this original before any returned-profile wrapper
  // or subsequent native-library constructor can fail.
  if (retainAuthorization !== undefined) retainAuthorization(authorization);
  return Object.freeze({
    // The source's own read authorization, for the Host's pre-acquisition
    // Checkpoint decision (the same configuration and context as the
    // adapter's check).
    readAuthorization: Object.freeze({
      accountConfiguration: checkedProfile.accountConfigurationWire, context}),
    environmentWire: checkedProfile.checkEnvironmentWire,
    database: checkedProfile.database, schema: checkedProfile.schema,
    table: checkedProfile.table, sourceRef: checkedProfile.sourceRef,
    sourceAccess: Object.freeze({authorization,
      connection: 'local-database', resource: checkedProfile.database,
      sourceRef: checkedProfile.sourceRef}),
    transportLimits: sourceLimits, acquisitionPlanning,
  });
}
