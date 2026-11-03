///|
fn value_construction_reader(
  text : String,
) -> @parameter_binding.DeclarationReadInput {
  let root = staged_declaration_cursor(text)
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(nodes=1000, text=10000),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  @parameter_binding.observe_declaration_read_construction(original).unwrap()
  |> ignore
  @parameter_binding.advance_declaration_read(original)
  original
}

///|
test "original declaration Value quantities retain sequential families and exact current syntax" {
  let original = value_construction_reader(
    "{\"x\":{\"type\":\"number\",\"default\":42,\"meta\":{\"label\":\"x\"}}}",
  )
  let syntax = @parameter_binding.declaration_read_pending_syntax(original)
  let facts = @parameter_binding.declaration_read_current_construction(original)
  let inventory = @parameter_binding.declaration_value_construction_inventory(
    original, 0,
  ).unwrap()
  assert_eq(
    (
      inventory.returned.record_headers,
      inventory.returned.reference_slots,
      inventory.returned.scalar_words,
    ),
    (9L, 21L, 7L),
  )
  assert_eq(
    (
      inventory.metadata.record_headers,
      inventory.metadata.reference_slots,
      inventory.metadata.scalar_words,
    ),
    (47L, 138L, 69L),
  )
  assert_eq(
    (
      inventory.constraints.record_headers,
      inventory.constraints.reference_slots,
      inventory.constraints.scalar_words,
    ),
    (38L, 95L, 46L),
  )
  assert_true(
    physical_equal(
      syntax,
      @parameter_binding.declaration_read_pending_syntax(original),
    ),
  )
  assert_true(
    physical_equal(
      facts,
      @parameter_binding.declaration_read_current_construction(original),
    ),
  )
  @parameter_binding.advance_declaration_read(original)
  let result = @parameter_binding.finish_declaration_read(original).unwrap()
  assert_eq(@parameter_binding.declaration_count(result), 1)
  assert_true(
    @parameter_binding.has_default(
      @parameter_binding.declaration_at(result, 0).unwrap(),
    ),
  )
  assert_true(
    @parameter_binding.declaration_value_construction_inventory(original, 0)
    is None,
  )
}

///|
test "wide metadata quantities preserve original reserved-key refusal before bad default" {
  let fields = Array::makei(31, i => "\"p" + i.to_string() + "\":0")
  let original = value_construction_reader(
    "{\"x\":{\"type\":\"number\",\"default\":\"bad\",\"meta\":{" +
    fields.join(",") +
    ",\"actql_bad\":0}}}",
  )
  let syntax = @parameter_binding.declaration_read_pending_syntax(original).unwrap()
  let inventory = @parameter_binding.declaration_value_construction_inventory(
    original, 0,
  ).unwrap()
  assert_eq(
    (
      inventory.metadata.record_headers,
      inventory.metadata.reference_slots,
      inventory.metadata.scalar_words,
    ),
    (646L, 2150L, 1787L),
  )
  @parameter_binding.advance_declaration_read(original)
  guard @parameter_binding.finish_declaration_read(original)
    is Err(@parameter_binding.ParameterIssue(kind, path~, span~)) else {
    fail("original reserved metadata")
  }
  assert_eq(kind, @parameter_binding.ReservedMetadataKey)
  let child = @decode.field_at(syntax.metadata.unwrap(), 31).unwrap().1
  assert_eq(path, @decode.cursor_path(child))
  assert_eq(span, @decode.cursor_key_span(child).unwrap())
}

///|
test "Value call includes same caller Limits and outer Parameter refusal records" {
  let original = value_construction_reader(
    "{\"x\":{\"type\":\"number\",\"default\":42}}",
  )
  let syntax = @parameter_binding.declaration_read_pending_syntax(original).unwrap()
  let g = @parameter_binding.declaration_read_current_construction(original).unwrap().default_value.unwrap()
  let bare = @value.parameter_syntax_value_phase_construction_inventory(
    syntax, g, 2L, 20000,
  ).unwrap()
  let combined = @parameter_binding.declaration_value_construction_inventory(
    original, 0,
  ).unwrap().value.unwrap()
  // Original caller-owned Limits1H3W plus Parameter issue/Abort/state family
  //5H7R5W coexist during this Value call, not just during later constraints.
  assert_eq(
    (
      combined.temporary.record_headers - bare.temporary.record_headers,
      combined.temporary.reference_slots - bare.temporary.reference_slots,
      combined.temporary.scalar_words - bare.temporary.scalar_words,
    ),
    (6L, 7L, 8L),
  )
  assert_eq(
    (
      combined.temporary.record_headers,
      combined.temporary.reference_slots,
      combined.temporary.scalar_words,
    ),
    (89L, 145L, 256L),
  )
}
