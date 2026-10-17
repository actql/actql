///|
fn enum_contract(
  values : Array[String],
  nullable? : Bool = false,
) -> @contract.Contract {
  @contract.string_enum_contract(
    values,
    { max_nodes: 1000, max_depth: 2, max_text_bytes: 100000, },
    nullable~,
  ).unwrap()
}

///|
fn enum_source(wire : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(wire, {
      max_input_bytes: 100000,
      max_nodes: 1000,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 10,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn enum_limits() -> Limits {
  { max_nodes: 100, max_depth: 10, max_text_bytes: 100000, }
}

///|
test "Text enum admission checks exact membership nullability and original Unicode" {
  let contract = enum_contract(["low", "medium", "high", "e\u{0301}"])
  for wire in ["\"low\"", "\"medium\"", "\"high\"", "\"e\\u0301\""] {
    assert_true(admit(contract, enum_source(wire), enum_limits()) is Ok(_))
  }
  for wire in ["\"LOW\"", "\" low\"", "\"é\"", "1", "null"] {
    assert_true(admit(contract, enum_source(wire), enum_limits()) is Err(_))
  }
  assert_true(
    admit(enum_contract([], nullable=true), enum_source("null"), enum_limits())
    is Ok(value) &&
    value.value is Null,
  )
  assert_true(
    admit(enum_contract([]), enum_source("\"\""), enum_limits()) is Err(_),
  )
  let empty = enum_contract([""])
  assert_true(admit(empty, enum_source("\"\""), enum_limits()) is Ok(_))
  assert_true(checked_text_value("other", contract) is None)
  assert_true(checked_text_value("low", contract) is Some(_))
}

///|
test "Text enum metadata does not replace exact payload budgets or extent intersection" {
  let contract = @contract.string_enum_contract(
    ["a", "xxxx"],
    { max_nodes: 4, max_depth: 2, max_text_bytes: 5, },
    nullable=false,
    max_codepoints=Some(1L),
  ).unwrap()
  assert_true(
    admit(contract, enum_source("\"a\""), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 1,
    })
    is Ok(_),
  )
  assert_true(
    admit(contract, enum_source("\"a\""), {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 0,
    })
    is Err(_),
  )
  assert_true(admit(contract, enum_source("\"xxxx\""), enum_limits()) is Err(_))
  assert_true(
    recheck_runtime_value(Text("xxxx"), contract, enum_limits()) is None,
  )
  assert_true(
    recheck_runtime_value(Text("a"), contract, enum_limits()) is Some(_),
  )
}

///|
test "Text enum typed admission yields inside long candidates and cancels same custody" {
  let prefix = "x".repeat(1024)
  let contract = enum_contract([prefix + "a", prefix + "b"])
  let source = enum_source("\"" + prefix + "b\"")
  let cursor = start_typed_admission(contract, source, enum_limits()).unwrap()
  assert_true(advance_typed_admission(cursor) is TypedAdmissionContinue)
  for _ in 0..<4 {
    assert_true(advance_typed_admission(cursor) is TypedAdmissionContinue)
  }
  assert_true(
    cursor.frames[0] is TypedTextEnumeration(_, _, _, 0, offset) &&
    offset <= 256,
  )
  cancel_typed_admission(cursor)
  cancel_typed_admission(cursor)
  assert_true(
    cursor.frames.is_empty() && cursor.root is None && cursor.value is None,
  )
  assert_true(advance_typed_admission(cursor) is TypedAdmissionTerminal)
  let admitted = admit(contract, source, enum_limits()).unwrap()
  assert_true(admitted.value is Text(text) && text == prefix + "b")
  assert_true(
    admit(contract, enum_source("\"" + prefix + "c\""), enum_limits()) is Err(_),
  )
}

///|
test "Text enum resumed runtime recheck preserves payload counts and pending aliases" {
  let text = "x".repeat(257)
  let contract = enum_contract([text, "unused"])
  let cursor = start_recheck_runtime_text(text, contract, enum_limits()).unwrap()
  let mut saw_enum = false
  for _ in 0..<100 {
    if cursor.stack.last() is Some(TextEnumeration(_, _, _, _)) {
      saw_enum = true
      break
    }
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  assert_true(saw_enum)
  assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  assert_true(cursor.stack.last() is Some(TextEnumeration(_, _, _, 64)))
  cancel_recheck_runtime_value(cursor)
  assert_true(cursor.stack.is_empty())
  let fresh = start_recheck_runtime_text(text, contract, enum_limits()).unwrap()
  let mut complete = false
  for _ in 0..<100 {
    match advance_recheck_runtime_value(fresh) {
      RecheckContinue => ()
      RecheckComplete(value, nodes, bytes) => {
        assert_true(value.value is Text(original) && original == text)
        assert_eq((nodes, bytes), (1, 257))
        complete = true
        break
      }
      RecheckFailed => fail("matching original enum refused")
    }
  }
  assert_true(complete)
  assert_true(
    recheck_runtime_value(Text("other"), contract, enum_limits()) is None,
  )
}
