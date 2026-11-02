///|
test "Host capture retains all original text and preserves its whole constructor peak" {
  for (bytes, nodes, depth) in [(1, 1, 1), (256, 16, 4), (1000000, 100000, 64)] {
    let peak = installed_source_response_preserving_workspace(
      bytes, nodes, depth,
    ).unwrap()
    let (retained, workspace) = installed_host_json_retained_roles(
      peak,
      bytes,
      nodes,
      keep_full_text=true,
    ).unwrap()
    assert_eq(retained.owned_utf16_units, peak.owned_utf16_units)
    assert_eq(workspace.owned_utf16_units, 0L)
    assert_true(
      @execution.compose_preparation_representation([retained, workspace]).unwrap() ==
      peak,
    )
    let quote = installed_standard_host_capture_row_capacity(
      bytes, nodes, depth,
    ).unwrap()
    let encoded : @execution.PreparationRepresentationUnits = {
      record_headers: 2L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: bytes.to_int64(),
      owned_wire_bytes: bytes.to_int64(),
    }
    let old_peak = @execution.compose_preparation_representation([peak, encoded]).unwrap()
    assert_eq(
      @execution.execution_capacity_execution_bytes(quote),
      @execution.preparation_representation_cost(old_peak).unwrap(),
    )
    assert_true(
      @execution.execution_capacity_retained_bytes(quote) <
      @execution.execution_capacity_execution_bytes(quote),
    )
  }
  assert_true(installed_standard_host_capture_row_capacity(0, 16, 4) is None)
  let too_small : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  assert_true(
    installed_host_json_retained_roles(too_small, 256, 16, keep_full_text=true)
    is None,
  )
}
