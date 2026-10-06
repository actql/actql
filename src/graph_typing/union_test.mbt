///|
fn union_test_node(
  name : String,
  fields : Array[(String, @contract.Contract)],
  label? : String = "Entity",
  key? : String = "original_key",
  keys? : Array[@contract.Contract] = [
    @contract.primitive(NumberType, nullable=false),
  ],
  columns? : Array[String] = [key],
) -> @carrier.PropertyNodeDefinition {
  let properties = @carrier.rows(
    fields.map(pair => (@row.Unqualified(pair.0), Some(pair.1))),
    field_set=Closed,
    max_fields=100,
    max_name_bytes=10000,
  ).unwrap()
  @carrier.property_node_definition(
    name,
    keys,
    properties,
    [label],
    key_columns=columns,
    max_fields=100,
    max_name_bytes=10000,
  ).unwrap()
}

///|
fn union_test_graph(
  nodes : Array[@carrier.PropertyNodeDefinition],
  edge_properties? : Array[(String, @contract.Contract)] = [],
  target? : String = "N",
  edge_name? : String = "Link",
  edge_keys? : Array[@contract.Contract] = [
    @contract.primitive(NumberType, nullable=false),
  ],
  domain? : String = "sha256:0000000000000000000000000000000000000000000000000000000000000000",
) -> @carrier.Carrier {
  let edge = @carrier.property_edge_definition(
    union_test_node(
      edge_name,
      edge_properties,
      label="Connection",
      key="edge_key",
      keys=edge_keys,
    ),
    "N",
    target,
  ).unwrap()
  @carrier.property_graph(
    domain,
    nodes,
    [edge],
    max_definitions=100,
    max_contract_work=10000,
  ).unwrap()
}

///|
fn union_test_contract(body : String) -> @contract.Contract {
  @contract.read_checked(cursor(body), {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
}

///|
test "union refuses identity bearing definition spelling and key descriptor changes" {
  let number = @contract.primitive(NumberType, nullable=false)
  let left = union_test_graph([union_test_node("N", [])])
  for
    (right, expected) in [
      (
        union_test_graph([union_test_node("n", [])]),
        @graph_typing.UnionDefinitionIdentityMismatch("N"),
      ),
      (
        union_test_graph([union_test_node("N", [])], edge_name="link"),
        @graph_typing.UnionDefinitionIdentityMismatch("Link"),
      ),
    ] {
    assert_true(
      @graph_typing.check_union(
        cursor("{\"with\":\"peer\"}"),
        [left, right],
        limits(),
      )
      is Err({ kind, .. }) &&
      kind == expected,
    )
  }
  let pdf = union_test_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/pdf\"}",
  )
  let json = union_test_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let any_artifact = union_test_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false}",
  )
  let issue = union_test_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"Issue\"}",
  )
  let pull = union_test_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"PullRequest\"}",
  )
  for
    (first, second) in [
      (pdf, json),
      (pdf, any_artifact),
      (issue, pull),
      (
        @contract.decimal_contract(18, 2, nullable=false).unwrap(),
        @contract.decimal_contract(38, 2, nullable=false).unwrap(),
      ),
      (
        @contract.decimal_contract(18, 2, nullable=false).unwrap(),
        @contract.decimal_contract(18, 3, nullable=false).unwrap(),
      ),
      (number, @contract.primitive(StringType, nullable=false)),
    ] {
    for edge in [false, true] {
      let first_graph = union_test_graph(
        [union_test_node("N", [], keys=[if edge { number } else { first }])],
        edge_keys=[if edge { first } else { number }],
      )
      let second_graph = union_test_graph(
        [union_test_node("N", [], keys=[if edge { number } else { second }])],
        edge_keys=[if edge { second } else { number }],
      )
      let expected = @graph_typing.UnionKeyIdentityMismatch(
        if edge {
          "Link"
        } else {
          "N"
        },
        0,
      )
      assert_true(
        @graph_typing.check_union(
          cursor("{\"with\":\"peer\"}"),
          [first_graph, second_graph],
          limits(),
        )
        is Err({ kind, .. }) &&
        kind == expected,
      )
    }
  }
}

