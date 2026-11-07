///|
test "complete original Parameter Value phase retains once-expanded storage and fixed scalar families" {
  let syntax = @contract.read_parameter_syntax(
    json_steps_cursor("{\"type\":\"number\"}"),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let source = json_steps_cursor("42")
  let g = @decode.observe_subtree_construction_geometry(source)
  let body = parameter_syntax_value_body_construction_inventory(syntax, g).unwrap()
  assert_eq(
    body.value_extent,
    @shape.collection_construction_extent(body.values).unwrap(),
  )
  assert_eq(
    body.traversal_extent,
    @shape.collection_construction_extent(body.traversal).unwrap(),
  )
  let phase = parameter_syntax_value_phase_construction_inventory(
    syntax, g, 2L, 10,
  ).unwrap()
  assert_eq(
    (
      phase.returned.record_headers,
      phase.returned.reference_slots,
      phase.returned.scalar_words,
    ),
    (2L, 3L, 2L),
  )
  assert_eq(
    (
      phase.temporary.record_headers,
      phase.temporary.reference_slots,
      phase.temporary.scalar_words,
    ),
    (83L, 138L, 248L),
  )
  assert_true(phase.normalization is None)
  assert_eq((phase.returned_utf16_units, phase.temporary_utf16_units), (0L, 0L))
  assert_true(
    admit(syntax.parameter_type.contract, source, {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 0,
    }).unwrap().value
    is Number(42.0),
  )
  assert_true(
    parameter_syntax_value_phase_construction_inventory(syntax, g, -1L, 10)
    is None,
  )
  assert_true(
    parameter_syntax_value_phase_construction_inventory(syntax, g, 2L, -1)
    is None,
  )
}

///|
test "complete Parameter Value phase covers real wide default without changing semantic budgets" {
  let syntax = @contract.read_parameter_syntax(
    json_steps_cursor("{\"type\":\"array\",\"items\":{\"type\":\"number\"}}"),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let source = json_steps_cursor(
    "[" + Array::makei(100, i => i.to_string()).join(",") + "]",
  )
  let g = @decode.observe_subtree_construction_geometry(source)
  let phase = parameter_syntax_value_phase_construction_inventory(
    syntax, g, 2L, 10,
  ).unwrap()
  assert_eq((g.nodes, g.arrays, g.array_items), (101, 1, 100))
  assert_eq(
    (
      phase.returned.record_headers,
      phase.returned.reference_slots,
      phase.returned.scalar_words,
    ),
    (106L, 417L, 204L),
  )
  assert_eq(
    (
      phase.temporary.record_headers,
      phase.temporary.reference_slots,
      phase.temporary.scalar_words,
    ),
    (404L, 1619L, 1190L),
  )
  let original = start_typed_admission(syntax.parameter_type.contract, source, {
    max_nodes: 101,
    max_depth: 1,
    max_text_bytes: 0,
  }).unwrap()
  let mut result = None
  for _ in 0..<1000 {
    match advance_typed_admission(original) {
      TypedAdmissionContinue => ()
      TypedAdmissionComplete(v, n, t) => {
        assert_eq((n, t), (101, 0))
        result = Some(v)
        break
      }
      _ => abort("original wide Parameter Value")
    }
  }
  guard result.unwrap().value is Array(values) else { abort("original Array") }
  assert_eq(element_count(values), 100)
  assert_true(
    admit(syntax.parameter_type.contract, source, {
      max_nodes: 100,
      max_depth: 1,
      max_text_bytes: 0,
    })
    is Err(ValueIssue(BudgetExceeded, ..)),
  )
}

///|
test "same original Contract Value phase shares Parameter syntax construction without rechecking a value" {
  for
    (wire, value) in [
      ("{\"type\":\"number\"}", "42"),
      ("{\"type\":\"string\"}", "\"source text\""),
      ("{\"type\":\"decimal\",\"precision\":20,\"scale\":4}", "\"12.3400\""),
      ("{\"type\":\"array\",\"items\":{\"type\":\"number\"}}", "[1,2,3]"),
    ] {
    let syntax = @contract.read_parameter_syntax(json_steps_cursor(wire), {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    let source = json_steps_cursor(value)
    let geometry = @decode.observe_subtree_construction_geometry(source)
    let original = syntax.parameter_type.contract
    let direct = contract_value_phase_construction_inventory(
      original, geometry, 2L, 10,
    ).unwrap()
    let parameter = parameter_syntax_value_phase_construction_inventory(
      syntax, geometry, 2L, 10,
    ).unwrap()
    assert_eq(direct, parameter)
    assert_true(
      admit(original, source, {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      })
      is Ok(_),
    )
    assert_true(
      contract_value_phase_construction_inventory(original, geometry, -1L, 10)
      is None,
    )
    assert_true(
      contract_value_phase_construction_inventory(original, geometry, 2L, -1)
      is None,
    )
  }
}
