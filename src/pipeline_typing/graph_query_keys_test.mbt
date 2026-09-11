///|
test "Graph matching requires all edge identity components and reach retains its semantic alias" {
  let empty = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("node"),
    Unqualified("source"),
    Unqualified("target"),
    Some(Unqualified("label")),
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    empty,
    empty,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
    label_contract=Some(@contract.primitive(StringType, nullable=true)),
  ).unwrap()
  for
    (fields, expected) in [
      ("[\"source\",\"target\",\"label\"]", 1),
      ("[\"source\",\"target\"]", 0),
    ] {
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(
        cursor(
          "[{\"match_edges\":{\"where\":\"true\",\"fields\":" + fields + "}}]",
        ),
        [("g", graph)],
        None,
        None,
        limits(),
      ),
    )
    let keys = @pipeline_typing.candidate_keys(p, Step(0)).unwrap()
    assert_eq(@evidence.key_witness_count(keys), expected)
    if expected == 1 {
      let key = @evidence.key_witness_at(keys, 0).unwrap()
      assert_eq(@evidence.key_field_count(key), 3)
      assert_true(
        @evidence.key_field_at(key, 2).unwrap().contract.unwrap().nullable,
      )
    }
  }
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(
      cursor(
        "[{\"reach\":{\"start\":1,\"direction\":\"both\",\"max_depth\":2}},{\"drop\":[\"node_id\"]}]",
      ),
      [("g", graph)],
      None,
      None,
      limits(),
    ),
  )
  let key = @pipeline_typing.candidate_key(p, Step(1)).unwrap()
  assert_eq(@evidence.key_field_at(key, 0).unwrap().name, Unqualified("node"))
  assert_eq(
    @evidence.declared_key_field_at(key, 0).unwrap().name,
    Unqualified("node_id"),
  )
  assert_true(
    @evidence.key_graph_query_producer(key) is Some(ReachOperation(_)),
  )
}

