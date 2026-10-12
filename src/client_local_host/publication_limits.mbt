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
