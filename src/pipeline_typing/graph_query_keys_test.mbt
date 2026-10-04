///|
fn query_property_graph() -> @carrier.Carrier {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @carrier.property_node_definition(
    "N",
    [@contract.primitive(NumberType, nullable=false)],
    empty,
    ["Node"],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let edge = @carrier.property_edge_definition(
    @carrier.property_node_definition(
      "E",
      [@contract.primitive(NumberType, nullable=false)],
      empty,
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
fn query_match_body(edges : Bool, fields : String) -> String {
  let definition = if edges { "E" } else { "N" }
  let operation = if edges { "match_edges" } else { "match_nodes" }
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
  "}}"
}

///|
test "current Graph matching requires the independent element identity not endpoint tuple" {
  for
    (edges, fields, expected) in [
      (false, "[\"element\"]", 1),
      (true, "[\"element\",\"src\",\"dst\"]", 1),
      (true, "[\"src\",\"dst\"]", 0),
    ] {
    let p = @pipeline_typing.check_carriers(
      cursor("[" + query_match_body(edges, fields) + "]"),
      [("g", query_property_graph())],
      None,
      None,
      limits(),
    ).unwrap()
    let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
    assert_eq(@evidence.key_witness_count(keys), expected)
    if expected == 1 {
      let key = @evidence.key_witness_at(keys, 0).unwrap()
      assert_eq(@evidence.key_field_count(key), 1)
      assert_eq(
        @evidence.key_field_at(key, 0).unwrap().name,
        Unqualified("element"),
      )
      assert_false(
        @evidence.key_field_at(key, 0).unwrap().contract.unwrap().nullable,
      )
    }
  }
}

///|
test "current Graph query aliases retain actual checked producer and exact transfer budgets" {
  for edges in [false, true] {
    let graph = query_property_graph()
    let source = cursor(
      "[" +
      query_match_body(edges, "[\"element\"]") +
      ",{\"select\":[{\"a\":\"element\"},{\"b\":\"element\"}]},{\"drop\":[\"a\"]}]",
    )
    let inputs = [("g", graph)]
    let p = @pipeline_typing.check_carriers(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let key = @pipeline_typing.candidate_key(p, Step(0)).unwrap()
    assert_eq(@evidence.key_origin(key), GraphQueryResult)
    let output = @pipeline_typing.candidate_key(p, Step(2)).unwrap()
    assert_eq(@evidence.key_field_count(output), 1)
    assert_eq(@evidence.key_field_at(output, 0).unwrap().name, Unqualified("b"))
    assert_eq(
      @evidence.declared_key_field_at(output, 0).unwrap().name,
      Unqualified("element"),
    )
    assert_eq(@evidence.key_pending(output), [ValidateKeyProducer])
    guard @evidence.key_graph_query_producer(output) is Some(MatchOperation(op)) else {
      abort("checked MATCH producer")
    }
    assert_true(physical_equal(@graph.match_input(op), graph))
    let transfer = @evidence.graph_query_keys(MatchOperation(op), {
      max_work: 100,
      max_name_bytes: 1000,
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
    let used = @pipeline_typing.usage(p)
    let cap = {
      ..limits(),
      max_work: used.work,
      max_nodes: used.nodes,
      max_tokens: used.tokens,
      max_text_bytes: used.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, cap) is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, inputs, None, None, {
        ..cap,
        max_work: cap.max_work - 1,
      })
      is Err(_),
    )
  }
}

///|
test "current identity projection loss and TRAIL enumeration do not fabricate Relation keys" {
  let graph = query_property_graph()
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      query_match_body(true, "[\"element\",\"src\",\"dst\"]") +
      ",{\"drop\":[\"element\"]}]",
    ),
    [("g", graph)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.candidate_key(p, Step(1)) is None)
  let identity = "{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
  let trail = @pipeline_typing.check_carriers(
    cursor(
      "[{\"traverse\":{\"start\":{\"ids\":[" +
      identity +
      "]},\"hops\":[{\"direction\":\"out\"}],\"path_mode\":\"trail\",\"emit\":\"paths\"}}]",
    ),
    [("g", graph)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.candidate_key(trail, Step(0)) is None)
  for
    operation in [
      "\"shortest_path\":{\"source\":1,\"target\":2,\"direction\":\"out\",\"max_hops\":3}",
    ] {
    let issue = @pipeline_typing.check_carriers(
      cursor("[{" + operation + "}]"),
      [("g", graph)],
      None,
      None,
      limits(),
    ).unwrap_err()
    assert_true(
      issue.kind is Graph(@graph.UnsupportedGraphOperation) ||
      issue.kind
      is GraphMatch(@graph.Structure(@graph.UnsupportedGraphOperation)),
    )
  }
  for kind in ["weak", "strong"] {
    guard graph is @carrier.GraphValue(graph_schema) else {
      abort("typed Graph")
    }
    let checked = @pipeline_typing.check_carriers(
      cursor("[{\"from\":\"g\",\"components\":{\"kind\":\"" + kind + "\"}}]"),
      [("g", graph)],
      None,
      None,
      limits(),
    ).unwrap()
    let schema = @pipeline_typing.output_schema(checked).unwrap()
    assert_eq(@schema.field_count(schema), 3)
    let identity = @carrier.graph_identity(graph_schema)
    for name in ["node_id", "component_id"] {
      assert_true(
        @contract.type_equal(
          @schema.lookup(schema, Unqualified(name)).unwrap(),
          identity,
          100,
        ),
      )
    }
    assert_true(
      @contract.type_equal(
        @schema.lookup(schema, Unqualified("component_size")).unwrap(),
        @contract.primitive(NumberType, nullable=false),
        100,
      ),
    )
    let keys = @pipeline_typing.candidate_keys(checked, Step(0)).unwrap()
    assert_eq(@evidence.key_witness_count(keys), 1)
    let key = @evidence.key_witness_at(keys, 0).unwrap()
    assert_eq(@evidence.key_field_count(key), 1)
    assert_eq(
      @evidence.key_field_at(key, 0).unwrap().name,
      Unqualified("node_id"),
    )
    assert_eq(@evidence.key_origin(key), GraphQueryResult)
  }
  for
    operation in [
      "\"degree\":{\"direction\":\"both\"}", "\"graph_bounds\":{\"max_nodes\":0,\"max_degree\":0}",
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor("[{" + operation + "}]"),
        [("g", graph)],
        None,
        None,
        limits(),
      )
      is Ok(_),
    )
  }
}
