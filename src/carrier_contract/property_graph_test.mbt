///|
fn property_fixture(
  name : String,
  keys : Array[@value.Contract],
  labels? : Array[String] = ["Node"],
  properties? : Knowledge = rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap(),
) -> PropertyNodeDefinition {
  property_node_definition(
    name,
    keys,
    properties,
    labels,
    max_fields=20,
    max_name_bytes=1000,
  ).unwrap()
}

///|
test "Property Graph metadata retains heterogeneous definition-scoped composite keys" {
  let number = @value.primitive(NumberType, nullable=true)
  let text = @value.primitive(StringType, nullable=false)
  let first = property_fixture("N", [number, text], labels=["Person", "Node"])
  let second = property_fixture("M", [text], labels=["Company"])
  let edge = property_edge_definition(
    property_fixture("E", [number], labels=["R"]),
    "N",
    "M",
  ).unwrap()
  let input_nodes = [first, second]
  let input_edges = [edge]
  guard property_graph(
      "sha256:" + "1".repeat(64),
      input_nodes,
      input_edges,
      max_definitions=3,
      max_contract_work=1000,
    ).unwrap()
    is GraphValue(graph) else {
    fail("graph")
  }
  input_nodes.clear()
  input_edges.clear()
  let definition = graph_property_definition(graph)
  assert_eq(property_graph_domain(definition), "sha256:" + "1".repeat(64))
  assert_eq(property_graph_node_definitions(definition).length(), 2)
  assert_eq(property_graph_edge_definitions(definition).length(), 1)
  assert_eq(property_definition_keys(first).length(), 2)
  assert_true(property_definition_key_at(first, -1) is None)
  assert_true(property_definition_key_at(first, 2) is None)
  let key = property_definition_key_at(first, 1).unwrap()
  assert_true(key.shape is @value.Text(_))
  assert_false(key.nullable)
  assert_true(!property_definition_keys(first)[0].nullable)
  assert_eq(property_definition_labels(first), ["Node", "Person"])
  assert_eq(property_definition_label_count(first), 2)
  assert_true(property_definition_label_at(first, -1) is None)
  assert_true(property_definition_label_at(first, 2) is None)
  let (label, fields) = property_definition_label_at(first, 0).unwrap()
  assert_eq(label, "Node")
  assert_eq(field_count(fields), 0)
  assert_eq(property_edge_endpoints(edge), ("N", "M"))
  let detached = property_definition_keys(first)
  detached.clear()
  assert_eq(property_definition_keys(first).length(), 2)
}

///|
test "Property Graph labels never come from property names or values" {
  let properties = rows(
    [
      (
        @row.Unqualified("entity_type"),
        Some(@value.primitive(StringType, nullable=false)),
      ),
    ],
    field_set=Closed,
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let definition = property_fixture(
    "N",
    [@value.primitive(NumberType, nullable=false)],
    labels=["Person"],
    properties~,
  )
  assert_eq(property_definition_labels(definition), ["Person"])
  assert_eq(field_count(property_definition_properties(definition)), 1)
}

///|
test "Property Graph rejects case-colliding definitions and labels" {
  let number = @value.primitive(NumberType, nullable=false)
  let empty = rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  assert_eq(
    property_node_definition(
      "N",
      [number],
      empty,
      ["Node", "node"],
      max_fields=10,
      max_name_bytes=100,
    ).unwrap_err(),
    DuplicateLabel,
  )
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      [property_fixture("N", [number]), property_fixture("n", [number])],
      [],
      max_definitions=2,
      max_contract_work=100,
    ).unwrap_err(),
    DuplicateDefinition,
  )
}

///|
test "Property Graph rejects unsupported key domains and unknown endpoint definitions" {
  let json = @value.primitive(JsonType, nullable=false)
  let number = @value.primitive(NumberType, nullable=false)
  let empty = rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  assert_eq(
    property_node_definition(
      "N",
      [json],
      empty,
      [],
      max_fields=10,
      max_name_bytes=100,
    ).unwrap_err(),
    InvalidKey,
  )
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      [property_fixture("N", [number])],
      [
        property_edge_definition(
          property_fixture("E", [number]),
          "N",
          "unknown",
        ).unwrap(),
      ],
      max_definitions=2,
      max_contract_work=100,
    ).unwrap_err(),
    UnknownEndpointDefinition,
  )
}

