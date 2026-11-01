///|
test "original declaration quantity facts exclude default meta syntax and retain canonical current association" {
  let root = staged_declaration_cursor(
    "{\"z\":{\"type\":\"number\",\"default\":[1,2],\"meta\":{\"x\":true}},\"a\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"one\",\"two\"]},\"default\":[\"one\"]}}",
  )
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  assert_true(
    @parameter_binding.observe_declaration_read_construction(original) is None,
  )
  @parameter_binding.advance_declaration_read(original)
  let cursor = @parameter_binding.declaration_read_type_cursor(original)
  let work = @parameter_binding.observe_declaration_read_construction(original)
  assert_true(
    work.unwrap() > 0L &&
    work.unwrap() <= 32L * @decode.admission_usage(root).nodes.to_int64(),
  )
  assert_true(
    physical_equal(
      work,
      @parameter_binding.declaration_read_construction_work(original),
    ),
  )
  assert_true(
    physical_equal(
      work,
      @parameter_binding.observe_declaration_read_construction(original),
    ),
  )
  assert_true(
    physical_equal(
      cursor,
      @parameter_binding.declaration_read_type_cursor(original),
    ),
  )
  let first = @parameter_binding.declaration_read_current_construction(original)
  assert_true(
    physical_equal(
      first,
      @parameter_binding.declaration_read_current_construction(original),
    ),
  )
  let a = first.unwrap()
  assert_eq(
    (a.type_syntax.types, a.type_syntax.arrays, a.type_syntax.enumerants),
    (2, 1, 2),
  )
  assert_eq(a.default_value.unwrap().nodes, 2)
  assert_true(a.metadata_fields is None)
  assert_eq(
    @parameter_binding.declaration_read_phase(original),
    @parameter_binding.DeclarationType,
  )
  @parameter_binding.advance_declaration_read(original)
  assert_true(
    physical_equal(
      first,
      @parameter_binding.declaration_read_current_construction(original),
    ),
  )
  @parameter_binding.advance_declaration_read(original)
  let z = @parameter_binding.declaration_read_current_construction(original).unwrap()
  assert_eq(
    (z.type_syntax.types, z.type_syntax.arrays, z.default_value.unwrap().nodes),
    (1, 0, 3),
  )
  assert_eq(z.metadata_fields, Some(1))
  assert_false(physical_equal(a, z))
  // Constructor observations do not admit the deliberately invalid Number
  // default. The existing value reader still owns the later typed refusal.
  assert_true(
    @parameter_binding.finish_declaration_read(original)
    is Err(@parameter_binding.Value(_)),
  )
  assert_true(
    @parameter_binding.declaration_read_construction_work(original) is None,
  )
  assert_true(
    @parameter_binding.declaration_read_current_construction(original) is None,
  )
}

///|
test "quantity observation never substitutes for original unknown-type refusal" {
  let root = staged_declaration_cursor(
    "{\"x\":{\"type\":\"unknown\",\"default\":{\"foo\":true},\"meta\":{\"type\":\"array\",\"items\":{\"type\":\"number\"}}}}",
  )
  let original = @parameter_binding.prepare_declaration_read(
    Some(root),
    limits(),
  ).0.unwrap()
  @parameter_binding.advance_declaration_read(original)
  @parameter_binding.observe_declaration_read_construction(original).unwrap()
  |> ignore
  let facts = @parameter_binding.declaration_read_current_construction(original).unwrap()
  assert_eq(
    (
      facts.type_syntax.types,
      facts.type_syntax.arrays,
      facts.type_syntax.objects,
    ),
    (1, 0, 0),
  )
  assert_eq(facts.default_value.unwrap().nodes, 2)
  assert_eq(facts.metadata_fields, Some(2))
  assert_true(
    @parameter_binding.finish_declaration_read(original)
    is Err(
      @parameter_binding.Contract(
        @contract.ContractIssue(@contract.UnknownType("unknown"), ..)
      )
    ),
  )
}

///|
test "declaration quantity inventory bounds original stack and retained observations independently" {
  let inventory = @parameter_binding.declaration_read_construction_inventory(
    3, 1,
  ).unwrap()
  assert_eq(
    (
      inventory.retained.record_headers,
      inventory.retained.reference_slots,
      inventory.retained.scalar_words,
    ),
    (12L, 24L, 29L),
  )
  assert_eq(
    (
      inventory.temporary.record_headers,
      inventory.temporary.reference_slots,
      inventory.temporary.scalar_words,
    ),
    (27L, 52L, 29L),
  )
  assert_true(
    @parameter_binding.declaration_read_construction_inventory(0, 1) is None,
  )
  assert_true(
    @parameter_binding.declaration_read_construction_inventory(3, 0) is None,
  )
  assert_true(
    @parameter_binding.declaration_read_construction_inventory(3, 3) is None,
  )
}
