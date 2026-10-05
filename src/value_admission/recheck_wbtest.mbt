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
test "runtime recheck reports exact node and text usage" {
  let text = @contract.primitive(@contract.StringType, nullable=false)
  let items = @contract.array_contract(text, nullable=false).unwrap()
  let contract = @contract.object_contract(
    [("items", items)],
    nullable=false,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let source = recheck_admitted(contract, "{\"items\":[\"é\"]}")
  let result = recheck_runtime_value_usage(source.value, contract, {
    max_nodes: 20,
    max_depth: 5,
    max_text_bytes: 20,
  })
  assert_true(result is Some(_))
  let (checked, nodes, text_bytes) = result.unwrap()
  assert_true(physical_equal(checked.value, source.value))
  assert_eq(nodes, 3)
  assert_eq(text_bytes, 7)
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

///|
test "runtime recheck preserves admitted decimal coefficients" {
  let contract = @contract.decimal_contract(38, 2, nullable=false).unwrap()
  let value = decimal_from_coefficient("100", 38, 2).unwrap()
  let exact : Limits = { max_nodes: 1, max_depth: 0, max_text_bytes: 3, }
  assert_true(recheck_runtime_value(value, contract, exact) is Some(_))
  assert_true(
    recheck_runtime_value(value, contract, { ..exact, max_text_bytes: 2, })
    is None,
  )
  assert_true(
    recheck_runtime_value(
      value,
      @contract.decimal_contract(38, 1, nullable=false).unwrap(),
      exact,
    )
    is None,
  )
}

///|
test "runtime text recheck advances in bounded chunks with exact usage" {
  let contract = @contract.string_contract(
    nullable=false,
    min_length=Some(130L),
    max_codepoints=Some(130L),
    max_utf8_bytes=Some(134L),
  ).unwrap()
  let mut text = ""
  for _ in 0..<128 {
    text = text + "a"
  }
  text = text + "é😀"
  let limits : Limits = { max_nodes: 1, max_depth: 0, max_text_bytes: 134, }
  let cursor = start_recheck_runtime_text(text, contract, limits).unwrap()
  for _ in 0..<3 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  assert_true(
    advance_recheck_runtime_value(cursor) is RecheckComplete(_, 1, 134),
  )
  let one_short = start_recheck_runtime_text(text, contract, {
    ..limits,
    max_text_bytes: 133,
  }).unwrap()
  for _ in 0..<3 {
    assert_true(advance_recheck_runtime_value(one_short) is RecheckContinue)
  }
  assert_true(advance_recheck_runtime_value(one_short) is RecheckFailed)
  let malformed = String::from_array([(0xd800).unsafe_to_char()])
  let invalid = start_recheck_runtime_text(
    malformed,
    @contract.primitive(@contract.StringType, nullable=false),
    limits,
  ).unwrap()
  assert_true(advance_recheck_runtime_value(invalid) is RecheckContinue)
  assert_true(advance_recheck_runtime_value(invalid) is RecheckFailed)
}

///|
test "runtime Text recheck shares exact poll and logical usage boundaries" {
  let contract = @contract.primitive(@contract.StringType, nullable=false)
  // A node poll and a terminal poll surround the TextUnits polls. The empty
  // string still has one TextUnits poll; 64 ASCII units or 32 surrogate pairs
  // fit one chunk, while the next complete character needs a second chunk.
  // These literal counts are independent of the cursor's observed result.
  for
    (text, bytes, polls) in [
      ("", 0, 3),
      ("a", 1, 3),
      ("é", 2, 3),
      ("😀", 4, 3),
      ("a".repeat(64), 64, 3),
      ("a".repeat(65), 65, 4),
      ("😀".repeat(32), 128, 3),
      ("😀".repeat(33), 132, 4),
    ] {
    let limits : Limits = { max_nodes: 1, max_depth: 0, max_text_bytes: bytes, }
    // Raw count/group output and already admitted callers share the cursor.
    for raw in [false, true] {
      let cursor = if raw {
        start_recheck_runtime_text(text, contract, limits).unwrap()
      } else {
        start_recheck_runtime_value(Text(text), contract, limits).unwrap()
      }
      for _ in 0..<(polls - 1) {
        assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
      }
      match advance_recheck_runtime_value(cursor) {
        RecheckComplete(checked, nodes, text_bytes) => {
          assert_true(checked.value is Text(value) && value == text)
          assert_eq(nodes, 1)
          assert_eq(text_bytes, bytes)
        }
        _ => assert_true(false)
      }
      assert_true(cursor.stack.is_empty())
      assert_true(advance_recheck_runtime_value(cursor) is RecheckFailed)
    }
  }
}
