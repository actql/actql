///|
/// Select the existing Local row/import/export allocation model for one
/// original Command-input key phase. The row executor uses the SAME
/// InputKeyCursor algorithm; its full allowance is retained rather than
/// pretending that an entry ceiling is itself a byte count. The Result's
/// independent managed re-admission and both canonical exports overlap it.
/// This is an allowance quote, not an issuer, physical RSS bound or grant.
pub fn client_command_key_workspace_capacity(
  sequence : @execution.GeneratedSequence,
  limits : @publication_host.PublicationOutputExportLimits,
) -> @execution.ExecutionCapacity? {
  let (values, original, measurement) = client_local_execution_limits()
  let exported = client_local_export_limits(original.rows.max_rows, values)
  if limits.max_rows < 0 ||
    limits.max_rows > original.rows.max_rows ||
    limits.max_result_fields < 0 ||
    limits.max_result_fields > exported.wire.max_columns ||
    limits.max_result_mapping_work < 0 ||
    limits.max_result_mapping_work > original.rows.metadata_entries ||
    limits.max_result_order_work < 0 ||
    limits.max_result_order_work > original.rows.metadata_entries ||
    limits.max_result_workspace_entries < 0 ||
    limits.max_result_workspace_entries > original.rows.retained_entries ||
    limits.values.max_nodes < 1 ||
    limits.values.max_nodes > values.max_nodes ||
    limits.values.max_text_bytes < 0 ||
    limits.values.max_text_bytes > values.max_text_bytes ||
    limits.values.max_depth < 0 ||
    limits.values.max_depth > values.max_depth ||
    limits.values.max_work < 0 ||
    limits.values.max_work > values.max_work {
    return None
  }
  for wire in [limits.payload_wire, limits.logical_wire] {
    if wire.max_columns < 0 ||
      wire.max_columns > exported.wire.max_columns ||
      wire.max_order_work < 0 ||
      wire.max_order_work > exported.wire.max_order_work ||
      wire.max_bytes < 0 ||
      wire.max_bytes > exported.wire.max_bytes ||
      wire.max_nodes < 1 ||
      wire.max_nodes > exported.wire.max_nodes ||
      wire.max_depth < 0 ||
      // Logical relation framing may exceed the payload wire's depth (for
      // example 64 -> 66); quote its actual declared depth independently.
      wire.max_depth > values.max_depth {
      return None
    }
  }
  if limits.schema.max_fields < 0 ||
    limits.schema.max_fields > exported.wire.max_columns ||
    limits.schema.max_bytes < 0 ||
    limits.schema.max_bytes > limits.payload_wire.max_bytes ||
    limits.schema.max_nodes < 0 ||
    limits.schema.max_nodes > limits.payload_wire.max_nodes ||
    limits.schema.max_depth < 0 ||
    limits.schema.max_depth > limits.payload_wire.max_depth ||
    limits.max_batch_bytes < 1 ||
    limits.max_batch_bytes > exported.max_batch_bytes {
    return None
  }
  // The Command key adapter actually uses values.max_nodes for type frames.
  // Quote that original selected limit, not Local's smaller frame default.
  let executing : @execution.SequenceExecutionLimits = {
    ..original,
    max_frames: limits.values.max_nodes,
  }
  guard @execution.generated_sequence_capacity(sequence, executing, measurement)
    is Some(key) &&
    @local.local_import_retention_capacity({
      max_rows: limits.max_rows,
      values: limits.values,
      wire: limits.payload_wire,
      row: {
        max_bytes: limits.payload_wire.max_bytes,
        max_nodes: limits.payload_wire.max_nodes,
        max_depth: limits.payload_wire.max_depth,
        max_text_bytes: limits.values.max_text_bytes,
      },
      max_batch_bytes: limits.max_batch_bytes,
    })
    is Some(importing) &&
    @local.local_export_retention_capacity({
      max_rows: limits.max_rows,
      values: limits.values,
      wire: limits.payload_wire,
      max_batch_bytes: limits.max_batch_bytes,
    })
    is Some(payload) &&
    @local.local_export_retention_capacity({
      max_rows: limits.max_rows,
      values: limits.values,
      wire: limits.logical_wire,
      max_batch_bytes: limits.max_batch_bytes,
    })
    is Some(logical) else {
    return None
  }
  let retained = @execution.execution_capacity_retained_bytes(key)
  let scratch = @execution.execution_capacity_execution_bytes(key)
  let maximum = 9223372036854775807L
  if importing > maximum - retained ||
    payload > maximum - retained - importing ||
    logical > maximum - retained - importing - payload {
    return None
  }
  let retained = retained + importing + payload + logical
  if scratch > maximum - retained {
    return None
  }
  @execution.execution_capacity(retained, retained + scratch)
}
