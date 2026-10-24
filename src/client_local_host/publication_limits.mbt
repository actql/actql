///|
/// Source-free publication uses the same finite Local task value and output
/// envelope as dispatch. The installed Store ceiling may make it stricter;
/// it cannot increase row, field, workspace, wire or value capacity.
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
  if max_payload_bytes < 1 {
    return None
  }
  let rows = @publication_host.prepared_client_values_max_rows(prepared)
  let envelope = client_local_result_envelope(
    @publication_host.prepared_client_graph(prepared),
    rows,
  )
  let tasks = @publication_host.prepared_client_requires_task_compilation(
    prepared,
  )
  let wire_proof = client_local_result_scalar_wire_bytes(
    @publication_host.prepared_client_graph(prepared),
    rows,
  )
  let bytes = Int::min(max_payload_bytes, wire_proof.unwrap_or(10000000))
  Some({
    max_result_fields: envelope.map(value => value.fields).unwrap_or(10),
    max_result_mapping_work: envelope
    .map(value => value.mapping_work)
    .unwrap_or(1000),
    max_result_order_work: 10000,
    max_result_workspace_entries: envelope
    .map(value => value.publication_workspace_entries)
    .unwrap_or(if tasks { 100 } else { Int::max(100, rows) }),
    max_rows: if tasks {
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
      max_columns: 100,
      max_order_work: 1000000,
    },
    logical_wire: {
      max_bytes: bytes,
      max_nodes: 1000003,
      max_depth: 66,
      max_columns: 100,
      max_order_work: 1000000,
    },
    schema: {
      max_fields: 100,
      max_bytes: client_node_publication_schema_bytes(),
      max_nodes: 10000,
      max_depth: 64,
    },
    max_batch_bytes: 65536,
  })
}
