///|
fn typed_steps_contract(text : String) -> @contract.Contract {
  @contract.read_author(json_steps_cursor(text), {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
fn finish_typed_steps(
  admission : TypedAdmission,
) -> Result[(CheckedValue, Int, Int), Issue] {
  for _ in 0..<100000 {
    match advance_typed_admission(admission) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(value, nodes, text) =>
        return Ok((value, nodes, text))
      TypedAdmissionFailed(issue) => return Err(issue)
      TypedAdmissionTerminal => abort("premature typed admission terminal")
    }
  }
  cancel_typed_admission(admission)
  abort("typed admission did not terminate")
}

///|
// The synchronous Host convenience entry must use the same resumed owner.
// Independent wire spellings and usage counts below remain the expectations.
fn host_typed_usage(
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : Limits,
) -> Result[(CheckedValue, Int, Int), Issue] {
  admit_host_usage(
    bind_reference_reissuer((_, _) => None),
    contract,
    cursor,
    limits,
    {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
      max_text_units: 10000,
    },
  )
}

///|
fn typed_steps_wire(checked : CheckedValue) -> String raise {
  let writer = @encode.writer(10000, 1000, 100)
  emit_checked_wire_value(checked, writer)
  @encode.finish(writer)
}

///|
test "resumed typed admission retains nested typed values and exact usage" {
  let contract = typed_steps_contract(
    (
      #|{"type":"object","nullable":false,"fields":{"a":{"type":"array","nullable":false,"items":{"type":"object","nullable":false,"fields":{"d":{"type":"decimal","nullable":false,"precision":3,"scale":2},"n":{"type":"number","nullable":true}}}},"b":{"type":"boolean","nullable":false},"date":{"type":"date","nullable":false},"j":{"type":"json","nullable":true},"s":{"type":"string","nullable":false},"t":{"type":"timestamp","nullable":false},"v":{"type":"vector","nullable":false,"dimensions":2}}}
    ),
  )
  let cursor = json_steps_cursor(
    (
      #|{"v":[1,2],"t":"2026-10-05T00:00:00.000Z","s":"é","j":{"z":[null,2],"a":true},"date":"2026-10-05","b":false,"a":[{"n":null,"d":"1.20"}]}
    ),
  )
  let limits : Limits = { max_nodes: 17, max_depth: 4, max_text_bytes: 54, }
  let admission = start_typed_admission(contract, cursor, limits).unwrap()
  let (checked, nodes, text) = finish_typed_steps(admission).unwrap()
  let expected =
    #|{"a":[{"d":"1.20","n":null}],"b":false,"date":"2026-10-05","j":{"$json":{"a":true,"z":[null,2]}},"s":"é","t":"2026-10-05T00:00:00.000Z","v":[1,2]}
  assert_eq(typed_steps_wire(checked), expected)
  // 17 value nodes, 14 field-name bytes and 40 scalar bytes.
  assert_eq((nodes, text), (17, 54))
  let prior = host_typed_usage(contract, cursor, limits).unwrap()
  assert_eq((nodes, text), (prior.1, prior.2))
  assert_eq(typed_steps_wire(prior.0), expected)
  assert_true(physical_equal(checked.contract, contract))
  cancel_typed_admission(admission)
  cancel_typed_admission(admission)
  assert_true(advance_typed_admission(admission) is TypedAdmissionTerminal)
  assert_eq(typed_steps_wire(checked), expected)
}

///|
test "resumed typed admission preserves leaf and nullable reference contracts" {
  let limits : Limits = {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }
  for
    (contract, input, expected, usage) in [
      (@contract.primitive(NumberType, nullable=false), "2.5", "2.5", (1, 0)),
      (
        @contract.primitive(StringType, nullable=false),
        "\"e\\u0301\\r\"",
        "\"e\u0301\\r\"",
        (1, 4),
      ),
      (
        @contract.array_contract(
          @contract.primitive(NumberType, nullable=true),
          nullable=false,
        ).unwrap(),
        "[null,1]",
        "[null,1]",
        (3, 0),
      ),
      (
        typed_steps_contract(
          "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"record\"}",
        ),
        "null",
        "null",
        (1, 0),
      ),
      (@contract.primitive(JsonType, nullable=true), "null", "null", (1, 0)),
    ] {
    let cursor = json_steps_cursor(input)
    let (checked, nodes, text) = finish_typed_steps(
      start_typed_admission(contract, cursor, limits).unwrap(),
    ).unwrap()
    assert_eq(typed_steps_wire(checked), expected)
    assert_eq((nodes, text), usage)
    let prior = host_typed_usage(contract, cursor, limits).unwrap()
    assert_eq(typed_steps_wire(prior.0), expected)
    assert_eq((nodes, text), (prior.1, prior.2))
  }
  let reference = typed_steps_contract(
    "{\"type\":\"resource_ref\",\"nullable\":true,\"resource_kind\":\"record\"}",
  )
  assert_true(
    finish_typed_steps(
      start_typed_admission(reference, json_steps_cursor("{}"), limits).unwrap(),
    )
    is Err(ValueIssue(UnsupportedReference, ..)),
  )
}

///|
test "resumed typed refusal retains original issue kind path span and precedence" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nested = @contract.object_contract(
    [
      (
        "outer",
        @contract.object_contract(
          [("n", number)],
          nullable=false,
          max_fields=1,
          max_name_bytes=1,
        ).unwrap(),
      ),
    ],
    nullable=false,
    max_fields=1,
    max_name_bytes=5,
  ).unwrap()
  let normal : Limits = {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }
  for
    (contract, input, limits) in [
      (nested, "{\"outer\":{}}", normal),
      (nested, "{\"outer\":{\"x\":0}}", normal),
      (nested, "{\"outer\":{\"n\":null}}", normal),
      (nested, "{\"outer\":{\"n\":\"x\"}}", normal),
      (nested, "{\"outer\":{\"n\":1}}", { ..normal, max_nodes: 2, }),
      (nested, "{\"outer\":{\"x\":0}}", { ..normal, max_nodes: 1, }),
      (nested, "{\"outer\":{\"n\":1}}", { ..normal, max_text_bytes: 5, }),
      (nested, "{\"outer\":{\"n\":1}}", { ..normal, max_depth: 1, }),
      (@contract.vector_contract(2.0, nullable=false).unwrap(), "[1]", normal),
      (
        @contract.vector_contract(2.0, nullable=false).unwrap(),
        "[1,{}]",
        normal,
      ),
      (
        @contract.decimal_contract(3, 2, nullable=false).unwrap(),
        "\"1.2\"",
        normal,
      ),
      (@contract.primitive(DateType, nullable=false), "\"2026-02-30\"", normal),
      (
        @contract.primitive(TimestampType, nullable=false),
        "\"2026-10-05\"",
        normal,
      ),
      (
        @contract.string_contract(nullable=false, max_codepoints=Some(1L)).unwrap(),
        "\"ab\"",
        normal,
      ),
      (
        @contract.primitive(JsonType, nullable=false),
        "[[1,2],3]",
        { ..normal, max_nodes: 4, },
      ),
      (
        @contract.primitive(JsonType, nullable=false),
        "{\"z\":0,\"a\":1}",
        { ..normal, max_text_bytes: 0, },
      ),
      (
        @contract.primitive(JsonType, nullable=false),
        "{\"z\":{},\"a\":1}",
        { ..normal, max_text_bytes: 1, },
      ),
    ] {
    let cursor = json_steps_cursor(input)
    let resumed = start_typed_admission(contract, cursor, limits).unwrap()
    let result = finish_typed_steps(resumed)
    guard result is Err(issue) &&
      host_typed_usage(contract, cursor, limits) is Err(prior) else {
      abort("expected typed refusal")
    }
    assert_eq(issue, prior)
    assert_true(
      resumed.root is None && resumed.value is None && resumed.frames.is_empty(),
    )
    assert_true(advance_typed_admission(resumed) is TypedAdmissionTerminal)
  }
  // The missing field is located at the nested object, not the parent's key.
  let cursor = json_steps_cursor("{\"outer\":{}}")
  guard finish_typed_steps(
      start_typed_admission(nested, cursor, normal).unwrap(),
    )
    is Err(Decode(issue)) else {
    abort("missing field")
  }
  assert_eq(issue.path, [@source.Key("outer"), @source.Key("n")])
  assert_eq((issue.span.start_byte, issue.span.end_byte), (9, 11))
}

///|
test "wide typed schemas are not copied before a tiny value budget is refused" {
  let number = @contract.primitive(NumberType, nullable=false)
  let entries = []
  for index in 0..<1000 {
    entries.push(("f" + index.to_string(), number))
  }
  let contract = @contract.object_contract(
    entries,
    nullable=false,
    max_fields=1000,
    max_name_bytes=4000,
  ).unwrap()
  let cursor = json_steps_cursor("{}")
  let admission = start_typed_admission(contract, cursor, {
    max_nodes: 1,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
  assert_true(advance_typed_admission(admission) is TypedAdmissionContinue)
  assert_eq(admission.frames.length(), 1)
  guard admission.frames[0] is TypedObjectInput(object, 0) else {
    abort("indexed typed input")
  }
  assert_eq(object.children.length(), 0)
  assert_true(
    advance_typed_admission(admission)
    is TypedAdmissionFailed(ValueIssue(BudgetExceeded, ..)),
  )
  assert_eq(object.children.length(), 0)
}

///|
test "typed cancellation releases construction without clearing source or completed data" {
  let contract = typed_steps_contract(
    (
      #|{"type":"object","nullable":false,"fields":{"a":{"type":"array","nullable":false,"items":{"type":"json","nullable":true}},"v":{"type":"vector","nullable":false,"dimensions":2}}}
    ),
  )
  let cursor = json_steps_cursor("{\"v\":[1,2],\"a\":[{\"z\":[null,3]},null]}")
  let limits : Limits = {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }
  let seen_array = Ref(false)
  let seen_object = Ref(false)
  let seen_find = Ref(false)
  let seen_json = Ref(false)
  let seen_vector = Ref(false)
  for stop in 0..<90 {
    let admission = start_typed_admission(contract, cursor, limits).unwrap()
    for _ in 0..<stop {
      match advance_typed_admission(admission) {
        TypedAdmissionContinue => ()
        TypedAdmissionComplete(_, _, _) => break
        _ => abort("unexpected typed cancellation fixture failure")
      }
    }
    let saved = admission.frames.copy()
    cancel_typed_admission(admission)
    cancel_typed_admission(admission)
    assert_true(
      admission.frames.is_empty() &&
      admission.root is None &&
      admission.value is None,
    )
    assert_true(advance_typed_admission(admission) is TypedAdmissionTerminal)
    for frame in saved {
      match frame {
        TypedArrayNext(_, _, builder, _, _) | TypedArrayAppend(builder) => {
          seen_array.val = true
          assert_false(builder.open)
          assert_eq(builder.values.length(), 0)
        }
        TypedObjectNext(object, builder, _) => {
          seen_object.val = true
          assert_eq(object.children.length(), 0)
          assert_false(builder.open)
          assert_eq(builder.values.length(), 0)
        }
        TypedObjectFind(object, _, _, _, _, _) => {
          seen_find.val = true
          assert_eq(object.children.length(), 0)
        }
        TypedVectorNext(_, builder, _) => {
          seen_vector.val = true
          assert_false(builder.open)
          assert_eq(builder.values.length(), 0)
        }
        TypedJson(json, _) => {
          seen_json.val = true
          assert_true(
            json.frames.is_empty() && json.root is None && json.value is None,
          )
        }
        _ => ()
      }
    }
    assert_eq(@decode.object_length(cursor), Some(2))
  }
  assert_true(
    seen_array.val &&
    seen_object.val &&
    seen_find.val &&
    seen_json.val &&
    seen_vector.val,
  )
}