///|
test "Property Graph repeated labels require compatible complete property schemas" {
  let number = @value.primitive(NumberType, nullable=false)
  let properties = fn(contract) {
    rows(
      [(@row.Unqualified("value"), Some(contract))],
      field_set=Closed,
      max_fields=1,
      max_name_bytes=100,
    ).unwrap()
  }
  let first = property_fixture("N", [number], properties=properties(number))
  let second = property_fixture(
    "M",
    [number],
    properties=properties(@value.with_nullability(number, true)),
  )
  assert_true(
    property_graph(
      "sha256:" + "1".repeat(64),
      [first, second],
      [],
      max_definitions=2,
      max_contract_work=100,
    )
    is Ok(_),
  )
  let incompatible = property_fixture(
    "M",
    [number],
    properties=properties(@value.primitive(StringType, nullable=false)),
  )
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      [first, incompatible],
      [],
      max_definitions=2,
      max_contract_work=100,
    ).unwrap_err(),
    LabelPropertyConflict,
  )
}

///|
test "Property Graph metadata is bounded and cannot invent a domain from a locator" {
  let number = @value.primitive(NumberType, nullable=false)
  let nodes = [property_fixture("N", [number])]
  assert_eq(
    property_graph(
      "/tmp/graph",
      nodes,
      [],
      max_definitions=1,
      max_contract_work=100,
    ).unwrap_err(),
    InvalidDomain,
  )
  assert_eq(
    property_graph(
      "sha256:" + "g".repeat(64),
      nodes,
      [],
      max_definitions=1,
      max_contract_work=100,
    ).unwrap_err(),
    InvalidDomain,
  )
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      nodes,
      [],
      max_definitions=0,
      max_contract_work=100,
    ).unwrap_err(),
    LimitExceeded,
  )
}

///|
fn scored_property_fixture(
  name : String,
  label : String,
  property : String,
  contract : @value.Contract,
) -> PropertyNodeDefinition {
  property_fixture(
    name,
    [@value.primitive(NumberType, nullable=false)],
    labels=[label],
    properties=rows(
      [(@row.Unqualified(property), Some(contract))],
      field_set=Closed,
      max_fields=10,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
test "Graph wide property type compatibility crosses distinct labels and node edge definitions" {
  let number = @value.primitive(NumberType, nullable=false)
  let text = @value.primitive(StringType, nullable=false)
  let first = scored_property_fixture("N", "Person", "score", number)
  let incompatible = scored_property_fixture("M", "Company", "SCORE", text)
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      [first, incompatible],
      [],
      max_definitions=3,
      max_contract_work=1000,
    ).unwrap_err(),
    PropertyTypeConflict,
  )
  let edge = property_edge_definition(
    scored_property_fixture("E", "Relationship", "SCORE", text),
    "N",
    "N",
  ).unwrap()
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      [first],
      [edge],
      max_definitions=3,
      max_contract_work=1000,
    ).unwrap_err(),
    PropertyTypeConflict,
  )
}

///|
test "Shared label property sets cross node edge definitions even with compatible value types" {
  let number = @value.primitive(NumberType, nullable=false)
  let text = @value.primitive(StringType, nullable=false)
  let node = scored_property_fixture("N", "Person", "name", text)
  let element = property_fixture(
    "E",
    [number],
    labels=["PERSON"],
    properties=rows(
      [
        (@row.Unqualified("NAME"), Some(@value.with_nullability(text, true))),
        (@row.Unqualified("score"), Some(number)),
      ],
      field_set=Closed,
      max_fields=10,
      max_name_bytes=100,
    ).unwrap(),
  )
  let edge = property_edge_definition(element, "N", "N").unwrap()
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      [node],
      [edge],
      max_definitions=3,
      max_contract_work=1000,
    ).unwrap_err(),
    LabelPropertyConflict,
  )
}

///|
test "Compatible global property values preserve per definition nullability and bounded work" {
  let number = @value.primitive(NumberType, nullable=false)
  let nullable = @value.with_nullability(number, true)
  let first = scored_property_fixture("N", "Person", "score", number)
  let second = scored_property_fixture("M", "Company", "SCORE", nullable)
  let edge = property_edge_definition(
    scored_property_fixture("E", "PERSON", "SCORE", nullable),
    "N",
    "M",
  ).unwrap()
  let (carrier, used) = property_graph_usage(
    "sha256:" + "1".repeat(64),
    [first, second],
    [edge],
    max_definitions=3,
    max_contract_work=1000,
  ).unwrap()
  assert_true(carrier is GraphValue(_))
  assert_true(
    field_at(property_definition_properties(first), 0).unwrap().contract
    is Some({ nullable: false, .. }),
  )
  assert_true(
    field_at(property_definition_properties(second), 0).unwrap().contract
    is Some({ nullable: true, .. }),
  )
  assert_true(
    property_graph(
      "sha256:" + "1".repeat(64),
      [first, second],
      [edge],
      max_definitions=3,
      max_contract_work=used,
    )
    is Ok(_),
  )
  assert_eq(
    property_graph(
      "sha256:" + "1".repeat(64),
      [first, second],
      [edge],
      max_definitions=3,
      max_contract_work=used - 1,
    ).unwrap_err(),
    LimitExceeded,
  )
}
