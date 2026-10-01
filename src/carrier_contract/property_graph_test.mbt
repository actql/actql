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
  let definition = graph_property_definition(graph).unwrap()
  assert_eq(property_graph_domain(definition), "sha256:" + "1".repeat(64))
  assert_eq(property_graph_node_definitions(definition).length(), 2)
  assert_eq(property_graph_edge_definitions(definition).length(), 1)
  assert_eq(property_definition_keys(first).length(), 2)
  assert_true(!property_definition_keys(first)[0].nullable)
  assert_eq(property_definition_labels(first), ["Node", "Person"])
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
test "legacy Graph metadata remains a separate unchanged profile" {
  let empty = rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
  guard graph(
      @value.primitive(NumberType, nullable=false),
      empty,
      empty,
      labels=Some(["R"]),
      max_labels=1,
      max_label_bytes=10,
    ).unwrap()
    is GraphValue(value) else {
    fail("legacy graph")
  }
  assert_true(graph_property_definition(value) is None)
  assert_eq(graph_labels(value), Some(["R"]))
}
