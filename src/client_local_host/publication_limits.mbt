///|
/// Compatibility calculator for callers without an original LocalCapacityPlan.
/// This retains its historical generic decoder/export profile; it is not the
/// plan-derived ordinary Node publication path and does not prove equivalence
/// to a separately configured dispatch envelope. The Store ceiling only narrows
/// the selected legacy wire profile. New ordinary callers use the checked
/// Result and installed metadata projections below instead.
pub fn client_local_values_publication_limits(
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> (
  @execution.RetainedRowDecodeLimits,
  @publication_host.PublicationOutputExportLimits,
)? {
  if max_payload_bytes < 1 {
    return None
  }
  let max_rows = @publication_host.prepared_client_values_max_rows(prepared)
  let (values, execution, _) = client_local_execution_limits(max_rows~)
  let exported = client_local_export_limits(max_rows, values)
  let wire = @execution.RowWireLimits::{
    ..exported.wire,
    max_bytes: Int::min(max_payload_bytes, exported.wire.max_bytes),
  }
  Some(
    (
      {
        max_bytes: 65536,
        max_nodes: 10000,
        max_depth: 64,
        max_text_bytes: 65536,
      },
      {
        max_result_fields: exported.wire.max_columns,
        max_result_mapping_work: execution.rows.metadata_entries,
        max_result_order_work: execution.rows.metadata_entries,
        max_result_workspace_entries: execution.rows.retained_entries,
        max_rows,
        values,
        payload_wire: wire,
        logical_wire: wire,
        schema: {
          max_fields: exported.wire.max_columns,
          max_bytes: Int::min(65536, max_payload_bytes),
          max_nodes: 8192,
          max_depth: 64,
        },
        max_batch_bytes: Int::min(exported.max_batch_bytes, max_payload_bytes),
      },
    ),
  )
}

///|
/// The legacy Node publication schema byte ceiling, also consumed by the
/// independent retained publication quote; this does not use payload wire.
fn client_node_publication_schema_bytes() -> Int {
  100000
}

///|
/// Node's existing ordinary publication phase profile. This is separate from
/// compute/Content limits. Only checked Result metadata changes; other legacy
/// ceilings retain their original meaning and value.
pub fn client_node_values_publication_limits(
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
) -> @publication_host.PublicationOutputExportLimits? {
  // Standalone compatibility callers have no original capacity plan. Preserve
  // their historical row profile; do not infer or reconstruct a second proof.
  client_node_values_publication_limits_with_plan(
    prepared,
    max_payload_bytes,
    None,
  )
}

///|
priv struct ClientLocalResultPublicationPlan {
  rows : Int
  envelope : ClientLocalResultEnvelope?
  wire_bytes : Int?
  schema_bytes : Int
}

///|
fn client_local_result_publication_plan(
  graph : @strategy.CheckedDAG,
  rows : Int,
  envelope : ClientLocalResultEnvelope?,
) -> ClientLocalResultPublicationPlan {
  let schema_limits : @execution.RelationSchemaIdentityLimits = {
    max_fields: envelope.map(value => value.fields).unwrap_or(100),
    max_bytes: client_node_publication_schema_bytes(),
    max_nodes: 10000,
    max_depth: 64,
  }
  {
    rows,
    envelope,
    wire_bytes: client_local_result_scalar_wire_bytes(graph, rows),
    schema_bytes: client_local_result_schema_bytes(graph, schema_limits).unwrap_or(
      schema_limits.max_bytes,
    ),
  }
}

///|
fn client_node_values_publication_limits_with_plan(
  prepared : @publication_host.PreparedClientProgram,
  max_payload_bytes : Int,
  original : ClientLocalCapacityPlan?,
) -> @publication_host.PublicationOutputExportLimits? {
  if max_payload_bytes < 1 {
    return None
  }
  let profile_rows = @publication_host.prepared_client_values_max_rows(prepared)
  let graph = @publication_host.prepared_client_graph(prepared)
  let publication = match original {
    Some(plan) => {
      if plan.admitted_rows != profile_rows ||
        !(plan.graph is Some(owner) && physical_equal(owner, graph)) {
        return None
      }
      plan.publication
    }
    None => None
  }
  let rows = publication.map(value => value.rows).unwrap_or(profile_rows)
  let envelope = match publication {
    Some(value) => value.envelope
    None => client_local_result_envelope(graph, rows)
  }
  let tasks = @publication_host.prepared_client_requires_task_compilation(
    prepared,
  )
  let wire_proof = match publication {
    Some(value) => value.wire_bytes
    None => client_local_result_scalar_wire_bytes(graph, rows)
  }
  let bytes = Int::min(max_payload_bytes, wire_proof.unwrap_or(10000000))
  let schema_limits : @execution.RelationSchemaIdentityLimits = {
    max_fields: envelope.map(value => value.fields).unwrap_or(100),
    max_bytes: client_node_publication_schema_bytes(),
    max_nodes: 10000,
    max_depth: 64,
  }
  let schema_bytes = publication
    .map(value => value.schema_bytes)
    .unwrap_or(schema_limits.max_bytes)
  Some({
    max_result_fields: envelope.map(value => value.fields).unwrap_or(10),
    max_result_mapping_work: envelope
    .map(value => value.mapping_work)
    .unwrap_or(1000),
    // With no authored order, the Result view still initializes one row index
    // per row before its early completion. This is the same original row bound
    // that funds execution.rows.max_rows and the envelope workspace, not a
    // Result LIMIT/projection count or a sampled successful output count.
    // Ordered comparison work remains a separate, unresolved legacy profile.
    max_result_order_work: if envelope is Some(value) && value.order_terms == 0 {
      rows
    } else { 10000 },
    max_result_workspace_entries: envelope
    .map(value => value.publication_workspace_entries)
    .unwrap_or(if tasks { 100 } else { Int::max(100, rows) }),
    max_rows: if publication is Some(_) {
      rows
    } else if tasks {
      10000
    } else {
      rows
    },
    values: {
      max_nodes: 1000000,
      max_text_bytes: 10000000,
      max_depth: 64,
      max_work: 1000000,
    },
    payload_wire: {
      max_bytes: bytes,
      max_nodes: 1000000,
      max_depth: 64,
      max_columns: envelope.map(value => value.fields).unwrap_or(100),
      max_order_work: 1000000,
    },
    logical_wire: {
      max_bytes: bytes,
      max_nodes: 1000003,
      max_depth: 66,
      max_columns: envelope.map(value => value.fields).unwrap_or(100),
      max_order_work: 1000000,
    },
    schema: { ..schema_limits, max_bytes: schema_bytes, },
    max_batch_bytes: 65536,
  })
}
