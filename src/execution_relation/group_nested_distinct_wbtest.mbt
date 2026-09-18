///|
fn nested_array_contract(depth : Int) -> String {
  let mut contract = "{\"type\":\"number\",\"nullable\":false}"
  for index = 0; index < depth; index = index + 1 {
    contract = "{\"type\":\"array\",\"nullable\":false,\"max_items\":1,\"items\":" +
      contract +
      "}"
  }
  contract
}

///|
fn nested_array_value(value : Int, depth : Int) -> String {
  "[".repeat(depth) + value.to_string() + "]".repeat(depth)
}

///|
fn nested_distinct_program(
  contract : String,
  rows : String,
  distinct : Bool,
) -> @lower.BoundPrepared {
  bound_pipeline(
    "[{\"values\":{\"schema\":{\"v\":" +
    contract +
    "},\"rows\":" +
    rows +
    "},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\",\"field\":\"v\",\"distinct\":" +
    distinct.to_string() +
    "}}}}]",
  )
}

///|
fn execute_nested_count(
  owner : @lower.BoundPrepared,
  limits : SequenceRunLimits,
  max_work : Int,
) -> Double raise {
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["group_1"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: limits,
    max_work,
    max_frames: 100,
  }).unwrap()
  guard completed_cell(completed_output(result, Step(1)).unwrap(), 0, 0)
    is Some(Number(value)) else {
    abort("count result expected")
  }
  value
}

///|
test "count distinct accepts admitted values deeper than four containers" {
  let depth = 6
  let one = nested_array_value(1, depth)
  let two = nested_array_value(2, depth)
  let rows = "[{\"v\":" +
    one +
    "},{\"v\":" +
    one +
    "},{\"v\":" +
    two +
    "},{\"v\":null}]"
  let nullable_contract = "{\"type\":\"array\",\"nullable\":true,\"max_items\":1,\"items\":" +
    nested_array_contract(depth - 1) +
    "}"
  let distinct = nested_distinct_program(nullable_contract, rows, true)
  assert_eq(execute_nested_count(distinct, run_limits(), 100000), 2.0)
  let all = nested_distinct_program(nullable_contract, rows, false)
  assert_eq(execute_nested_count(all, run_limits(), 100000), 3.0)
}

///|
test "count distinct compares complete nested objects after identity bucketing" {
  let contract = "{\"type\":\"object\",\"nullable\":true,\"fields\":{\"payload\":" +
    nested_array_contract(5) +
    "}}"
  let one = "{\"payload\":" + nested_array_value(1, 5) + "}"
  let two = "{\"payload\":" + nested_array_value(2, 5) + "}"
  let rows = "[{\"v\":" +
    one +
    "},{\"v\":" +
    one +
    "},{\"v\":" +
    two +
    "},{\"v\":null}]"
  let owner = nested_distinct_program(contract, rows, true)
  assert_eq(execute_nested_count(owner, run_limits(), 100000), 2.0)
}

///|
test "count distinct keeps empty and all null global group laws" {
  let contract = "{\"type\":\"array\",\"nullable\":true,\"max_items\":1,\"items\":" +
    nested_array_contract(5) +
    "}"
  let empty = nested_distinct_program(contract, "[]", true)
  assert_eq(execute_nested_count(empty, run_limits(), 100000), 0.0)
  let nulls = nested_distinct_program(
    contract, "[{\"v\":null},{\"v\":null}]", true,
  )
  assert_eq(execute_nested_count(nulls, run_limits(), 100000), 0.0)
}

///|
test "runtime identity uses configured depth node work and frame ceilings" {
  let owner = nested_distinct_program(
    nested_array_contract(6),
    "[{\"v\":" + nested_array_value(1, 6) + "}]",
    true,
  )
  let input = row_capture(owner)
  let value = input.rows[0][0]
  let generous : ValueLimits = {
    max_nodes: 7,
    max_text_bytes: 0,
    max_depth: 6,
    max_work: 13,
  }
  let exact_control = { remaining: 13, max_frames: 100, }
  let exact_workspace = { limit: 6, live: 0, peak: 0, }
  assert_true(
    runtime_value_identity(value, exact_control, exact_workspace, generous)
    is Ok(_),
  )
  assert_eq(exact_control.remaining, 0)
  assert_eq(exact_workspace.live, 0)
  assert_eq(exact_workspace.peak, 6)
  assert_true(
    runtime_value_identity(
      value,
      { remaining: 12, max_frames: 100, },
      { limit: 6, live: 0, peak: 0, },
      generous,
    )
    is Err(RowLimit),
  )
  for
    short in [
      { ..generous, max_nodes: 6, },
      { ..generous, max_depth: 5, },
      { ..generous, max_work: 12, },
    ] {
    let control = { remaining: 13, max_frames: 100, }
    let workspace = { limit: 6, live: 0, peak: 0, }
    assert_true(
      runtime_value_identity(value, control, workspace, short) is Err(RowLimit),
    )
    assert_eq(workspace.live, 0)
  }
  assert_true(
    runtime_value_identity(
      value,
      { remaining: 13, max_frames: 100, },
      { limit: 5, live: 0, peak: 0, },
      generous,
    )
    is Err(RowLimit),
  )
}
