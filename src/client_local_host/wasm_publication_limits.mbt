///|
/// Independent installed Wasm formatter guards, not a Compute quote, backing
/// grant or proof of checked demand. Both source-free and captured Source
/// publication project their retained requirements through this independent
/// formatter profile.
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
/// Project only the same requirements already consumed by this exact Compute.
/// The phase guards remain independent; no copied Program or missing original
/// can select the captured-Source profile instead.
pub fn ClientLocalRequirements::wasm_publication_limits(
  self : ClientLocalRequirements,
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.PublicationOutputExportLimits? {
  guard physical_equal(self.prepared, prepared) else { return None }
  client_wasm_checked_publication_limits(prepared, self.capacity_plan)
}

///|
/// Use the same Wasm limits projection on the already planned Model module.
pub fn installed_model_wasm_publication_limits(
  adopted : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
) -> @publication_host.PublicationOutputExportLimits? {
  guard !adopted.effect_operation_closing &&
    installed_managed_run_compilation_original(adopted, prepared)
    is Some(@publication_host.Tasks(compilation)) &&
    !compilation.infers.is_empty() else {
    return None
  }
  match (adopted.source_free_preparation, adopted.captured_preparation) {
    (Some(original), None) =>
      client_wasm_checked_publication_limits(prepared, original.capacity_plan)
    (None, Some(original)) if !original.whole_sources.is_empty() =>
      client_wasm_checked_publication_limits(
        prepared,
        original.capacity_plan,
        whole_inputs=true,
      )
    _ => None
  }
}

///|
fn client_wasm_checked_publication_limits(
  prepared : @publication_host.PreparedClientProgram,
  capacity_plan : ClientLocalCapacityPlan,
  whole_inputs? : Bool = false,
) -> @publication_host.PublicationOutputExportLimits? {
  let original = @publication_host.prepared_client_graph(prepared)
  guard capacity_plan.graph is Some(graph) &&
    (
      physical_equal(graph, original) ||
      (
        whole_inputs &&
        @strategy.source_inputs_dag_matches_original(graph, original)
      )
    ) &&
    capacity_plan.publication is Some(publication) else {
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
