///|
fn cursor(text : String) -> @decode.Cursor {
  let node = @source.parse_json(text, {
    max_input_bytes: 100000,
    max_nodes: 10000,
    max_depth: 1000,
  }).unwrap()
  @decode.admit(node, {
    max_nodes: 10000,
    max_depth: 1000,
    max_string_bytes: 100000,
    max_total_string_bytes: 100000,
  }).unwrap()
}

///|
fn field(root : @decode.Cursor, name : String) -> @decode.Cursor {
  @decode.lookup(@decode.open_object(root).unwrap(), name).unwrap()
}

///|
fn checked(
  root : @decode.Cursor,
  steps : @decode.Cursor,
) -> @pipeline.CheckedPipeline {
  let declarations = @parameter.read_declarations(
    @decode.lookup(@decode.open_object(root).unwrap(), "params"),
    {
      max_parameters: 100,
      max_nodes: 10000,
      max_depth: 1000,
      max_text_bytes: 100000,
    },
  ).unwrap()
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("amount"),
        @contract.primitive(NumberType, nullable=false),
      ),
    ],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  @pipeline.check(steps, [("rows", schema)], Some(declarations), None, {
    max_steps: 100,
    max_work: 1000000,
    max_nodes: 100000,
    max_depth: 1000,
    max_text_bytes: 100000,
    max_tokens: 10000,
  }).unwrap()
}

///|
fn limits() -> Limits {
  {
    max_work: 100000,
    max_slots: 100,
    max_references: 100,
    max_pointer_units: 10000,
    max_direct_text_bytes: 10000,
  }
}

///|
test "combined pipeline Parameter collection retains all local occurrences with shared budgets" {
  let root = cursor(
    (
      #|{"params":{"n":{"type":"number","default":2,"meta":{"note":"not identity"}}},"steps":[{"derive":{"y":"$n + $n"},"as":"unused"},{"take":{"$param":"n"},"from":"rows","meta":{"$param":"annotation"}}]}
    ),
  )
  let steps = field(root, "steps")
  let p = checked(root, steps)
  let collected = collect(root, p, limits()).unwrap()
  assert_true(physical_equal(pipeline(collected), p))
  let refs = index(collected)
  assert_true(
    physical_equal(
      @references.declarations(refs),
      @pipeline.parameters(p).unwrap(),
    ),
  )
  assert_eq(@references.reference_count(refs), 3)
  assert_eq(
    @references.reference_at(refs, 0).unwrap().path,
    "/steps/0/derive/y/add/0",
  )
  assert_eq(
    @references.reference_at(refs, 1).unwrap().path,
    "/steps/0/derive/y/add/1",
  )
  assert_eq(@references.reference_at(refs, 2).unwrap().path, "/steps/1/take")
  assert_eq(@pipeline.expression_slot_count(expressions(collected)), 1)
  assert_eq(@pipeline.parameter_slot_count(operands(collected)), 1)
  let exact : Limits = {
    max_work: work(collected),
    max_slots: 2,
    max_references: 3,
    max_pointer_units: @references.pointer_units(refs),
    max_direct_text_bytes: direct_text_bytes(collected),
  }
  assert_true(collect(root, p, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_slots: 1, },
      { ..exact, max_references: 2, },
      { ..exact, max_pointer_units: exact.max_pointer_units - 1, },
      { ..exact, max_direct_text_bytes: exact.max_direct_text_bytes - 1, },
    ] {
    assert_true(collect(root, p, cap) is Err(_))
  }
  let local_index = index(collect(steps, p, limits()).unwrap())
  assert_eq(
    @references.reference_at(local_index, 0).unwrap().path,
    "/0/derive/y/add/0",
  )
  assert_eq(@references.reference_count(local_index), 3)
}

///|
test "root ownership is enforced even for empty Parameter collections" {
  let text = "{\"a\":[],\"b\":[]}"
  let root = cursor(text)
  let p = checked(root, field(root, "a"))
  let value = collect(root, p, limits()).unwrap()
  assert_eq(@references.reference_count(index(value)), 0)
  assert_true(collect(cursor(text), p, limits()) is Err(ForeignRoot))
  assert_true(collect(field(root, "b"), p, limits()) is Err(ForeignRoot))
  assert_true(
    collect(root, p, { ..limits(), max_work: -1, }) is Err(InvalidLimits),
  )
  let exact : Limits = {
    max_work: work(value),
    max_slots: 0,
    max_references: 0,
    max_pointer_units: 0,
    max_direct_text_bytes: 0,
  }
  assert_true(collect(root, p, exact) is Ok(_))
}

///|
test "direct operand text allowance is shared across steps" {
  let root = cursor(
    "{\"params\":{\"n\":{\"type\":\"number\"}},\"steps\":[{\"take\":{\"$param\":\"n\"}},{\"take\":{\"$param\":\"n\"}}]}",
  )
  let p = checked(root, field(root, "steps"))
  let value = collect(root, p, limits()).unwrap()
  assert_eq(@references.reference_count(index(value)), 2)
  let bytes = direct_text_bytes(value)
  assert_true(bytes > 0)
  assert_true(
    collect(root, p, { ..limits(), max_direct_text_bytes: bytes, }) is Ok(_),
  )
  assert_true(
    collect(root, p, { ..limits(), max_direct_text_bytes: bytes / 2, })
    is Err(_),
  )
}

///|
test "a pipeline without a declaration owner has an empty reference index" {
  let root = cursor("[]")
  let p = @pipeline.check(root, [], None, None, {
    max_steps: 0,
    max_work: 100,
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 100,
    max_tokens: 0,
  }).unwrap()
  assert_true(@pipeline.parameters(p) is None)
  let value = collect(root, p, limits()).unwrap()
  assert_eq(@references.reference_count(index(value)), 0)
}
