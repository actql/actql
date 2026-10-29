///|
fn completed_source_limits() -> @parameter.DeclarationLimits {
  {
    max_parameters: 10,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }
}

///|
test "Source constructs from completed original declarations without advancing pending or foreign readers" {
  let p = parsed()
  let root = @decode.open_object(@stage.program_body(p)).unwrap()
  let params = @decode.lookup(root, "params")
  let original = @parameter.prepare_declaration_read(
    params,
    completed_source_limits(),
  ).0.unwrap()
  let (pending, work) = prepare_from_declaration_read(p, original)
  assert_true(pending is Err(ForeignDeclarations))
  assert_eq(work, 6L)
  assert_eq(@parameter.declaration_read_phase(original), DeclarationHeader)
  let original_declarations = @parameter.finish_declaration_read(original).unwrap()
  let (result, spent) = prepare_from_declaration_read(p, original)
  let source = result.unwrap()
  assert_true(physical_equal(program(source), p))
  assert_true(physical_equal(declarations(source), original_declarations))
  assert_eq((stage_count(source), spent), (2, 8L))
  assert_true(
    prepare_from_declaration_read(parsed(), original).0
    is Err(ForeignDeclarations),
  )
  let failed = @parameter.prepare_declaration_read(params, {
    ..completed_source_limits(),
    max_parameters: 0,
  }).0.unwrap()
  let original_error = @parameter.finish_declaration_read(failed)
  guard original_error is Err(issue) else { fail("original count refusal") }
  let (rejected, work) = prepare_from_declaration_read(p, failed)
  assert_true(rejected is Err(Declarations(_)))
  guard rejected is Err(Declarations(retained)) else { fail("retained issue") }
  assert_true(physical_equal(issue, retained))
  assert_eq(work, 6L)
}

///|
test "Source retains completed binding original including its typed refusal without a second bind" {
  let source = prepared(parsed())
  let supplied = Some(source_binding_cursor("{\"n\":7}"))
  let limits : @value.Limits = {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }
  let original = @parameter.prepare_binding_read(
    declarations(source),
    supplied,
    limits,
  ).unwrap()
  assert_true(
    retain_completed_binding(source, original) is Err(ForeignDeclarations),
  )
  assert_eq(@parameter.binding_read_phase(original), BindingHeader)
  guard @parameter.finish_binding_read(original) is Ok(Ready(values)) else {
    fail("original binding")
  }
  let snapshot = retain_completed_binding(source, original).unwrap()
  guard bind(snapshot, supplied, limits) is Ok(Ready(same)) else {
    fail("forwarded binding")
  }
  assert_true(physical_equal(values, same))
  assert_true(
    retain_completed_binding(prepared(parsed()), original)
    is Err(ForeignDeclarations),
  )
  let null_input = Some(source_binding_cursor("{\"n\":null}"))
  let failed = @parameter.prepare_binding_read(
    declarations(source),
    null_input,
    limits,
  ).unwrap()
  guard @parameter.finish_binding_read(failed) is Err(issue) else {
    fail("original NULL refusal")
  }
  let snapshot = retain_completed_binding(source, failed).unwrap()
  guard bind(snapshot, null_input, limits) is Err(retained) else {
    fail("no false Ready")
  }
  assert_true(physical_equal(issue, retained))
}

///|
test "Source constructor inventory prices actual root Map Stage copy and separate binding snapshot" {
  let inventory = source_construction_inventory(parsed()).unwrap()
  assert_eq(inventory.returned, {
    record_headers: 5L,
    reference_slots: 26L,
    scalar_words: 3L,
  })
  assert_eq(inventory.temporary, {
    record_headers: 45L,
    reference_slots: 111L,
    scalar_words: 101L,
  })
  assert_eq(inventory.maximum_work, 8L)
  let bindings = source_binding_construction_inventory()
  assert_eq(bindings.returned, {
    record_headers: 2L,
    reference_slots: 7L,
    scalar_words: 1L,
  })
  assert_eq(bindings.temporary, {
    record_headers: 5L,
    reference_slots: 10L,
    scalar_words: 4L,
  })
  assert_eq(bindings.maximum_work, 0L)
}
