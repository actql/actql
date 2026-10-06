///|
fn effect_json_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
test "checked JSON author admission retains exact keys independently of wire mode" {
  let source =
    #|{"é":1,"é":2,"\r":3,"\n":4,"\r\n":5,"nested":[{"$json":{"é":"é\r\n"}}]}
  let expected =
    #|{"$json":{"\n":4,"\r":3,"\r\n":5,"é":2,"nested":[{"$json":{"é":"é\r\n"}}],"é":1}}
  let contract = @contract.primitive(@contract.JsonType, nullable=false)
  let (checked, _, _) = admit_usage(contract, effect_json_cursor(source), {
    max_nodes: 100,
    max_depth: 20,
    max_text_bytes: 1000,
  }).unwrap()
  assert_eq(typed_steps_wire(checked), expected)
  let restored = admit_wire(contract, effect_json_cursor(expected), {
    max_nodes: 100,
    max_depth: 20,
    max_text_bytes: 1000,
  }).unwrap()
  assert_eq(typed_steps_wire(restored), expected)
}

///|
test "JSON author admission keeps SQL NULL and wire JSON null distinct" {
  let nullable = @contract.primitive(@contract.JsonType, nullable=true)
  let limits = { max_nodes: 20, max_depth: 5, max_text_bytes: 100, }
  let raw = admit_usage(nullable, effect_json_cursor("null"), limits).unwrap().0
  assert_eq(typed_steps_wire(raw), "null")
  let tagged = admit_wire(
    nullable,
    effect_json_cursor("{\"$json\":null}"),
    limits,
  ).unwrap()
  assert_eq(typed_steps_wire(tagged), "{\"$json\":null}")
  let ordinary = admit_usage(
      nullable,
      effect_json_cursor("{\"$json\":null}"),
      limits,
    ).unwrap().0
  assert_eq(typed_steps_wire(ordinary), "{\"$json\":{\"$json\":null}}")
  assert_true(
    admit_usage(
      @contract.primitive(@contract.JsonType, nullable=false),
      effect_json_cursor("null"),
      limits,
    )
    is Err(ValueIssue(UnexpectedNull, ..)),
  )
}

///|
test "authored Object fields normalize while nested JSON fields retain data keys" {
  let contract = typed_steps_contract(
    (
      #|{"type":"object","nullable":false,"fields":{"é":{"type":"string","nullable":false},"j":{"type":"json","nullable":false}}}
    ),
  )
  let source =
    #|{"é":"v","j":{"é":1,"é":2,"\r\n":"data"}}
  let limits = { max_nodes: 100, max_depth: 10, max_text_bytes: 100, }
  let cursor = effect_json_cursor(source)
  assert_true(admit_usage(contract, cursor, limits) is Err(_))
  assert_true(admit_wire(contract, cursor, limits) is Err(_))
  let checked = admit_usage(contract, cursor, limits, authored_fields=true).unwrap().0
  let expected =
    #|{"j":{"$json":{"\r\n":"data","é":1,"é":2}},"é":"v"}
  assert_eq(typed_steps_wire(checked), expected)
  let collision = effect_json_cursor(
    (
      #|{"é":"v","é":"v","j":{}}
    ),
  )
  assert_true(
    admit_usage(contract, collision, limits, authored_fields=true)
    is Err(Decode({ kind: @decode.DuplicateField, .. })),
  )
  assert_true(
    start_typed_admission(
      contract,
      cursor,
      limits,
      wire=true,
      authored_fields=true,
    )
    is Err(ValueIssue(InvalidLimits, ..)),
  )
}

///|
test "authored JSON admission retains exact bounds and cancellation" {
  let contract = @contract.primitive(@contract.JsonType, nullable=false)
  let cursor = effect_json_cursor(
    (
      #|{"é":[1,2,3],"é":[4,5,6]}
    ),
  )
  let normal = { max_nodes: 100, max_depth: 10, max_text_bytes: 100, }
  let (_, nodes, text) = admit_usage(contract, cursor, normal).unwrap()
  let exact = { max_nodes: nodes, max_depth: 2, max_text_bytes: text, }
  assert_true(admit_usage(contract, cursor, exact) is Ok(_))
  for
    limited in [
      { ..exact, max_nodes: nodes - 1, },
      { ..exact, max_depth: 1, },
      { ..exact, max_text_bytes: text - 1, },
    ] {
    assert_true(
      admit_usage(contract, cursor, limited)
      is Err(ValueIssue(BudgetExceeded, ..)),
    )
  }
  let admission = start_typed_admission(
    contract,
    cursor,
    normal,
    authored_fields=true,
  ).unwrap()
  assert_true(advance_typed_admission(admission) is TypedAdmissionContinue)
  assert_true(advance_typed_admission(admission) is TypedAdmissionContinue)
  cancel_typed_admission(admission)
  assert_true(admission.frames.is_empty())
  assert_true(admission.root is None)
  assert_true(admission.value is None)
  assert_true(advance_typed_admission(admission) is TypedAdmissionTerminal)
}