///|
test "union joins text extents and property domains without changing ordered key identity" {
  let text = @contract.primitive(StringType, nullable=false)
  let tight = union_test_contract(
    "{\"type\":\"string\",\"nullable\":false,\"max_utf8_bytes\":8}",
  )
  let pdf = union_test_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/pdf\"}",
  )
  let json = union_test_contract(
    "{\"type\":\"artifact_ref\",\"nullable\":true,\"media_type\":\"application/json\"}",
  )
  let left = union_test_graph([
    union_test_node("N", [("p", pdf)], keys=[tight, text], columns=[
      "tenant", "person",
    ]),
  ])
  let right = union_test_graph([
    union_test_node("N", [("P", json)], keys=[text, tight], columns=[
      "tenant", "person",
    ]),
  ])
  let checked = @graph_typing.check_union(
    cursor("{\"with\":\"peer\"}"),
    [left, right],
    limits(),
  ).unwrap()
  guard @graph_typing.union_output(checked) is @carrier.GraphValue(graph) else {
    fail("Graph output required")
  }
  let definition = @carrier.property_graph_node_at(
    @carrier.graph_property_definition(graph),
    0,
  ).unwrap()
  for index in 0..<2 {
    let key = @carrier.property_definition_key_at(definition, index).unwrap()
    assert_eq(@carrier.property_key_descriptor(key), Some(@carrier.TextKey))
    assert_true(@contract.type_equal(key, text, 1))
  }
  assert_eq(
    @carrier.property_definition_key_column_at(definition, 0),
    Some("tenant"),
  )
  assert_eq(
    @carrier.property_definition_key_column_at(definition, 1),
    Some("person"),
  )
  let field = @carrier.field_at(
    @carrier.property_definition_properties(definition),
    0,
  ).unwrap()
  assert_true(
    field.contract
    is Some({ shape: ArtifactRef(media_type=None), nullable: true, }),
  )
  let reversed = union_test_graph([
    union_test_node("N", [("p", pdf)], keys=[text, text], columns=[
      "person", "tenant",
    ]),
  ])
  assert_true(
    @graph_typing.check_union(
      cursor("{\"with\":\"peer\"}"),
      [left, reversed],
      limits(),
    )
    is Err({ kind: IncompatibleGraphDomains, .. }),
  )
}

///|
test "union checks named definition and property alignment without erasing occurrences" {
  let number = @contract.primitive(NumberType, nullable=false)
  let left = union_test_graph(
    [
      union_test_node("N", [("p", number), ("q", number)]),
      union_test_node("M", [("p", number), ("q", number)]),
    ],
    edge_properties=[("p", number), ("q", number)],
  )
  let right = union_test_graph(
    [
      union_test_node("M", [("Q", number), ("p", number)]),
      union_test_node("N", [("Q", number), ("p", number)]),
    ],
    edge_properties=[("Q", number), ("p", number)],
  )
  let checked = @graph_typing.check_union(
    cursor(
      "{\"with\":[\"peer\",\"peer\"],\"merge\":{\"node_properties\":{\"p\":\"number_sum\"}}}",
    ),
    [left, right, right],
    limits(),
  ).unwrap()
  assert_eq(@graph_typing.union_input_count(checked), 3)
  assert_eq(
    @graph_typing.union_right_definition(checked, 0, 0, edge=false),
    Some(1),
  )
  assert_eq(
    @graph_typing.union_right_definition(checked, 0, 1, edge=false),
    Some(0),
  )
  assert_eq(
    @graph_typing.union_field_at(checked, 0, 0, 0, edge=false),
    Some((0, 1, UnionNumberSum)),
  )
  assert_eq(
    @graph_typing.union_field_at(checked, 0, 0, 1, edge=false),
    Some((1, 0, UnionExactEqual)),
  )
  assert_eq(
    @graph_typing.union_field_at(checked, 0, 0, 0, edge=true),
    Some((0, 1, UnionExactEqual)),
  )
  assert_true(@graph_typing.union_fold_output(checked, 1) is Some(_))
  assert_eq(
    @graph_typing.union_right_definition(checked, 2, 0, edge=false),
    None,
  )
}

