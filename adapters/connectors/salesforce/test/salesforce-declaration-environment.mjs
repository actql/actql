// Test assembly of one Check Environment from a Salesforce Site's generated
// declaration. Canonical text and CIDs come from the repository's
// independent canonical JSON implementation, not from the generator.
import {machineCid} from '../../../../scripts/actql-spec-family.mjs';
import {canonicalText} from '../../../../scripts/check-canonical-json.mjs';

const byBody = texts => texts.map(text => JSON.parse(text))
  .sort((a, b) => machineCid(a) < machineCid(b) ? -1 :
    machineCid(a) > machineCid(b) ? 1 : 0);

// The fixed capacity policy of the existing Program fixtures.
const capacity = Object.freeze({
  max_aggregate_array_items: 10000, max_artifact_bytes: 10000,
  max_artifact_rows: 10000, max_effect_items: 10000,
  max_graph_input_edges: 10000, max_graph_input_nodes: 10000,
  max_graph_output_rows: 10000, max_graph_paths: 10000,
  max_infer_items: 10000, max_model_input_tokens_per_item: 10000,
  max_model_request_bytes_per_item: 10000,
  max_model_total_duration_ms: 10000, max_nested_value_bytes: 10000,
  max_nested_value_depth: 10000, max_relation_output_rows: 10000,
  max_temporal_matches_per_key: 10000, max_temporal_output_rows: 10000,
  version: 'actql-capacity-host-policy/0.1',
});

// `mappings` are the execution Mapping bodies the Program's Effects use.
export function declarationEnvironment(declared, mappings = []) {
  const body = {
    version: 'actql-check-environment/0.1',
    schema_snapshots: [], connector_capabilities: [],
    mapping_contracts: byBody(mappings),
    source_views: byBody(declared.source_views),
    command_contracts: [], model_task_contracts: [],
    contract_registry: byBody(declared.contracts),
    connector_catalogs: [JSON.parse(declared.catalog)],
    connector_manifest: {version: 'actql-connectors/0.1',
      connectors: [JSON.parse(declared.manifest_entry)]},
    host_policy_profile: {capacity},
  };
  const evidenceCid = machineCid(body);
  return {text: canonicalText({...body, evidence_bundle_cid: evidenceCid}),
    evidenceCid};
}

export function declaredReadProgram(connectorId, resource, fields) {
  return JSON.stringify({version: 'actql/0.1', id: 'declared-read',
    stages: [{id: 'acquire',
      inputs: {remote: {connector: connectorId, resource}},
      steps: [{select: fields, as: 'captured'}],
      results: {r: {from: 'captured', fields}}}],
    results: {out: {from: {stage: 'acquire', result: 'r'}}}});
}
