///|
test "mean checks every graph and produces nullable numeric means" {
  let source = cursor(
    "{\"with\":[\"a\",\"b\"],\"weights\":[1,0],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{\"cost\":{\"mean\":{\"missing\":\"zero\",\"nulls\":\"fail\"}}}}}",
  )
  let g = weighted_graph(false)
  let inputs = [g, weighted_graph(true)]
  let c = @graph_typing.check_mean(source, inputs, limits()).unwrap()
  guard @graph_typing.mean_output(c) is @carrier.GraphValue(output) else {
    abort("expected graph")
  }
  guard @carrier.lookup(
      @carrier.graph_edge_properties(output),
      Unqualified("cost"),
    )
    is Present({ contract: Some(cost), .. }) else {
    abort("expected cost")
  }
  assert_true(cost.nullable)
  assert_true(cost.shape is @contract.Number)
  assert_true(
    indexed_obligation_copy(
      @graph_typing.mean_pending(c),
      @graph_typing.mean_pending_count(c),
      i => @graph_typing.mean_pending_at(c, i),
      (a, b) => a == b,
    ).contains(RoundExactWeightedMeansOnce),
  )
  inputs[0] = @carrier.unknown_carrier(GraphKind)
  assert_true(@graph_typing.mean_output(c) is @carrier.GraphValue(_))
  assert_true(
    @graph_typing.check_mean(
      source,
      [g, @carrier.unknown_carrier(GraphKind)],
      limits(),
    )
    is Err({ kind: IncompleteGraph, .. }),
  )
  assert_true(
    @graph_typing.check_mean(
      source,
      [g, @carrier.relation(@carrier.unknown_rows())],
      limits(),
    )
    is Err({ kind: WrongCarrier(RelationKind), .. }),
  )
  let u = @graph_typing.mean_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @graph_typing.check_mean(source, [g, weighted_graph(true)], exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_mean(source, [g, weighted_graph(true)], cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "mean requires complete strategy coverage and compatible zero-weight contracts" {
  let g = weighted_graph(false)
  for
    props in [
      "{}", "{\"other\":\"exact_equal\"}", "{\"cost\":\"exact_equal\",\"other\":\"exact_equal\"}",
    ] {
    let text = "{\"with\":[\"g\"],\"weights\":[1],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":" +
      props +
      "}}"
    assert_true(@graph_typing.check_mean(cursor(text), [g], limits()) is Err(_))
  }
  let source = cursor(
    "{\"with\":[\"g\",\"z\"],\"weights\":[1,0],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{\"cost\":\"exact_equal\"}}}",
  )
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let wrong = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    @carrier.rows(
      [
        (
          Unqualified("cost"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=4,
    ).unwrap(),
    labels=None,
    max_labels=0,
    max_label_bytes=0,
  ).unwrap()
  assert_true(
    @graph_typing.check_mean(source, [g, wrong], limits())
    is Err({ kind: ContractMismatch(_), .. }),
  )
  let c = @graph_typing.check_mean(source, [g, g], limits()).unwrap()
  guard @graph_typing.mean_output(c) is @carrier.GraphValue(output) else {
    abort("expected graph")
  }
  guard @carrier.lookup(
      @carrier.graph_edge_properties(output),
      Unqualified("cost"),
    )
    is Present({ contract: Some(cost), .. }) else {
    abort("expected cost")
  }
  assert_false(cost.nullable)
}

///|
test "mean options preserve sample occurrences without overflowing total weight" {
  let source = cursor(
    "{\"with\":[\"g\",\"g\",\"z\"],\"weights\":[1.7976931348623157e308,1.7976931348623157e308,0],\"support\":{\"nodes\":5e-324,\"edges\":1},\"properties\":{\"nodes\":{\"v\":{\"mean\":{\"missing\":\"zero\",\"nulls\":\"fail\"}}},\"edges\":{\"label\":\"exact_equal\"}}}",
  )
  let c = @graph_typing.check_mean_options(source, limits()).unwrap()
  assert_eq(@graph_typing.mean_input_names(c), ["g", "g", "z"])
  assert_eq(@graph_typing.mean_weights(c).length(), 3)
  assert_eq(@graph_typing.mean_support(c, Nodes), 5.0e-324)
  assert_eq(@graph_typing.mean_support(c, Edges), 1.0)
  assert_eq(
    @graph_typing.mean_properties(c, Nodes)[0].strategy,
    WeightedMean(ZeroMissing, FailNull),
  )
  let names = @graph_typing.mean_input_names(c)
  names[0] = "changed"
  assert_eq(@graph_typing.mean_input_names(c)[0], "g")
  let weights = @graph_typing.mean_weights(c)
  weights[0] = 0.0
  assert_true(@graph_typing.mean_weights(c)[0] > 0.0)
  let used = @graph_typing.mean_options_usage(c)
  let exact = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(@graph_typing.check_mean_options(source, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_mean_options(source, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "mean options reject missing policies invalid weights and invalid support" {
  for weights in ["[]", "[0]", "[-1]", "[1,2]", "[{\"$param\":\"w\"}]"] {
    let text = "{\"with\":[\"g\"],\"weights\":" +
      weights +
      ",\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}"
    assert_true(
      @graph_typing.check_mean_options(cursor(text), limits()) is Err(_),
    )
  }
  for support in ["0", "-1", "1.00001", "null"] {
    let text = "{\"with\":[\"g\"],\"weights\":[1],\"support\":{\"nodes\":" +
      support +
      ",\"edges\":1},\"properties\":{\"nodes\":{},\"edges\":{}}}"
    assert_true(
      @graph_typing.check_mean_options(cursor(text), limits()) is Err(_),
    )
  }
  for
    strategy in [
      "\"number_mean\"", "{\"mean\":{\"missing\":\"exclude\"}}", "{\"mean\":{\"missing\":\"fail\",\"nulls\":\"zero\"}}",
      "{\"mean\":{\"missing\":\"zero\",\"nulls\":\"zero\",\"extra\":1}}",
    ] {
    let text = "{\"with\":[\"g\"],\"weights\":[1],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{\"v\":" +
      strategy +
      "},\"edges\":{}}}"
    assert_true(
      @graph_typing.check_mean_options(cursor(text), limits()) is Err(_),
    )
  }
}
