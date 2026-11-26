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

///|
test "unused contract text policy does not inflate the original Task document quote" {
  let limits = declaration_limits()
  let loose = {
    ..limits,
    contracts: { ..limits.contracts, max_text_bytes: 65536, },
  }
  let denied = {
    ..limits,
    contracts: { ..limits.contracts, max_text_bytes: 1, },
  }
  let yaml =
    #|task: model-task:quote.original
    #|input: {notes: string}
    #|output: {enabled: boolean}
    #|instructions: >-
    #|  Preserve the authored text
    #|  and the original checked schema.
  for (wire, format) in [(declaration_base(""), "json"), (yaml, "yaml")] {
    let peak = public_model_task_document_construction_extent(
      wire, format, limits,
    ).unwrap()
    assert_eq(
      public_model_task_document_construction_extent(wire, format, loose),
      Some(peak),
    )
    let original = read_public_model_task_document(wire, format, limits).unwrap()
    let expanded = read_public_model_task_document(wire, format, loose).unwrap()
    for
      (first, second) in [
        (original.input, expanded.input),
        (original.output, expanded.output),
      ] {
      assert_eq(first.wire, second.wire)
      assert_eq(first.cid, second.cid)
    }
    assert_true(read_public_model_task_document(wire, format, denied) is Err(_))
  }
}

///|
test "Task construction funds YAML escapes whose decoded UTF-8 outgrows the document" {
  let limits = declaration_limits()
  let prefix = "task: model-task:quote.original\ninput: {kind: {type: string, enum: [\""
  let suffix = "\"]}}\noutput: {enabled: boolean}\ninstructions: preserve\n"
  let escaped = prefix + "\\L\\P".repeat(120) + suffix
  let same_wire_size = prefix + "abcd".repeat(120) + suffix
  assert_eq(escaped.length(), same_wire_size.length())
  let task = read_public_model_task_document(escaped, "yaml", limits).unwrap()
  assert_true(task.input.text > escaped.length())
  let ordinary = public_model_task_document_construction_extent(
    same_wire_size, "yaml", limits,
  ).unwrap()
  let expanded = public_model_task_document_construction_extent(
    escaped, "yaml", limits,
  ).unwrap()
  assert_true(expanded.owned_utf16_units > ordinary.owned_utf16_units)
}
