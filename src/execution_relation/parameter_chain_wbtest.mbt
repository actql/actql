///|
fn parameter_preparation() -> (@lower.Prepared, @parameter.Declarations) {
  let declarations = @parameter.read_declarations(
    Some(input_cursor("{\"n\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let checked = @pipeline.check(
    input_cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":{\"$param\":\"n\"}}]},\"as\":\"seed\"},{\"derive\":{\"v\":\"id + $n\"}},{\"filter\":\"v > 0\"},{\"select\":[\"v\",\"id\"]}]",
    ),
    [],
    Some(declarations),
    None,
    {
      max_steps: 100,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  (
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    declarations,
  )
}

///|
fn bind_number(
  prepared : @lower.Prepared,
  declarations : @parameter.Declarations,
  n : Int,
) -> @lower.BoundPrepared {
  guard @parameter.bind(
      declarations,
      Some(input_cursor("{\"n\":" + n.to_string() + "}")),
      { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
    ).unwrap()
    is @parameter.Ready(values) else {
    abort("complete fixture bindings")
  }
  @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=1,
    max_name_bytes=1,
  ).unwrap()
}

///|
test "parameter cells and expressions use one bound invocation through all four operations" {
  let (prepared, declarations) = parameter_preparation()
  for n in [3, 7] {
    let owner = bind_number(prepared, declarations, n)
    let control = { remaining: 1000, max_frames: 100, }
    let output = row_output()
    let a = evaluate_rows(
      row_kernel(owner, 1),
      row_capture(owner),
      100,
      control,
      output,
    ).unwrap()
    let b = evaluate_rows(row_kernel(owner, 2), a, 100, control, output).unwrap()
    let c = evaluate_rows(row_kernel(owner, 3), b, 100, control, output).unwrap()
    assert_eq(c.names, ["v", "id"])
    assert_eq(c.rows.length(), 1)
    guard c.rows[0][0] is Number(v) && c.rows[0][1] is Number(id) else {
      fail("numeric output")
    }
    assert_eq(v, (n * 2).to_double())
    assert_eq(id, n.to_double())
  }
  let a = bind_number(prepared, declarations, 3)
  let b = bind_number(prepared, declarations, 7)
  assert_true(
    evaluate_rows(
      row_kernel(b, 1),
      row_capture(a),
      100,
      { remaining: 1000, max_frames: 100, },
      row_output(),
    )
    is Err(OwnerMismatch),
  )
}

///|
test "NULL predicate drops its row while lazy derived conditional preserves selected result" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"id\":null},{\"id\":2}]},\"as\":\"seed\"},{\"derive\":{\"v\":\"if(id IS NULL, 7, id + 1)\"}},{\"filter\":\"id > 0\"},{\"select\":[\"v\"]}]",
  )
  let control = { remaining: 1000, max_frames: 100, }
  let output = row_output()
  let a = evaluate_rows(
    row_kernel(owner, 1),
    row_capture(owner),
    100,
    control,
    output,
  ).unwrap()
  assert_true(a.rows[0][1] is Number(7.0))
  let b = evaluate_rows(row_kernel(owner, 2), a, 100, control, output).unwrap()
  let c = evaluate_rows(row_kernel(owner, 3), b, 100, control, output).unwrap()
  assert_eq(c.rows.length(), 1)
  assert_true(c.rows[0][0] is Number(3.0))
}
