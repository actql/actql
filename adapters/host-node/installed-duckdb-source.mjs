// Host-owned physical source installation. Programs select a checked Catalog
// source; they cannot provide a file path, account grant, or transport policy.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {isAbsolute} from 'node:path';
import {createNodeAuthorizationGate} from './authorization.mjs';

const sourceLimits = Object.freeze({
  maxRows: 10000, maxCells: 100000, maxTransportBytes: 10000000,
  maxSqlBytes: 10000, maxParameters: 100, maxColumns: 100,
  memoryBytes: 128 * 1024 * 1024, threads: 1,
});

function cid(value) {
  return `sha256:${createHash('sha256').update(JSON.stringify(value))
    .digest('hex')}`;
}

export async function loadInstalledDuckDBSource(path, {root, principalId}) {
  if (path === undefined) return undefined;
  if (typeof path !== 'string' || !isAbsolute(path)) {
    throw new TypeError('InvalidInstalledSourceProfilePath');
  }
  const profile = JSON.parse(await readFile(path, 'utf8'));
  if (profile === null || typeof profile !== 'object' ||
      Array.isArray(profile) ||
      Object.keys(profile).sort().join('\0') !==
        ['accountConfigurationWire', 'checkEnvironmentWire', 'database',
          'schema', 'sourceRef', 'table', 'version'].join('\0') ||
      profile.version !== 'actql-installed-duckdb-source/0.1' ||
      typeof profile.database !== 'string' ||
      !isAbsolute(profile.database) ||
      !['schema', 'table', 'sourceRef', 'checkEnvironmentWire',
        'accountConfigurationWire'].every(key =>
        typeof profile[key] === 'string' && profile[key].length > 0)) {
    throw new TypeError('InvalidInstalledSourceProfile');
  }
  const context = Object.freeze({principal: principalId,
    contextCid: cid({version: 'actql-installed-source-context/0.1',
      root, principalId})});
  const authorization = await createNodeAuthorizationGate({
    configuration: profile.accountConfigurationWire, context,
  });
  return Object.freeze({
    // The source's own read authorization, for the Host's pre-acquisition
    // Checkpoint decision (the same configuration and context as the
    // adapter's check).
    readAuthorization: Object.freeze({
      accountConfiguration: profile.accountConfigurationWire, context}),
    environmentWire: profile.checkEnvironmentWire,
    database: profile.database, schema: profile.schema,
    table: profile.table, sourceRef: profile.sourceRef,
    sourceAccess: Object.freeze({authorization,
      connection: 'local-database', resource: profile.database,
      sourceRef: profile.sourceRef}),
    transportLimits: sourceLimits,
  });
}
