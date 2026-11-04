///|
// The selected non-HTTP writer supplies its actual construction original.
// Common retains it unchanged and adds only its existing JSON/capture/control
// constructors. Neither the quote nor transfer bound admits a physical attempt.
pub fn installed_physical_write_recipe_capacities(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  request_bytes : Int,
  recovery_bytes : Int,
  response_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  physical : @execution.ExecutionCapacity,
  control_wire_bytes? : Int? = None,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  let control_bytes = control_wire_bytes.unwrap_or(stored_bytes)
  if control_bytes < 1 ||
    control_bytes > stored_bytes ||
    stored_bytes < response_bytes ||
    response_bytes < 1 {
    return Err(Unsupported)
  }
  guard installed_standard_host_capture_row_capacity(
      body_bytes, body_nodes, body_depth,
    )
    is Some(capture_row) &&
    local_file_store_json_capacity(preview_bytes, preview_nodes, preview_depth)
    is Some(preview) &&
    local_file_store_json_capacity(recovery_bytes, preview_nodes, preview_depth)
    is Some(recovery) &&
    standard_create_sequence_pair_capacity(preview, recovery)
    is Some(capture_fixed) &&
    local_file_store_json_capacity(body_bytes, body_nodes, body_depth)
    is Some(input) &&
    local_file_store_json_capacity(request_bytes, body_nodes, body_depth)
    is Some(immutable_request) &&
    standard_create_sum_capacities(
      [input, preview, immutable_request],
      sequential_workspace=true,
    )
    is Some(request) &&
    standard_create_saved_control_capacity(
      control_bytes, stored_nodes, stored_depth,
    )
    is Some(saved) &&
    local_file_store_json_capacity(response_bytes, stored_nodes, stored_depth)
    is Some(projected) &&
    @execution.execution_capacity_inventory(
      [{ unit: QuotedBytes, count: stored_bytes.to_int64(), copies: 2, }],
      [],
      RetainedAlongsideExecution,
    )
    is Some(stored_buffers) &&
    standard_create_sum_capacities(
      [saved, stored_buffers, projected],
      sequential_workspace=true,
    )
    is Some(controls) else {
    return Err(Unsupported)
  }
  let no_additional_effect_id = @execution.execution_capacity(0L, 0L).unwrap()
  Ok([
    capture_fixed, capture_row, request, physical, controls, no_additional_effect_id,
  ])
}
