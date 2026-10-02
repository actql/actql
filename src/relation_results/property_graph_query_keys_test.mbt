///|
fn property_query_graph() -> @carrier.Carrier {
  let props = @carrier.rows(
    [
      (
        Unqualified("score"),
        Some(@contract.primitive(NumberType, nullable=true)),
      ),
    ],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [
      @contract.primitive(NumberType, nullable=false),
      @contract.primitive(StringType, nullable=false),
    ],
    props,
    ["Node"],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "E",
      [@contract.primitive(NumberType, nullable=false)],
      props,
      ["Link"],
      max_fields=1,
      max_name_bytes=100,
    ).unwrap(),
    "N",
    "N",
  ).unwrap()
  @carrier.property_graph(
    "sha256:" + "0".repeat(64),
    [node],
    [edge],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
}

///|
fn property_query_body(edges : Bool, fields : String) -> String {
  let operation = if edges { "match_edges" } else { "match_nodes" }
  let definition = if edges { "E" } else { "N" }
  let bindings = if edges {
    "{\"identity\":\"element\",\"source\":\"src\",\"target\":\"dst\"}"
  } else {
    "{\"identity\":\"element\"}"
  }
  "{\"" +
  operation +
  "\":{\"definition\":\"" +
  definition +
  "\",\"bindings\":" +
  bindings +
  ",\"where\":\"true\",\"fields\":" +
  fields +
  "},\"as\":\"out\"}"
}

///|
test "Property Graph MATCH key evidence retains the independent typed identity and checked producer" {
  for edges in [false, true] {
    let graph = property_query_graph()
    let p = @pipeline.check_carriers(
      cursor("[" + property_query_body(edges, "[\"element\",\"score\"]") + "]"),
      [("g", graph)],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let key = @pipeline.candidate_key(p, Step(0)).unwrap()
    assert_eq(@evidence.key_origin(key), GraphQueryResult)
    assert_eq(@evidence.key_field_count(key), 1)
    let field = @evidence.key_field_at(key, 0).unwrap()
    assert_eq(field.name, Unqualified("element"))
    assert_true(field.contract.unwrap().shape is @contract.Json)
    assert_false(field.contract.unwrap().nullable)
    assert_eq(@evidence.key_pending(key), [ValidateKeyProducer])
    guard @evidence.key_graph_query_producer(key) is Some(MatchOperation(op)) else {
      abort("expected the actual checked MATCH producer")
    }
    assert_true(physical_equal(@graph.match_input(op), graph))
    assert_eq(
      @graph.match_property_definition_name(op),
      Some(if edges { "E" } else { "N" }),
    )
    // Semantic Graph identity is not a generic JSON scalar key or authored order.
    for usage in [@evidence.CanonicalOrder, @evidence.ScalarIdentity] {
      assert_true(
        @evidence.select_key(
          cursor("null"),
          @evidence.singleton_key(key),
          usage,
          { max_work: 100, max_name_bytes: 100, },
        ).unwrap().key
        is None,
      )
    }
    let transfer = @evidence.graph_query_keys(MatchOperation(op), {
      max_work: 100,
      max_name_bytes: 100,
    }).unwrap()
    let exact : @evidence.TransferLimits = {
      max_work: transfer.work,
      max_name_bytes: transfer.name_bytes,
    }
    assert_true(@evidence.graph_query_keys(MatchOperation(op), exact) is Ok(_))
    assert_true(
      @evidence.graph_query_keys(MatchOperation(op), {
        ..exact,
        max_work: exact.max_work - 1,
      })
      is Err(_),
    )
    assert_true(
      @evidence.graph_query_keys(MatchOperation(op), {
        ..exact,
        max_name_bytes: exact.max_name_bytes - 1,
      })
      is Err(_),
    )
  }
}

///|
test "MATCH identity survives aliases but disappears when its last projection is dropped" {
  for edges in [false, true] {
    let p = @pipeline.check_carriers(
      cursor(
        "[" +
        property_query_body(edges, "[\"element\",\"score\"]") +
        ",{\"select\":[{\"a\":\"element\"},{\"b\":\"element\"},\"score\"]},{\"drop\":[\"a\"]},{\"drop\":[\"b\"],\"as\":\"rows\"}]",
      ),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let key = @pipeline.candidate_key(p, Step(2)).unwrap()
    assert_eq(@evidence.key_field_count(key), 1)
    assert_eq(@evidence.key_field_at(key, 0).unwrap().name, Unqualified("b"))
    assert_eq(
      @evidence.declared_key_field_at(key, 0).unwrap().name,
      Unqualified("element"),
    )
    assert_true(
      @evidence.key_graph_query_producer(key) is Some(MatchOperation(_)),
    )
    assert_true(@pipeline.candidate_key(p, Step(3)) is None)
  }
}

///|
test "endpoints properties and historical row aliases cannot fabricate an independent edge key" {
  let original = property_query_graph()
  guard original is @carrier.GraphValue(graph) else { abort("Graph") }
  let names = @carrier.graph_row_names(
    Unqualified("score"),
    Unqualified("src"),
    Unqualified("dst"),
    Some(Unqualified("score")),
    max_name_bytes=100,
  ).unwrap()
  for graph in [original, @carrier.with_graph_names(graph, Some(names))] {
    for fields in ["[\"src\",\"dst\"]", "[\"src\",\"dst\",\"score\"]"] {
      let p = @pipeline.check_carriers(
        cursor("[" + property_query_body(true, fields) + "]"),
        [("g", graph)],
        None,
        None,
        ranking_limits(),
      ).unwrap()
      assert_true(@pipeline.candidate_key(p, Step(0)) is None)
    }
  }
}

///|
test "current MATCH publishes structured identity through inherited order rather than scalar completion" {
  for edges in [false, true] {
    let p = @pipeline.check_carriers(
      cursor(
        "[" +
        property_query_body(edges, "[\"element\",\"score\"]") +
        ",{\"take\":1,\"as\":\"rows\"}]",
      ),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let results = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"rows\",\"fields\":[\"element\",\"score\"]}}"),
      limits(),
    ).unwrap()
    let order = resolve(results)
    assert_eq(@relation_results.publication_strategy(order), Inherited)
    assert_eq(
      @pipeline.order_origin(
        @relation_results.publication_inherited_order(order).unwrap(),
      ),
      Step(0),
    )
    assert_eq(@relation_results.publication_term_count(order), 0)
    // Copying the output shape cannot manufacture producer order or key evidence.
    let plain = @pipeline.check_carriers(
      cursor("[]"),
      [("rows", @pipeline.output_carrier(p).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(plain, Input(0)) is None)
    assert_true(@pipeline.candidate_key(plain, Input(0)) is None)
  }
}
