// Benchmark setup only, outside measurement. No runtime rows or execution
// evidence are constructed here. The public checker must admit this envelope.
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {canonicalText} from '../../scripts/check-canonical-json.mjs';

const capacityContract = JSON.parse(readFileSync(new URL('../../spec/contracts/actql-capacity-host-policy.json', import.meta.url), 'utf8'));
const hash = value => `sha256:${createHash('sha256').update(canonicalText(value)).digest('hex')}`;
const signed = (value, key) => ({...value, [key]: hash(value)});
const ordered = values => [...values].sort((a, b) => hash(a) < hash(b) ? -1 : hash(a) > hash(b) ? 1 : 0);

export function benchmarkEnvironment(fixture) {
  const fields = Object.fromEntries(fixture.fields.map(name => [name,
    {type: name === 'payload' && fixture.layout === 'text-1024' ? 'string' : 'number', nullable: false}]));
  const contract = (id, kind, body) => signed({schema: 'actql.contract/0.1',
    id, kind, version: 'benchmark', body}, 'cid');
  const request = contract('request', 'request_schema', {type: 'object', nullable: false, additional_properties: false, fields: {}});
  const rows = contract('rows', 'carrier_schema', {type: 'object', nullable: false, additional_properties: false, fields});
  const facts = contract('facts', 'carrier_facts', {});
  const pushdown = contract('pushdown', 'pushdown', {});
  const policy = contract('policy', 'data_policy', {version: 'actql-source-data-policy/0.1',
    classification: 'unknown', source_ref: 'connector://crm/main/r#v'});
  const ref = value => ({id: value.id, version: value.version, cid: value.cid});
  const view = signed({schema: 'actql.source_view/0.1', connector_id: 'crm/main',
    connector_version: 'benchmark', resource_kind: 'record', view_id: 'v', view_version: 'benchmark',
    acquisition: {authority: 'read_metadata', default_mode: 'snapshot', kind: 'scan',
      modes: [{bounded: true, mode: 'snapshot'}], request_schema: ref(request)},
    output: {carrier: 'relation', schema: ref(rows), facts: ref(facts), data_policy: ref(policy)},
    pushdown: {contract: ref(pushdown), operations: []}, request_processing: {mutates_business_state: false}}, 'contract_cid');
  const contracts = [request, rows, facts, pushdown, policy].sort((a, b) => a.cid < b.cid ? -1 : 1);
  const catalog = signed({schema: 'actql.connector_catalog/0.1', connector_id: 'crm/main',
    connector_version: 'benchmark', commands: [], contracts, source_views: [view]}, 'catalog_cid');
  const capacity = Object.fromEntries(capacityContract.schema.required.map(key => [key,
    key === 'version' ? 'actql-capacity-host-policy/0.1' : key === 'max_relation_output_rows'
      ? Math.max(fixture.limits.sourceRows, fixture.limits.intermediateRows) : 10000]));
  const environment = signed({version: 'actql-check-environment/0.1',
    schema_snapshots: [], connector_capabilities: [], mapping_contracts: [],
    source_views: [view], command_contracts: [], model_task_contracts: [],
    contract_registry: ordered(contracts), connector_catalogs: [catalog],
    host_policy_profile: {capacity}}, 'evidence_bundle_cid');
  return Object.freeze({text: canonicalText(environment), cid: environment.evidence_bundle_cid});
}
