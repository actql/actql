///|
test "structural set union widens array bounds and keeps shared budgets" {
  let number = @contract.primitive(NumberType, nullable=false)
  let a = complete_graph(
    number,
    @contract.array_contract(number, nullable=true, max_items=Some(3L)).unwrap(),
    "a",
  )
  let b = complete_graph(
    number,
    @contract.array_contract(number, nullable=false, max_items=Some(5L)).unwrap(),
    "b",
  )
  let source = cursor(
    "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"value\":\"set_union\"}}}",
  )
  for operation in [@graph_typing.Union, @graph_typing.Subtract] {
    let c = @graph_typing.check_structural(operation, source, a, b, limits()).unwrap()
    guard @graph_typing.structural_output(c) is @carrier.GraphValue(g) else {
      abort("expected graph")
    }
    guard @carrier.lookup(
        @carrier.graph_node_properties(g),
        Unqualified("value"),
      )
      is Present({ contract: Some(t), .. }) else {
      abort("expected property")
    }
    assert_true(t.nullable)
    assert_true(t.shape is @contract.Array(_, max_items=Some(8L)))
    assert_eq(@carrier.graph_labels(g), Some(["a", "b"]))
    assert_true(
      @graph_typing.structural_pending(c).contains(
        ValidateCanonicalSetOperations,
      ),
    )
    let strategies = @graph_typing.structural_strategies(c, Left)
    assert_eq(strategies.length(), 1)
    strategies.clear()
    assert_eq(@graph_typing.structural_strategies(c, Left).length(), 1)
    let u = @graph_typing.structural_usage(c)
    let exact = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @graph_typing.check_structural(operation, source, a, b, exact) is Ok(_),
    )
    for
      cap in [
        { ..exact, max_work: u.work - 1, },
        { ..exact, max_nodes: u.nodes - 1, },
        { ..exact, max_text_bytes: u.text_bytes - 1, },
      ] {
      assert_true(
        @graph_typing.check_structural(operation, source, a, b, cap) is Err(_),
      )
    }
  }
}

///|
test "structural strategies validate properties and preserve subtraction obligations" {
  let number = @contract.primitive(NumberType, nullable=false)
  let g = complete_graph(number, number, "r")
  for
    strategy in [
      "exact_equal", "number_sum", "number_mean", "number_min", "number_max",
    ] {
    let source = cursor(
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"value\":\"" +
      strategy +
      "\"}}}",
    )
    let c = @graph_typing.check_structural(Subtract, source, g, g, limits()).unwrap()
    assert_true(
      @graph_typing.structural_pending(c).contains(ApplyEveryAuthoredStrategy),
    )
    assert_true(
      @graph_typing.structural_pending(c).contains(CloseSubtractionEndpoints),
    )
    assert_true(
      @graph_typing.check_structural(Graft, source, g, g, limits()) is Err(_),
    )
  }
  for
    body in [
      "{\"with\":\"peer\",\"merge\":null}", "{\"with\":\"peer\",\"merge\":{\"extra\":{}}}",
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"missing\":\"exact_equal\"}}}",
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"value\":\"set_union\"}}}",
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"value\":\"last_write\"}}}",
    ] {
    assert_true(
      @graph_typing.check_structural(Union, cursor(body), g, g, limits())
      is Err(_),
    )
  }
  let empty = @graph_typing.check_structural(
    Subtract,
    cursor("{\"with\":\"peer\",\"merge\":{\"node_properties\":{}}}"),
    g,
    g,
    limits(),
  ).unwrap()
  assert_true(
    !@graph_typing.structural_pending(empty).contains(
      ApplyEveryAuthoredStrategy,
    ),
  )
  assert_true(
    @graph_typing.check_structural(
      Graft,
      cursor("{\"with\":\"peer\"}"),
      g,
      g,
      limits(),
    )
    is Ok(_),
  )
}
