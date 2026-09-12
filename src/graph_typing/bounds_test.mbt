///|
test "graph bounds retain zero thresholds and typed nullable identities" {
  let id = @contract.decimal_contract(38, 9, nullable=false).unwrap()
  for name in ["max_nodes", "max_edges", "max_degree"] {
    let checked = @graph_typing.check(
      GraphBounds,
      cursor("{\"" + name + "\":0}"),
      graph(id),
      None,
      limits(),
    ).unwrap()
    let rows = @carrier.relation_rows(@graph_typing.output(checked)).unwrap()
    let schema = @carrier.complete_schema(rows).unwrap()
    assert_eq(@row.field_count(schema), 4)
    assert_true(
      @contract.type_equal(
        @row.lookup(schema, Unqualified("node_id")).unwrap(),
        @contract.with_nullability(id, true),
        10,
      ),
    )
    for field in ["actual", "max"] {
      let ty = @row.lookup(schema, Unqualified(field)).unwrap()
      assert_true(ty.shape is Number && !ty.nullable)
    }
    let pending = indexed_obligation_copy(
      @graph_typing.pending_validations(checked),
      @graph_typing.pending_validation_count(checked),
      i => @graph_typing.pending_validation_at(checked, i),
      (a, b) => a == b,
    )
    assert_true(pending.contains(BoundsReportOrder))
    assert_false(pending.contains(EnforceOutputGuard))
    match @graph_typing.options(checked) {
      BoundsOptions(max_nodes~, max_edges~, max_degree~) => {
        let values = [max_nodes, max_edges, max_degree]
        assert_eq(values.filter(v => v is Some(Literal(0L))).length(), 1)
        assert_eq(values.filter(v => v is None).length(), 2)
      }
      _ => fail("bounds lost")
    }
  }
}

///|
test "graph bounds reject empty malformed and out-of-range threshold bodies" {
  let input = graph(@contract.primitive(NumberType, nullable=false))
  for
    text in [
      "{}", "true", "{\"max_nodes\":null}", "{\"max_nodes\":-1}", "{\"max_nodes\":1.5}",
      "{\"max_nodes\":9007199254740992}", "{\"max_nodes\":\"1\"}", "{\"max_nodes\":1,\"max_output_rows\":1}",
    ] {
    assert_true(
      @graph_typing.check(GraphBounds, cursor(text), input, None, limits())
      is Err(_),
    )
  }
  assert_true(
    @graph_typing.check(
      GraphBounds,
      cursor("{\"max_degree\":9007199254740991}"),
      input,
      None,
      limits(),
    )
    is Ok(_),
  )
  let issue = @graph_typing.check(
    GraphBounds,
    cursor("{\"max_edges\":-1}"),
    input,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, InvalidCount)
  assert_eq(issue.path, [@source.Key("max_edges")])
}

///|
test "bound parameters retain nonnegative validation and opaque ID information" {
  let ds = @parameter.read_declarations(
    Some(cursor("{\"limit\":{\"type\":\"number\",\"default\":-1}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let source = cursor("{\"max_nodes\":{\"$param\":\"limit\"},\"max_degree\":0}")
  let input = @carrier.unknown_carrier(GraphKind)
  let checked = @graph_typing.check(
    GraphBounds,
    source,
    input,
    Some(ds),
    limits(),
  ).unwrap()
  assert_true(
    indexed_obligation_copy(
      @graph_typing.pending_validations(checked),
      @graph_typing.pending_validation_count(checked),
      i => @graph_typing.pending_validation_at(checked, i),
      (a, b) => a == b,
    ).contains(BindNonnegativeCount("limit")),
  )
  assert_false(
    indexed_obligation_copy(
      @graph_typing.pending_validations(checked),
      @graph_typing.pending_validation_count(checked),
      i => @graph_typing.pending_validation_at(checked, i),
      (a, b) => a == b,
    ).contains(BindPositiveCount("limit")),
  )
  let rows = @carrier.relation_rows(@graph_typing.output(checked)).unwrap()
  assert_eq(@carrier.field_set(rows), Closed)
  guard @carrier.lookup(rows, Unqualified("node_id")) is Present(f) else {
    fail("missing ID")
  }
  assert_true(f.contract is None)
  let used = @graph_typing.usage(checked)
  let exact : @graph_typing.Limits = {
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_depth: 2,
  }
  assert_true(
    @graph_typing.check(GraphBounds, source, input, Some(ds), exact) is Ok(_),
  )
  assert_eq(
    @graph_typing.check(GraphBounds, source, input, Some(ds), {
      ..exact,
      max_work: used.work - 1,
    }).unwrap_err().kind,
    BudgetExceeded,
  )
}
