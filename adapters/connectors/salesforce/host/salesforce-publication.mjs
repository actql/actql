// Explicit publication of one installed Salesforce Site's declaration. A
// publish describes exactly the target Resources (each under its own metadata
// read decision) and saves the Catalog identity, the observation and its
// retained describe evidence as one generation, replaced atomically. A Host
// start restores the generation without credential or provider I/O; it is
// refused for another connection, principal, Site generation or connector.
// A restored generation is not current authority: every read is decided again.
import {createHash, randomBytes} from 'node:crypto';
import {open, readFile, rename, rm} from 'node:fs/promises';
import {dirname, isAbsolute, join} from 'node:path';
import {canonicalJson, contentCid} from
  '../../../host-node/local-account-config.mjs';

export const SALESFORCE_PUBLICATION_VERSION =
  'actql-salesforce-publication/0.1';
const keys = Object.freeze(['binding', 'catalog_cid', 'complete',
  'connector_id', 'evidence', 'observation_cid', 'resource_states',
  'resources', 'version']);
const outcomeNames = Object.freeze(new Map([[1, 'described'],
  [2, 'permission_denied'], [3, 'rate_limited'], [4, 'provider_unavailable'],
  [5, 'transport_interrupted'], [6, 'invalid_metadata'], [7, 'cancelled'],
  [8, 'not_found']]));
const maxGenerationBytes = 16_000_000;

const fail = (code, cause) => {
  throw Object.assign(new Error(code, {cause}), {code});
};
const text = value => typeof value === 'string' && value.length > 0;
// The generation is stored as the exact JSON text it was published as (the
// retained provider bytes are not renormalized) and identified by it.
const bytesCid = body => `sha256:${createHash('sha256').update(body, 'utf8')
  .digest('hex')}`;

function targetSet(connectorId, resources) {
  if (!text(connectorId) || !Array.isArray(resources) ||
      resources.length === 0 || !resources.every(text) ||
      new Set(resources).size !== resources.length) {
    fail('InvalidSalesforcePublication');
  }
  return [...resources];
}

// Replace `path` with `body` so a reader sees the previous or the new
// generation, never a mixture.
async function replaceFile(path, body) {
  const temporary = join(dirname(path),
    `.${randomBytes(8).toString('hex')}.publication.tmp`);
  const file = await open(temporary, 'wx', 0o600);
  try {
    await file.writeFile(body, 'utf8');
    await file.sync();
  } finally {
    await file.close();
  }
  try {
    await rename(temporary, path);
  } catch (error) {
    await rm(temporary, {force: true});
    throw error;
  }
  const directory = await open(dirname(path), 'r');
  try { await directory.sync(); }
  finally { await directory.close(); }
}

// Describe the target Resources and publish them as the Site's generation
// at `path`. A denied Resource refuses the whole publication before any
// provider I/O; an interrupted describe publishes nothing.
export async function publishSalesforceGeneration({site, path, connectorId,
  resources, signal}) {
  if (typeof path !== 'string' || !isAbsolute(path) ||
      typeof site?.declareCatalog !== 'function') {
    fail('InvalidSalesforcePublication');
  }
  const targets = targetSet(connectorId, resources);
  const declared = await site.declareCatalog({connectorId,
    resources: targets, signal});
  const {evidence} = declared;
  const generation = {
    binding: JSON.parse(evidence.observationJson).binding,
    catalog_cid: declared.catalog_cid,
    // Named observations are never complete: nothing outside the targets
    // was observed.
    complete: false,
    connector_id: connectorId,
    evidence,
    observation_cid: declared.observationCid,
    resource_states: evidence.names.map((name, index) => ({name,
      state: outcomeNames.get(evidence.outcomes[index]) ?? 'unobserved'})),
    resources: targets,
    version: SALESFORCE_PUBLICATION_VERSION,
  };
  const body = JSON.stringify(generation);
  if (Buffer.byteLength(body, 'utf8') > maxGenerationBytes) {
    fail('SalesforcePublicationTooLarge');
  }
  await replaceFile(path, body);
  return Object.freeze({generationCid: bytesCid(body), declared});
}

// Restore the published generation at `path` into `site` without provider
// I/O. The generation must name the Host profile's connector and target
// Resources and must be bound to the Site as installed now.
export async function loadSalesforceGeneration({site, path, connectorId,
  resources}) {
  if (typeof path !== 'string' || !isAbsolute(path) ||
      typeof site?.restoreDeclaration !== 'function') {
    fail('InvalidSalesforcePublication');
  }
  const targets = targetSet(connectorId, resources);
  let body;
  try { body = await readFile(path, 'utf8'); }
  catch (error) {
    if (error?.code === 'ENOENT') fail('SalesforcePublicationMissing', error);
    throw error;
  }
  if (Buffer.byteLength(body, 'utf8') > maxGenerationBytes) {
    fail('InvalidSalesforcePublication');
  }
  let generation;
  try { generation = JSON.parse(body); }
  catch (error) { fail('InvalidSalesforcePublication', error); }
  if (generation === null || typeof generation !== 'object' ||
      Array.isArray(generation) ||
      Object.keys(generation).join('\0') !== keys.join('\0') ||
      generation.version !== SALESFORCE_PUBLICATION_VERSION ||
      generation.complete !== false || JSON.stringify(generation) !== body ||
      !Array.isArray(generation.resource_states)) {
    fail('InvalidSalesforcePublication');
  }
  // The Host's target set is part of what was published: another connector
  // id or Resource set is another publication.
  if (generation.connector_id !== connectorId ||
      canonicalJson(generation.resources) !== canonicalJson(targets) ||
      canonicalJson(generation.evidence?.names ?? null) !==
        canonicalJson(targets)) {
    fail('SalesforcePublicationTargetMismatch');
  }
  const restored = site.restoreDeclaration({connectorId,
    resources: targets, evidence: generation.evidence,
    observationCid: generation.observation_cid,
    catalogCid: generation.catalog_cid});
  return Object.freeze({generationCid: bytesCid(body),
    resourceStates: Object.freeze(generation.resource_states.map(
      state => Object.freeze({...state}))), declared: restored});
}

const byCid = values => values.map(value => JSON.parse(value))
  .sort((a, b) => {
    const left = contentCid(a);
    const right = contentCid(b);
    return left < right ? -1 : left > right ? 1 : 0;
  });

// The Check Environment for Programs over a published declaration: the
// Host's base environment with the declaration's Catalog, source views,
// contracts and manifest entry. Built only from the published generation;
// Check never describes or regenerates anything.
export function salesforceCheckEnvironment(baseWire, declared) {
  const base = JSON.parse(baseWire);
  const {evidence_bundle_cid: _, ...body} = base;
  if (body.version !== 'actql-check-environment/0.1' ||
      body.connector_catalogs.length !== 0 ||
      body.connector_manifest !== undefined) {
    fail('InvalidSalesforceCheckEnvironmentBase');
  }
  const environment = {...body,
    source_views: byCid(declared.source_views),
    contract_registry: byCid(declared.contracts),
    connector_catalogs: [JSON.parse(declared.catalog)],
    connector_manifest: {version: 'actql-connectors/0.1',
      connectors: [JSON.parse(declared.manifest_entry)]}};
  const evidenceCid = contentCid(environment);
  return Object.freeze({
    wire: canonicalJson({...environment, evidence_bundle_cid: evidenceCid}),
    evidenceCid});
}
