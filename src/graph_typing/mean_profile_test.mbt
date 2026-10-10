///|
fn mean_profile_body(
  names : String,
  weights : String,
  properties : String,
) -> String {
  "{\"with\":" +
  names +
  ",\"weights\":" +
  weights +
  ",\"support\":{\"nodes\":1,\"edges\":0.5},\"properties\":{\"nodes\":" +
  properties +
  ",\"edges\":{}}}"
}

///|
test "Mean checks all sample occurrences and joins nullable Number properties without a union reduction" {
  let number = @contract.primitive(NumberType, nullable=false)
  let nullable = @contract.primitive(NumberType, nullable=true)
  let first = union_test_graph([union_test_node("N", [("score", number)])])
  let second = union_test_graph([union_test_node("N", [("score", nullable)])])
  let body = mean_profile_body(
    "[\"a\",\"b\",\"a\"]", "[1,0,2]", "{\"score\":{\"mean\":{\"missing\":\"exclude\",\"nulls\":\"zero\"}}}",
  )
  let checked = @graph_typing.check_mean(
    cursor(body),
    [first, second, first],
    limits(),
  ).unwrap()
  let options = @graph_typing.checked_mean_options(checked)
  assert_eq(@graph_typing.mean_input_names(options), ["a", "b", "a"])
  assert_eq(@graph_typing.mean_weights(options), [1.0, 0.0, 2.0])
  assert_eq(@graph_typing.mean_sample_count(options), 3)
  guard @graph_typing.mean_output(checked) is @carrier.GraphValue(graph) else {
    fail("typed mean Graph output")
  }
  let definition = @carrier.graph_definition(graph)
  let node = @carrier.graph_node_at(definition, 0).unwrap()
  let field = @carrier.field_at(
    @carrier.graph_element_definition_properties(node),
    0,
  ).unwrap()
  assert_true(@contract.type_equal(field.contract.unwrap(), nullable, 100))
  for sample in 0..<3 {
    assert_eq(
      @graph_typing.mean_definition_at(checked, sample, 0, edge=false),
      Some(0),
    )
    assert_eq(
      @graph_typing.mean_property_input_at(checked, sample, 0, 0, edge=false),
      Some(0),
    )
  }
  assert_eq(@graph_typing.mean_pending_count(checked), 7)
  assert_eq(
    @graph_typing.mean_pending_at(checked, 4),
    Some(@graph_typing.ApplyExactMeanSupport),
  )
  assert_eq(@graph_typing.mean_pending_at(checked, 7), None)
}

///|
test "Mean singleton numerical output is nullable and aliases require every sample" {
  let number = @contract.primitive(NumberType, nullable=false)
  let first = union_test_graph([union_test_node("N", [("score", number)])])
  let second = union_test_graph([
    union_test_node("N", [("score", number)], key="other_key"),
  ])
  let properties = "{\"score\":{\"mean\":{\"missing\":\"zero\",\"nulls\":\"exclude\"}}}"
  for
    (names, weights, inputs, aliases) in [
      ("[\"a\"]", "[1]", [first], ["original_key"]),
      ("[\"a\",\"b\",\"a\"]", "[1,2,1]", [first, second, first], []),
    ] {
    let checked = @graph_typing.check_mean(
      cursor(mean_profile_body(names, weights, properties)),
      inputs,
      limits(),
    ).unwrap()
    guard @graph_typing.mean_output(checked) is @carrier.GraphValue(graph) else {
      fail("Graph")
    }
    let node = @carrier.graph_node_at(@carrier.graph_definition(graph), 0).unwrap()
    assert_eq(@carrier.graph_element_definition_key_count(node), 1)
    assert_eq(
      @carrier.graph_element_definition_key_column_at(node, 0),
      aliases.get(0),
    )
    let field = @carrier.field_at(
      @carrier.graph_element_definition_properties(node),
      0,
    ).unwrap()
    assert_true(
      @contract.type_equal(
        field.contract.unwrap(),
        @contract.primitive(NumberType, nullable=true),
        100,
      ),
    )
  }
}

///|
test "Mean refuses missing policies incompatible types foreign domains and zero-weight invalid samples" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let first = union_test_graph([union_test_node("N", [("score", number)])])
  let body = mean_profile_body(
    "[\"a\",\"b\"]", "[1,0]", "{\"score\":{\"mean\":{\"missing\":\"exclude\",\"nulls\":\"fail\"}}}",
  )
  for
    (right, expected) in [
      (
        union_test_graph([union_test_node("N", [("score", text)])]),
        @graph_typing.IncompatibleGraphDomains,
      ),
      (
        union_test_graph(
          [union_test_node("N", [("score", number)])],
          domain="sha256:1111111111111111111111111111111111111111111111111111111111111111",
        ),
        @graph_typing.IncompatibleGraphDomains,
      ),
      (@carrier.unknown_carrier(GraphKind), @graph_typing.IncompleteGraph),
    ] {
    assert_true(
      @graph_typing.check_mean(cursor(body), [first, right], limits())
      is Err({ kind, .. }) &&
      kind == expected,
    )
  }
  assert_true(
    @graph_typing.check_mean(
      cursor(mean_profile_body("[\"a\"]", "[1]", "{}")),
      [first],
      limits(),
    )
    is Err({ kind: @graph_typing.InvalidPropertyStrategy("score"), .. }),
  )
  let text_graph = union_test_graph([union_test_node("N", [("score", text)])])
  assert_true(
    @graph_typing.check_mean(cursor(body), [text_graph, text_graph], limits())
    is Err({ kind: @graph_typing.IncompatiblePropertyStrategy("score"), .. }),
  )
  assert_true(
    @graph_typing.check_mean(cursor(body), [first], limits())
    is Err({ kind: @graph_typing.InvalidBody, .. }),
  )
}

///|
test "Mean exact-equal policy preserves data contracts rather than imposing numeric output" {
  let text = union_test_contract(
    "{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":10}",
  )
  let graph = union_test_graph([union_test_node("N", [("name", text)])])
  let checked = @graph_typing.check_mean(
    cursor(mean_profile_body("[\"g\"]", "[1]", "{\"name\":\"exact_equal\"}")),
    [graph],
    limits(),
  ).unwrap()
  guard @graph_typing.mean_output(checked) is @carrier.GraphValue(value) else {
    fail("Graph")
  }
  let node = @carrier.graph_node_at(@carrier.graph_definition(value), 0).unwrap()
  assert_true(
    @contract.type_equal(
      @carrier.field_at(@carrier.graph_element_definition_properties(node), 0).unwrap().contract.unwrap(),
      text,
      100,
    ),
  )
}
