// Independent test authoring, not a product catalog builder. Only declared
// source schema changes; every affected preimage is resealed with Node SHA-256.
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

export const canonical = value => Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
export const hash = value => `sha256:${createHash('sha256').update(canonical(value)).digest('hex')}`;
function seal(value, key) {
  const body = { ...value };
  delete body[key];
  value[key] = hash(body);
}
function replace(value, oldCid, newCid) {
  if (Array.isArray(value)) return value.map(item => replace(item, oldCid, newCid));
  if (value !== null && typeof value === 'object') return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, replace(item, oldCid, newCid)]),
  );
  return value === oldCid ? newCid : value;
}

export function typedCatalog(seed, fieldContract) {
  let environment = structuredClone(seed);
  const expected = environment.evidence_bundle_cid;
  seal(environment, 'evidence_bundle_cid');
  assert.equal(environment.evidence_bundle_cid, expected);
  const contract = environment.contract_registry.find(item => item.kind === 'carrier_schema');
  const previousContract = contract.cid;
  contract.body.fields.amount = fieldContract;
  seal(contract, 'cid');
  for (const catalog of environment.connector_catalogs) {
    catalog.contracts = catalog.contracts.map(item => item.cid === previousContract ? structuredClone(contract) : item);
  }
  environment = replace(environment, previousContract, contract.cid);
  const view = environment.source_views[0];
  const previousView = view.contract_cid;
  seal(view, 'contract_cid');
  environment = replace(environment, previousView, view.contract_cid);
  for (const catalog of environment.connector_catalogs) {
    catalog.contracts.sort((a, b) => a.cid < b.cid ? -1 : a.cid > b.cid ? 1 : 0);
    seal(catalog, 'catalog_cid');
  }
  environment.contract_registry.sort((a, b) => hash(a) < hash(b) ? -1 : hash(a) > hash(b) ? 1 : 0);
  seal(environment, 'evidence_bundle_cid');
  return environment;
}
