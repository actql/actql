///|
fn recheck_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(
      text,
      { max_input_bytes: 1000, max_nodes: 100, max_depth: 10, },
      source_path="runtime-recheck.json",
    ).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
fn recheck_admitted(
  contract : @contract.Contract,
  text : String,
) -> CheckedValue {
  admit(contract, recheck_cursor(text), {
    max_nodes: 100,
    max_depth: 10,
    max_text_bytes: 1000,
  }).unwrap()
}

///|
test "runtime recheck preserves exact nested typed values" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let item = @contract.array_contract(
    number,
    nullable=false,
    max_items=Some(2L),
  ).unwrap()
  let contract = @contract.object_contract(
    [("items", item)],
    nullable=false,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let source = recheck_admitted(contract, "{\"items\":[1,2]}")
  let checked = recheck_runtime_value(source.value, contract, {
    max_nodes: 4,
    max_depth: 2,
    max_text_bytes: 5,
  }).unwrap()
  assert_true(physical_equal(checked.value, source.value))
  assert_true(physical_equal(checked.contract, contract))
}

///|
test "runtime recheck rejects foreign contracts and exhausted limits" {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let source = recheck_admitted(text, "\"hello\"")
  let exact : Limits = { max_nodes: 1, max_depth: 1, max_text_bytes: 5, }
  assert_true(recheck_runtime_value(source.value, text, exact) is Some(_))
  assert_true(recheck_runtime_value(source.value, number, exact) is None)
  assert_true(
    recheck_runtime_value(source.value, text, { ..exact, max_nodes: 0, })
    is None,
  )
  assert_true(
    recheck_runtime_value(source.value, text, { ..exact, max_text_bytes: 4, })
    is None,
  )
}

///|
test "runtime recheck enforces array depth and item count" {
  let number = @contract.primitive(@contract.NumberType, nullable=false)
  let contract = @contract.array_contract(
    @contract.array_contract(number, nullable=false, max_items=Some(1L)).unwrap(),
    nullable=false,
    max_items=Some(1L),
  ).unwrap()
  let source = recheck_admitted(contract, "[[1]]")
  let exact : Limits = { max_nodes: 3, max_depth: 2, max_text_bytes: 0, }
  assert_true(recheck_runtime_value(source.value, contract, exact) is Some(_))
  assert_true(
    recheck_runtime_value(source.value, contract, { ..exact, max_depth: 1, })
    is None,
  )
  assert_true(
    recheck_runtime_value(source.value, contract, { ..exact, max_nodes: 2, })
    is None,
  )
}
