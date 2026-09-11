///|
test "long union lists retain all ordered folds under a shared budget" {
  let number = @contract.primitive(NumberType, nullable=false)
  let g = complete_graph(number, number, "g")
  let operands = []
  let refs = StringBuilder()
  for i in 0..<128 {
    if i > 0 {
      refs.write_string(",")
    }
    refs.write_string("\"g\"")
    operands.push(g)
  }
  let source = cursor(
    "{\"with\":[" +
    refs.to_string() +
    "],\"merge\":{\"node_properties\":{\"value\":\"number_mean\"}}}",
  )
  let c = @graph_typing.check_union(source, g, operands, limits()).unwrap()
  assert_eq(@graph_typing.union_count(c), 128)
  for i in 0..<128 {
    let fold = @graph_typing.union_fold_at(c, i).unwrap()
    assert_eq(@graph_typing.structural_with_name(fold), "g")
    assert_true(
      @graph_typing.structural_pending(fold).contains(
        ValidateFiniteNumericResults,
      ),
    )
  }
  let u = @graph_typing.union_usage(c)
  assert_true(
    @graph_typing.check_union(source, g, operands, {
      ..limits(),
      max_work: u.work - 1,
    })
    is Err(_),
  )
}

///|
test "union list retains left-fold property extents and repeated source references" {
  let number = @contract.primitive(NumberType, nullable=false)
  let a = complete_graph(
    number,
    @contract.array_contract(number, nullable=false, max_items=Some(3L)).unwrap(),
    "a",
  )
  let z = complete_graph(
    number,
    @contract.array_contract(number, nullable=true, max_items=Some(5L)).unwrap(),
    "z",
  )
  let source = cursor(
    "{\"with\":[\"z\",\"a\"],\"merge\":{\"node_properties\":{\"value\":\"set_union\"}}}",
  )
  let operands = [z, a]
  let c = @graph_typing.check_union(source, a, operands, limits()).unwrap()
  operands.clear()
  assert_true(physical_equal(@graph_typing.union_source(c), source))
  assert_true(physical_equal(@graph_typing.union_input(c), a))
  assert_true(physical_equal(@graph_typing.union_operand_at(c, 0).unwrap(), z))
  assert_true(physical_equal(@graph_typing.union_operand_at(c, 1).unwrap(), a))
  assert_eq(@graph_typing.union_count(c), 2)
  for (i, bound, name) in [(0, 8L, "z"), (1, 11L, "a")] {
    let fold = @graph_typing.union_fold_at(c, i).unwrap()
    assert_eq(@graph_typing.structural_with_name(fold), name)
    assert_eq(@graph_typing.structural_operation(fold), Union)
    assert_true(
      @graph_typing.structural_pending(fold).contains(
        ApplyEveryAuthoredStrategy,
      ),
    )
    guard @graph_typing.structural_output(fold) is @carrier.GraphValue(g) else {
      abort("Graph")
    }
    guard @carrier.lookup(
        @carrier.graph_node_properties(g),
        Unqualified("value"),
      )
      is Present({ contract: Some(t), .. }) else {
      abort("property")
    }
    assert_true(t.shape is @contract.Array(_, max_items=Some(n)) && n == bound)
    assert_true(t.nullable)
  }
  assert_true(
    physical_equal(
      @graph_typing.union_output(c),
      @graph_typing.structural_output(
        @graph_typing.union_fold_at(c, 1).unwrap(),
      ),
    ),
  )
  let u = @graph_typing.union_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@graph_typing.check_union(source, a, [z, a], exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(@graph_typing.check_union(source, a, [z, a], cap) is Err(_))
  }
  assert_true(@graph_typing.union_fold_at(c, 2) is None)
  assert_true(@graph_typing.union_operand_at(c, -1) is None)
}

///|
test "union rejects malformed lists arity and late Carrier errors without partial results" {
  let number = @contract.primitive(NumberType, nullable=false)
  let g = complete_graph(number, number, "a")
  for
    body in [
      "{\"with\":[]}", "{\"with\":[\"g\",[]]}", "{\"with\":[\"g\",\"\"]}", "{\"with\":[\"g\"],\"extra\":1}",
    ] {
    assert_true(
      @graph_typing.check_union(cursor(body), g, [g, g], limits()) is Err(_),
    )
  }
  assert_true(
    @graph_typing.check_union(cursor("{\"with\":[\"g\"]}"), g, [], limits())
    is Err(_),
  )
  for body in ["{\"with\":\"g\"}", "{\"with\":[\"g\"]}"] {
    let c = @graph_typing.check_union(cursor(body), g, [g], limits()).unwrap()
    assert_eq(@graph_typing.union_count(c), 1)
  }
  let e = @graph_typing.check_union(
    cursor("{\"with\":[\"g\",\"wrong\"]}"),
    g,
    [g, @carrier.unknown_carrier(RelationKind)],
    limits(),
  ).unwrap_err()
  assert_eq(e.kind, WrongCarrier(RelationKind))
  assert_eq(e.path, [@source.Key("with"), @source.Index(1)])
}
