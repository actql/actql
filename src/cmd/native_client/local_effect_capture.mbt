///|
// Both ordinary publication and original Effect capture use the same installed
// Source/Run ceilings. No separate Effect profile increases export capacity.
fn local_result_output_limits(
  run : LocalRunInstallation,
  configuration : @source_owner.ResidentSourceComputeConfiguration,
) -> @run_host.PublicationOutputExportLimits {
  let native = configuration.dispatch.native
  let transport = configuration.dispatch.transport
  let wire : @execution.RowWireLimits = {
    max_columns: transport.max_columns,
    max_order_work: native.metadata_work,
    max_bytes: run.result_payload_bytes.to_int(),
    max_nodes: native.values.max_nodes,
    max_depth: native.values.max_depth,
  }
  {
    max_result_fields: transport.max_columns,
    max_result_mapping_work: native.metadata_work,
    max_result_order_work: native.metadata_work,
    max_result_workspace_entries: native.metadata_work,
    max_rows: transport.max_rows,
    values: configuration.dispatch.local_execution.rows.output_values,
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: transport.max_columns,
      max_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    },
    max_batch_bytes: run.result_payload_bytes.to_int().min(16384),
  }
}
