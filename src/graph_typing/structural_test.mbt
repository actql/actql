///|
test "structural indexed obligations keep first strategy family order" {
  let number = @contract.primitive(NumberType, nullable=false)
  let items = @contract.array_contract(
    number,
    nullable=false,
    max_items=Some(2L),
  ).unwrap()
  for first_set in [false, true] {
    let properties = @carrier.rows(
      [
        (Unqualified("a"), Some(if first_set { items } else { number })),
        (Unqualified("b"), Some(if first_set { number } else { items })),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=10,
    ).unwrap()
    let empty = @carrier.rows(
      [],
      field_set=Closed,
      max_fields=0,
      max_name_bytes=0,
    ).unwrap()
    let graph = @carrier.graph(
      number,
      properties,
      empty,
      labels=Some([]),
      max_labels=0,
      max_label_bytes=0,
    ).unwrap()
    let a = if first_set { "set_union" } else { "number_sum" }
    let b = if first_set { "number_sum" } else { "set_union" }
    let c = @graph_typing.check_structural(
      Union,
      cursor(
        "{\"with\":\"r\",\"merge\":{\"node_properties\":{\"a\":\"" +
        a +
        "\",\"b\":\"" +
        b +
        "\"}}}",
      ),
      graph,
      graph,
      limits(),
    ).unwrap()
    assert_eq(@graph_typing.structural_pending_count(c), 10)
    let expected = if first_set {
      [
        @graph_typing.ValidateCanonicalSetOperations,
        @graph_typing.ValidateFiniteNumericResults,
      ]
    } else {
      [
        @graph_typing.ValidateFiniteNumericResults,
        @graph_typing.ValidateCanonicalSetOperations,
      ]
    }
    assert_eq(@graph_typing.structural_pending_at(c, 8), Some(expected[0]))
    assert_eq(@graph_typing.structural_pending_at(c, 9), Some(expected[1]))
    assert_true(@graph_typing.structural_pending_at(c, 10) is None)
  }
}

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
      indexed_obligation_copy(
        @graph_typing.structural_pending(c),
        @graph_typing.structural_pending_count(c),
        i => @graph_typing.structural_pending_at(c, i),
        (a, b) => a == b,
      ).contains(ValidateCanonicalSetOperations),
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
      indexed_obligation_copy(
        @graph_typing.structural_pending(c),
        @graph_typing.structural_pending_count(c),
        i => @graph_typing.structural_pending_at(c, i),
        (a, b) => a == b,
      ).contains(ApplyEveryAuthoredStrategy),
    )
    assert_true(
      indexed_obligation_copy(
        @graph_typing.structural_pending(c),
        @graph_typing.structural_pending_count(c),
        i => @graph_typing.structural_pending_at(c, i),
        (a, b) => a == b,
      ).contains(CloseSubtractionEndpoints),
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
    !indexed_obligation_copy(
      @graph_typing.structural_pending(empty),
      @graph_typing.structural_pending_count(empty),
      i => @graph_typing.structural_pending_at(empty, i),
      (a, b) => a == b,
    ).contains(ApplyEveryAuthoredStrategy),
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
