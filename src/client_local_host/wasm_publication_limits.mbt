///|
/// Independent installed Wasm formatter guards, not a Compute quote, backing
/// grant or proof of checked demand. Captured Source publication retains this
/// distinct profile until that Host supplies its own retained plan original.
pub fn client_wasm_result_export_profile() -> @publication_host.PublicationOutputExportLimits {
  {
    max_result_fields: 100,
    max_result_mapping_work: 100000,
    max_result_order_work: 1000000,
    max_result_workspace_entries: 100000,
    max_rows: 100000,
    values: {
      max_nodes: 10000,
      max_text_bytes: 65536,
      max_depth: 64,
      max_work: 100000,
    },
    payload_wire: {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
    },
    logical_wire: {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 64,
    },
    schema: {
      max_fields: 100,
      max_bytes: 65536,
      max_nodes: 10000,
      max_depth: 64,
    },
    max_batch_bytes: 65536,
  }
}

///|
/// Project only the same requirements already consumed by source-free Compute.
/// The phase guards remain independent; no copied Program or missing original
/// can select the captured-Source profile instead.
pub fn ClientLocalSourceFreeRequirements::wasm_publication_limits(
  self : ClientLocalSourceFreeRequirements,
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.PublicationOutputExportLimits? {
  guard physical_equal(self.prepared, prepared) &&
    self.capacity_plan.graph is Some(graph) &&
    physical_equal(graph, @publication_host.prepared_client_graph(prepared)) &&
    self.capacity_plan.publication is Some(publication) else {
    return None
  }
  let profile = client_wasm_result_export_profile()
  let envelope = publication.envelope
  let fields = envelope
    .map(value => value.fields)
    .unwrap_or(profile.max_result_fields)
  let mapping = envelope
    .map(value => value.mapping_work)
    .unwrap_or(profile.max_result_mapping_work)
  let workspace = envelope
    .map(value => value.publication_workspace_entries)
    .unwrap_or(profile.max_result_workspace_entries)
  if fields > profile.max_result_fields ||
    mapping > profile.max_result_mapping_work ||
    workspace > profile.max_result_workspace_entries ||
    publication.rows > profile.max_rows {
    return None
  }
  Some({
    ..profile,
    max_result_fields: fields,
    max_result_mapping_work: mapping,
    max_result_order_work: if envelope is Some(value) && value.order_terms == 0 {
      publication.rows
    } else {
      profile.max_result_order_work
    },
    max_result_workspace_entries: workspace,
    max_rows: publication.rows,
    payload_wire: {
      ..profile.payload_wire,
      max_bytes: Int::min(
        profile.payload_wire.max_bytes,
        publication.wire_bytes.unwrap_or(profile.payload_wire.max_bytes),
      ),
    },
    logical_wire: {
      ..profile.logical_wire,
      max_bytes: Int::min(
        profile.logical_wire.max_bytes,
        publication.wire_bytes.unwrap_or(profile.logical_wire.max_bytes),
      ),
    },
    schema: {
      ..profile.schema,
      max_bytes: Int::min(profile.schema.max_bytes, publication.schema_bytes),
    },
  })
}
