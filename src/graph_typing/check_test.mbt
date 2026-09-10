///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 1000,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 1000,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
fn limits() -> @graph_typing.Limits {
  {
    max_work: 10000,
    max_nodes: 10000,
    max_depth: 1000,
    max_text_bytes: 100000,
  }
}

///|
fn graph(id : @contract.Contract) -> @carrier.Carrier {
  @carrier.graph(
    id,
    @carrier.unknown_rows(),
    @carrier.unknown_rows(),
    labels=Some(["owns"]),
    max_labels=1,
    max_label_bytes=4,
  ).unwrap()
}

///|
test "degree and components retain semantic identity types despite unknown properties" {
  for
    id in [
      @contract.primitive(NumberType, nullable=false),
      @contract.primitive(StringType, nullable=false),
      @contract.decimal_contract(38, 9, nullable=false).unwrap(),
      @contract.read_author(
        cursor(
          "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"Customer\"}",
        ),
        { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
      ).unwrap(),
    ] {
    for direction in ["in", "out", "both"] {
      let checked = @graph_typing.check(
        Degree,
        cursor("{\"direction\":\"" + direction + "\"}"),
        graph(id),
        None,
        limits(),
      ).unwrap()
      let schema = @carrier.complete_schema(
        @carrier.relation_rows(@graph_typing.output(checked)).unwrap(),
      ).unwrap()
      assert_eq(@row.field_count(schema), 2)
      assert_true(
        @contract.type_equal(
          @row.lookup(schema, Unqualified("node")).unwrap(),
          id,
          10,
        ),
      )
      let n = @row.lookup(schema, Unqualified("degree")).unwrap()
      assert_true(n.shape is Number && !n.nullable)
      let pending = @graph_typing.pending_validations(checked)
      assert_eq(pending.length(), 3)
      pending.clear()
      assert_eq(@graph_typing.pending_validations(checked).length(), 3)
    }
    for kind in ["weak", "strong"] {
      let checked = @graph_typing.check(
        Components,
        cursor("{\"kind\":\"" + kind + "\"}"),
        graph(id),
        None,
        limits(),
      ).unwrap()
      let schema = @carrier.complete_schema(
        @carrier.relation_rows(@graph_typing.output(checked)).unwrap(),
      ).unwrap()
      assert_eq(@row.field_count(schema), 3)
      for field in ["node_id", "component_id"] {
        assert_true(
          @contract.type_equal(
            @row.lookup(schema, Unqualified(field)).unwrap(),
            id,
            10,
          ),
        )
      }
      assert_true(
        @graph_typing.pending_validations(checked).contains(
          ComponentIdentityOrder,
        ),
      )
      assert_true(
        @graph_typing.options(checked)
        is ComponentOptions(_, max_output_rows=None),
      )
    }
  }
}

///|
test "normalization preserves graph knowledge without claiming data normalization" {
  let checked = @graph_typing.check(
    NormalizeGraph,
    cursor("true"),
    graph(@contract.primitive(NumberType, nullable=false)),
    None,
    limits(),
  ).unwrap()
  assert_eq(@graph_typing.operation(checked), NormalizeGraph)
  assert_true(@graph_typing.options(checked) is Normalize)
  assert_true(@decode.boolean(@graph_typing.source(checked)).unwrap())
  assert_eq(@carrier.kind(@graph_typing.input(checked)), GraphKind)
  guard @graph_typing.output(checked) is GraphValue(g) else {
    fail("expected graph")
  }
  assert_eq(@carrier.graph_labels(g), Some(["owns"]))
  assert_true(@carrier.graph_identity(g).shape is Number)
  assert_eq(@carrier.field_set(@carrier.graph_node_properties(g)), Open)
  for
    (op, body) in [
      (@graph_typing.NormalizeGraph, "true"),
      (Degree, "{\"direction\":\"in\"}"),
      (Components, "{\"kind\":\"weak\"}"),
    ] {
    let checked = @graph_typing.check(
      op,
      cursor(body),
      @carrier.unknown_carrier(GraphKind),
      None,
      limits(),
    ).unwrap()
    if op == NormalizeGraph {
      assert_true(@graph_typing.output(checked) is Opaque(GraphKind))
    } else {
      let rows = @carrier.relation_rows(@graph_typing.output(checked)).unwrap()
      assert_eq(@carrier.field_set(rows), Closed)
      assert_true(@carrier.complete_schema(rows) is None)
      let field = if op == Degree { "node" } else { "node_id" }
      guard @carrier.lookup(rows, Unqualified(field)) is Present(f) else {
        fail("missing role")
      }
      assert_true(f.contract is None)
    }
  }
}

///|
test "graph bodies are closed and reject wrong carriers and invalid counts" {
  let input = graph(@contract.primitive(NumberType, nullable=false))
  for
    (op, body) in [
      (@graph_typing.NormalizeGraph, "false"),
      (NormalizeGraph, "{}"),
      (Degree, "{}"),
      (Degree, "{\"direction\":\"IN\"}"),
      (Degree, "{\"direction\":\"in\",\"field\":\"id\"}"),
      (Components, "{\"kind\":\"other\"}"),
      (Components, "{\"kind\":\"weak\",\"max_nodes\":1}"),
      (Components, "{\"kind\":\"weak\",\"max_output_rows\":0}"),
      (Components, "{\"kind\":\"weak\",\"max_output_rows\":1.5}"),
      (Components, "{\"kind\":\"weak\",\"max_output_rows\":9007199254740992}"),
    ] {
    assert_true(
      @graph_typing.check(op, cursor(body), input, None, limits()) is Err(_),
    )
  }
  for k in [@carrier.RelationKind, EventsKind, VectorsKind] {
    assert_eq(
      @graph_typing.check(
        NormalizeGraph,
        cursor("true"),
        @carrier.unknown_carrier(k),
        None,
        limits(),
      ).unwrap_err().kind,
      WrongCarrier(k),
    )
  }
  let issue = @graph_typing.check(
    Components,
    cursor("{\"kind\":\"weak\",\"max_output_rows\":0}"),
    input,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, InvalidCount)
  assert_eq(issue.path, [@source.Key("max_output_rows")])
}

///|
test "component guards preserve parameter binding obligations and exact budgets" {
  let ds = @parameter.read_declarations(
    Some(
      cursor(
        "{\"cap\":{\"type\":\"number\",\"default\":-1},\"bad\":{\"type\":\"number\",\"nullable\":true}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let input = graph(@contract.primitive(NumberType, nullable=false))
  let body = cursor(
    "{\"kind\":\"strong\",\"max_output_rows\":{\"$param\":\"cap\"}}",
  )
  let checked = @graph_typing.check(Components, body, input, Some(ds), limits()).unwrap()
  assert_true(
    @graph_typing.options(checked)
    is ComponentOptions(Strong, max_output_rows=Some(Parameter("cap"))),
  )
  assert_true(
    @graph_typing.pending_validations(checked).contains(
      BindPositiveCount("cap"),
    ),
  )
  assert_true(
    @graph_typing.pending_validations(checked).contains(EnforceOutputGuard),
  )
  assert_eq(
    @graph_typing.check(Components, body, input, None, limits()).unwrap_err().kind,
    UnknownParameter("cap"),
  )
  assert_eq(
    @graph_typing.check(
      Components,
      cursor("{\"kind\":\"weak\",\"max_output_rows\":{\"$param\":\"bad\"}}"),
      input,
      Some(ds),
      limits(),
    ).unwrap_err().kind,
    IncompatibleParameter("bad"),
  )
  let used = @graph_typing.usage(checked)
  let exact : @graph_typing.Limits = {
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
    max_depth: 2,
  }
  assert_true(
    @graph_typing.check(Components, body, input, Some(ds), exact) is Ok(_),
  )
  let caps : Array[@graph_typing.Limits] = [
    { ..exact, max_work: used.work - 1, },
    { ..exact, max_nodes: used.nodes - 1, },
    { ..exact, max_text_bytes: used.text_bytes - 1, },
    { ..exact, max_depth: 1, },
  ]
  for cap in caps {
    assert_eq(
      @graph_typing.check(Components, body, input, Some(ds), cap).unwrap_err().kind,
      BudgetExceeded,
    )
  }
}