///|
test "Graph query keys retain producer and complete identity through projections" {
  let cases = [
    ("\"degree\":{\"direction\":\"both\"}", ["node"]),
    ("\"components\":{\"kind\":\"weak\"}", ["node_id"]),
    ("\"graph_bounds\":{\"max_nodes\":0,\"max_degree\":0}", ["kind", "node_id"]),
    (
      "\"match_nodes\":{\"where\":\"true\",\"fields\":[\"node_id\"]}",
      ["node_id"],
    ),
    (
      "\"reach\":{\"start\":1,\"direction\":\"both\",\"max_depth\":3}",
      ["node_id"],
    ),
    (
      "\"traverse\":{\"start\":{\"ids\":[1,1,2]},\"direction\":\"both\",\"min_hops\":0,\"max_hops\":3,\"emit\":\"nodes\"}",
      ["start_id", "node_id"],
    ),
    (
      "\"shortest_path\":{\"source\":{\"ids\":[1,2]},\"target\":{\"ids\":[1,2]},\"direction\":\"both\",\"max_hops\":3,\"selection\":\"each_pair\"}",
      ["source_id", "target_id"],
    ),
    (
      "\"shortest_path\":{\"source\":{\"ids\":[1,2]},\"target\":{\"ids\":[1,2]},\"direction\":\"both\",\"max_hops\":3,\"selection\":\"nearest_per_source\"}",
      ["source_id"],
    ),
    (
      "\"shortest_path\":{\"source\":{\"ids\":[1]},\"target\":{\"ids\":[2]},\"direction\":\"both\",\"max_hops\":3,\"selection\":\"nearest_pair\"}",
      ["source_id"],
    ),
  ]
  for (operation, names) in cases {
    let projection = [
      "{\"a\":\"" + names[0] + "\"}",
      "{\"b\":\"" + names[0] + "\"}",
    ]
    for i in 1..<names.length() {
      projection.push("\"" + names[i] + "\"")
    }
    let source = cursor(
      "[" +
      graph_count_seed(3) +
      ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{" +
      operation +
      "},{\"select\":[" +
      projection.join(",") +
      "]},{\"drop\":[\"a\"]}]",
    )
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(source, [], None, None, limits()),
    )
    let key = @pipeline_typing.candidate_key(p, Step(2)).unwrap()
    assert_eq(@evidence.key_origin(key), GraphQueryResult)
    assert_eq(@evidence.key_field_count(key), names.length())
    for i, name in names {
      assert_eq(@evidence.key_field_at(key, i).unwrap().name, Unqualified(name))
    }
    let output = @pipeline_typing.candidate_key(p, Step(4)).unwrap()
    assert_eq(@evidence.key_field_at(output, 0).unwrap().name, Unqualified("b"))
    assert_eq(
      @evidence.declared_key_field_at(output, 0).unwrap().name,
      Unqualified(names[0]),
    )
    assert_eq(@evidence.key_pending(output), [ValidateKeyProducer])
    let producer = @evidence.key_graph_query_producer(output).unwrap()
    let actual = match producer {
      GraphOperation(op) => @graph.input(op)
      MatchOperation(op) => @graph.match_input(op)
      ReachOperation(op) => @graph.reach_input(op)
      TraverseOperation(op) => @graph.traverse_input(op)
      ShortestOperation(op) => @graph.shortest_input(op)
    }
    assert_true(
      physical_equal(actual, @pipeline_typing.carrier_at(p, Step(1)).unwrap()),
    )
    let t = @evidence.graph_query_keys(producer, {
      max_work: 100,
      max_name_bytes: 1000,
    }).unwrap()
    let exact : @evidence.TransferLimits = {
      max_work: t.work,
      max_name_bytes: t.name_bytes,
    }
    assert_true(@evidence.graph_query_keys(producer, exact) is Ok(_))
    assert_true(
      @evidence.graph_query_keys(producer, { ..exact, max_work: t.work - 1, })
      is Err(_),
    )
    assert_true(
      @evidence.graph_query_keys(producer, {
        ..exact,
        max_name_bytes: t.name_bytes - 1,
      })
      is Err(_),
    )
    let u = @pipeline_typing.usage(p)
    let cap = {
      ..limits(),
      max_work: u.work,
      max_nodes: u.nodes,
      max_tokens: u.tokens,
      max_text_bytes: u.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_carriers(source, [], None, None, cap) is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_carriers(source, [], None, None, {
        ..cap,
        max_work: u.work - 1,
      })
      is Err(_),
    )
  }
}

///|
test "Graph query projection loss and path enumeration do not invent keys" {
  for
    operation in [
      "\"traverse\":{\"start\":{\"ids\":[1,2]},\"direction\":\"both\",\"min_hops\":0,\"max_hops\":3,\"emit\":\"paths\"}",
      "\"match_edges\":{\"where\":\"true\",\"fields\":[\"src\"]}",
    ] {
    let p = graph_count_checked(
      @pipeline_typing.check_carriers(
        cursor(
          "[" +
          graph_count_seed(3) +
          ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{" +
          operation +
          "}]",
        ),
        [],
        None,
        None,
        limits(),
      ),
    )
    assert_eq(
      @evidence.key_witness_count(
        @pipeline_typing.candidate_keys(p, Step(2)).unwrap(),
      ),
      0,
    )
  }
  let p = graph_count_checked(
    @pipeline_typing.check_carriers(
      cursor(
        "[" +
        graph_count_seed(3) +
        ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"traverse\":{\"start\":{\"ids\":[1,2]},\"direction\":\"out\",\"min_hops\":0,\"max_hops\":3,\"emit\":\"nodes\"}},{\"drop\":[\"start_id\"]}]",
      ),
      [],
      None,
      None,
      limits(),
    ),
  )
  assert_true(@pipeline_typing.candidate_key(p, Step(3)) is None)
  let unknown = @pipeline_typing.check_carriers(
    cursor("[{\"degree\":{\"direction\":\"both\"}}]"),
    [("g", @carrier.unknown_carrier(GraphKind))],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.candidate_key(unknown, Step(0)) is None)
}