///|
test "union refuses incompatible labels ordered key mapping endpoint definitions and domain" {
  let number = @contract.primitive(NumberType, nullable=false)
  let left = union_test_graph([
    union_test_node("N", [("p", number)]),
    union_test_node("M", [("p", number)]),
  ])
  for
    right in [
      union_test_graph([
        union_test_node("N", [("p", number)], label="Other"),
        union_test_node("M", [("p", number)]),
      ]),
      union_test_graph([
        union_test_node("N", [("p", number)], key="different_key"),
        union_test_node("M", [("p", number)]),
      ]),
      union_test_graph(
        [
          union_test_node("N", [("p", number)]),
          union_test_node("M", [("p", number)]),
        ],
        target="M",
      ),
      union_test_graph(
        [
          union_test_node("N", [("p", number)]),
          union_test_node("M", [("p", number)]),
        ],
        domain="sha256:1111111111111111111111111111111111111111111111111111111111111111",
      ),
    ] {
    assert_true(
      @graph_typing.check_union(
        cursor("{\"with\":\"peer\"}"),
        [left, right],
        limits(),
      )
      is Err({ kind: IncompatibleGraphDomains, .. }),
    )
  }
}

///|
test "union derives strategy output extents without narrowing nullable one sided records" {
  let nullable = @contract.primitive(NumberType, nullable=true)
  let array = @contract.array_contract(
    nullable,
    nullable=true,
    max_items=Some(2L),
  ).unwrap()
  let graph = union_test_graph([
    union_test_node("N", [("p", nullable), ("tags", array)]),
  ])
  let checked = @graph_typing.check_union(
    cursor(
      "{\"with\":[\"peer\",\"peer\"],\"merge\":{\"node_properties\":{\"p\":\"number_sum\",\"tags\":\"set_union\"}}}",
    ),
    [graph, graph, graph],
    limits(),
  ).unwrap()
  guard @graph_typing.union_output(checked) is @carrier.GraphValue(output) else {
    fail("Graph output required")
  }
  let definition = @carrier.property_graph_node_at(
    @carrier.graph_property_definition(output),
    0,
  ).unwrap()
  let schema = @carrier.complete_schema(
    @carrier.property_definition_properties(definition),
  ).unwrap()
  assert_true(
    @row.lookup(schema, Unqualified("p"))
    is Some({ shape: Number, nullable: true, }),
  )
  assert_true(
    @row.lookup(schema, Unqualified("tags"))
    is Some(
      { shape: Array({ nullable: true, .. }, max_items=None), nullable: true, }
    ),
  )
}

///|
test "union rejects unknown duplicate incompatible and malformed merge strategies" {
  let graph = union_test_graph([
    union_test_node("N", [
      ("p", @contract.primitive(NumberType, nullable=false)),
    ]),
  ])
  for
    body in [
      "{\"with\":[]}", "{\"with\":\"peer\",\"extra\":true}", "{\"with\":\"peer\",\"merge\":{\"other\":{}}}",
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"p\":\"unknown\"}}}",
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"missing\":\"exact_equal\"}}}",
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"p\":\"number_sum\",\"P\":\"number_min\"}}}",
      "{\"with\":\"peer\",\"merge\":{\"node_properties\":{\"p\":\"set_union\"}}}",
    ] {
    assert_true(
      @graph_typing.check_union(cursor(body), [graph, graph], limits())
      is Err(_),
    )
  }
  assert_true(
    @graph_typing.check_union(cursor("{\"with\":\"peer\"}"), [graph], limits())
    is Err(_),
  )
}

///|
test "union charges cumulative checking once across the complete authored fold" {
  let graph = union_test_graph([
    union_test_node("N", [
      ("p", @contract.primitive(NumberType, nullable=false)),
    ]),
  ])
  let source = cursor("{\"with\":[\"peer\",\"peer\"]}")
  let checked = @graph_typing.check_union(
    source,
    [graph, graph, graph],
    limits(),
  ).unwrap()
  let usage = @graph_typing.union_usage(checked)
  let exact = {
    ..limits(),
    max_work: usage.work,
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
  }
  assert_true(
    @graph_typing.check_union(source, [graph, graph, graph], exact) is Ok(_),
  )
  for
    short in [
      { ..exact, max_work: usage.work - 1, },
      { ..exact, max_nodes: usage.nodes - 1, },
      { ..exact, max_text_bytes: usage.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_union(source, [graph, graph, graph], short) is Err(_),
    )
  }
}
