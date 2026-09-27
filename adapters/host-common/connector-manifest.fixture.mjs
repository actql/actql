// Test fixture: the Connector Catalog and `actql-connectors/0.1` manifest
// entry a Check Environment needs for a Mapping targeting `targetRef`. The
// entry CID is the canonical CID of the entry body alone.
import {createHash} from 'node:crypto';
import {canonicalJson} from './publication-contract-control.fixture.mjs';

const cid = value => 'sha256:' + createHash('sha256')
  .update(canonicalJson(value)).digest('hex');
const sortKeys = value => Object.fromEntries(Object.entries(value)
  .sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));

export function fixtureConnectorEntry(targetRef, version = 'fixture') {
  const connectorId = /^connector:\/\/(.+)\/[^/]+$/u.exec(targetRef)[1];
  const entry = {connector: connectorId, connector_id: connectorId,
    connector_version: version};
  return {entry, entryCid: cid(entry)};
}

// Add the connection's empty Catalog and manifest entry to an environment
// document (idempotently) and return the entry CID for its Mappings.
export function withFixtureConnector(environment, targetRef) {
  const {entry, entryCid} = fixtureConnectorEntry(targetRef);
  const catalogs = environment.connector_catalogs ?? [];
  if (!catalogs.some(catalog => catalog.connector_id === entry.connector_id)) {
    const body = {schema: 'actql.connector_catalog/0.1',
      connector_id: entry.connector_id,
      connector_version: entry.connector_version,
      source_views: [], commands: [], contracts: []};
    catalogs.push({...body, catalog_cid: cid(body)});
    catalogs.sort((a, b) => cid(a) < cid(b) ? -1 : cid(a) > cid(b) ? 1 : 0);
  }
  const connectors = environment.connector_manifest?.connectors ?? [];
  if (!connectors.some(value => value.connector_id === entry.connector_id)) {
    connectors.push(entry);
    connectors.sort((a, b) => cid(a) < cid(b) ? -1 : cid(a) > cid(b) ? 1 : 0);
  }
  Object.assign(environment, {connector_catalogs: catalogs,
    connector_manifest: {connectors, version: 'actql-connectors/0.1'}});
  const sorted = sortKeys(environment);
  for (const key of Object.keys(environment)) delete environment[key];
  Object.assign(environment, sorted);
  return entryCid;
}
