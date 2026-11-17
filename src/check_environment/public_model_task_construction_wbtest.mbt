///|
test "public Task metadata constructor keeps only its actual original retained quantities" {
  let wire = declaration_base("")
  let limits = declaration_limits()
  let peak = public_model_task_document_construction_extent(
    wire, "json", limits,
  ).unwrap()
  let task = read_public_model_task_document(wire, "json", limits).unwrap()
  let actual = public_model_task_declaration_retained_extent(task).unwrap()
  assert_true(peak.record_headers > actual.record_headers)
  assert_true(peak.reference_slots > actual.reference_slots)
  assert_true(peak.owned_utf16_units > actual.owned_utf16_units)
  let larger = {
    ..limits,
    bodies: { ..limits.bodies, max_bytes: 20000, max_nodes: 2000, },
  }
  let larger = public_model_task_document_construction_extent(
    wire, "json", larger,
  ).unwrap()
  assert_true(larger.record_headers > peak.record_headers)
  // Merely changing an unused constructor ceiling changes no already-retained
  // original Task or decoded quantity. It cannot grant another Task/Run.
  assert_eq(public_model_task_declaration_retained_extent(task), Some(actual))
  assert_true(
    public_model_task_document_construction_extent(wire, "other", limits)
    is None,
  )
  let normalization = public_model_task_normalization_construction_extent(
    task, limits,
  ).unwrap()
  let normalized = project_task_normalized("model-task:construction.original")
  let retained = normalized_public_model_task_retained_extent(normalized)
  assert_true(normalization.record_headers > retained.record_headers)
  assert_true(normalization.owned_wire_bytes > retained.owned_wire_bytes)
}
