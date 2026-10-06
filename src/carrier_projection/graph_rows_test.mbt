///|
fn graph_row_definition(
  name : String,
  key_column : String,
  property_name : String,
  label? : String = "Person",
) -> @carrier.GraphNodeDefinition {
  let number = @contract.primitive(NumberType, nullable=false)
  let props = @carrier.rows(
    [
      (
        @row.Unqualified(property_name),
        Some(@contract.primitive(NumberType, nullable=true)),
      ),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  @carrier.graph_node_definition(
    name,
    [number],
    props,
    [label],
    key_columns=[key_column],
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
}

///|
fn graph_label_definition(
  name : String,
  key_column : String,
  nullable : Bool,
  extra : Bool,
  string_key? : Bool = false,
) -> @carrier.GraphNodeDefinition {
  let number = @contract.primitive(NumberType, nullable=false)
  let p = @contract.primitive(NumberType, nullable~)
  let person = @carrier.rows(
    [(@row.Unqualified("p"), Some(p))],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let detail = @carrier.rows(
    [(@row.Unqualified("q"), Some(number))],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let properties = if extra {
    @carrier.rows(
      [(@row.Unqualified("p"), Some(p)), (@row.Unqualified("q"), Some(number))],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap()
  } else {
    person
  }
  @carrier.graph_node_definition(
    name,
    [
      if string_key {
        @contract.primitive(StringType, nullable=false)
      } else {
        number
      },
    ],
    properties,
    if extra {
      ["Person", "Detail"]
    } else {
      ["PERSON"]
    },
    key_columns=[key_column],
    label_properties=if extra {
      [("Person", person), ("Detail", detail)]
    } else {
      [("PERSON", person)]
    },
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "label candidates reject incompatible raw key types and role collisions" {
  let graph = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [
      graph_label_definition("A", "raw_key", false, false),
      graph_label_definition("B", "RAW_KEY", true, true, string_key=true),
    ],
    [],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  assert_true(
    check(NodeRows, cursor("{\"label\":\"person\"}"), graph, limits())
    is Err({ kind: OutputTypeConflict(_), .. }),
  )
  for
    (key, property) in [("id", "p"), ("raw_key", "ID"), ("raw_key", "RAW_KEY")] {
    let graph = @carrier.graph(
      "sha256:" + "0".repeat(64),
      [graph_row_definition("A", key, property)],
      [],
      max_definitions=1,
      max_contract_work=1000,
    ).unwrap()
    assert_true(
      check(NodeRows, cursor("{\"label\":\"person\"}"), graph, limits())
      is Err({ kind: OutputCollision(_), .. }),
    )
  }
}

///|
test "label row schema includes every declared candidate and keeps conditional columns" {
  let graph = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [
      graph_label_definition("A", "a_key", false, false),
      graph_label_definition("B", "b_key", true, true),
      graph_row_definition("C", "c_key", "q", label="Company"),
    ],
    [],
    max_definitions=3,
    max_contract_work=1000,
  ).unwrap()
  let checked = check(
    NodeRows,
    cursor("{\"label\":\"pErSoN\"}"),
    graph,
    limits(),
  ).unwrap()
  assert_eq(selected_definition(checked), None)
  assert_eq(selected_label(checked), Some("PERSON"))
  let schema = @carrier.complete_schema(
    @carrier.relation_rows(output(checked)).unwrap(),
  ).unwrap()
  assert_eq(@row.field_count(schema), 6)
  assert_eq(@row.lookup_reference(schema, "p").unwrap().presence, @row.Required)
  assert_true(@row.lookup(schema, @row.Unqualified("p")).unwrap().nullable)
  for field in ["a_key", "b_key", "q"] {
    assert_eq(
      @row.lookup_reference(schema, field).unwrap().presence,
      @row.Conditional,
    )
    assert_false(@row.lookup(schema, @row.Unqualified(field)).unwrap().nullable)
  }
  assert_true(@row.lookup_reference(schema, "c_key") is None)
  for
    body in [
      "{}", "false", "{\"label\":7}", "{\"label\":\"Person\",\"definition\":\"A\"}",
      "{\"label\":\"Person\",\"extra\":true}",
    ] {
    assert_true(
      check(NodeRows, cursor(body), graph, limits())
      is Err({ kind: InvalidBody, .. }),
    )
  }
  assert_true(
    check(NodeRows, cursor("{\"label\":\"Unknown\"}"), graph, limits())
    is Err({ kind: UnknownLabel("Unknown"), .. }),
  )
  assert_true(
    check(EdgeRows, cursor("{\"label\":\"Person\"}"), graph, limits())
    is Err({ kind: UnknownLabel("Person"), .. }),
  )
  assert_true(
    check(NodeRows, cursor("{\"label\":\"Person\"}"), graph, {
      ..limits(),
      max_work: 4,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    check(NodeRows, cursor("{\"label\":\"Person\"}"), graph, {
      ..limits(),
      max_nodes: 5,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  let reordered = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [
      graph_row_definition("C", "c_key", "q", label="Company"),
      graph_label_definition("B", "b_key", true, true),
      graph_label_definition("A", "a_key", false, false),
    ],
    [],
    max_definitions=3,
    max_contract_work=1000,
  ).unwrap()
  let again = check(
    NodeRows,
    cursor("{\"label\":\"PERSON\"}"),
    reordered,
    limits(),
  ).unwrap()
  assert_eq(selected_label(again), selected_label(checked))
  let again_schema = @carrier.complete_schema(
    @carrier.relation_rows(output(again)).unwrap(),
  ).unwrap()
  assert_eq(@row.field_count(again_schema), @row.field_count(schema))
  for index in 0..<@row.field_count(schema) {
    let original = @row.field_at(schema, index).unwrap()
    let restored = @row.field_at(again_schema, index).unwrap()
    assert_eq(restored.name, original.name)
    assert_eq(restored.presence, original.presence)
    assert_true(
      @contract.type_equal(restored.contract, original.contract, 1000),
    )
  }
}

///|
test "graph rows finite schema separates roles raw keys presence and nullable" {
  let first = graph_row_definition("N", "person_key", "p")
  let second = graph_row_definition("M", "company_key", "p")
  let graph = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [first, second],
    [],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  let checked = check(NodeRows, cursor("true"), graph, limits()).unwrap()
  guard output(checked) is @carrier.Relation(rows) else { fail("Relation") }
  let schema = @carrier.complete_schema(rows).unwrap()
  assert_eq(@row.field_count(schema), 5)
  assert_eq(
    @row.lookup_reference(schema, "id").unwrap().presence,
    @row.Required,
  )
  assert_eq(
    @row.lookup_reference(schema, "labels").unwrap().presence,
    @row.Required,
  )
  assert_eq(
    @row.lookup_reference(schema, "person_key").unwrap().presence,
    @row.Conditional,
  )
  assert_false(
    @row.lookup(schema, @row.Unqualified("person_key")).unwrap().nullable,
  )
  assert_eq(@row.lookup_reference(schema, "p").unwrap().presence, @row.Required)
  assert_true(@row.lookup(schema, @row.Unqualified("p")).unwrap().nullable)
  let reordered = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [second, first],
    [],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  let again = check(NodeRows, cursor("true"), reordered, limits()).unwrap()
  assert_eq(
    @carrier.field_count(@carrier.relation_rows(output(again)).unwrap()),
    5,
  )
}

///|
test "graph row role property key collisions reject instead of overwrite" {
  for
    (key, property) in [
      ("id", "p"),
      ("person_key", "ID"),
      ("person_key", "PERSON_KEY"),
    ] {
    let graph = @carrier.graph(
      "sha256:" + "0".repeat(64),
      [graph_row_definition("N", key, property)],
      [],
      max_definitions=1,
      max_contract_work=1000,
    ).unwrap()
    assert_true(
      check(NodeRows, cursor("true"), graph, limits())
      is Err({ kind: OutputCollision(_), .. }),
    )
  }
  let graph = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [
      graph_row_definition("N", "person_key", "p"),
      graph_row_definition("M", "company_key", "PERSON_KEY", label="Company"),
    ],
    [],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  assert_true(
    check(NodeRows, cursor("true"), graph, limits())
    is Err({ kind: OutputCollision(_), .. }),
  )
}

///|
test "definition row selection derives presence from declarations not data" {
  let graph = @carrier.graph(
    "sha256:" + "0".repeat(64),
    [
      graph_row_definition("Person", "person_key", "p"),
      graph_row_definition("Company", "company_key", "q", label="Company"),
    ],
    [],
    max_definitions=2,
    max_contract_work=1000,
  ).unwrap()
  let checked = check(
    NodeRows,
    cursor("{\"definition\":\"pErSoN\"}"),
    graph,
    limits(),
  ).unwrap()
  let schema = @carrier.complete_schema(
    @carrier.relation_rows(output(checked)).unwrap(),
  ).unwrap()
  assert_eq(selected_definition(checked), Some("Person"))
  assert_eq(@row.field_count(schema), 4)
  assert_eq(@row.lookup_reference(schema, "p").unwrap().presence, @row.Required)
  assert_true(@row.lookup(schema, @row.Unqualified("p")).unwrap().nullable)
  assert_eq(
    @row.lookup_reference(schema, "person_key").unwrap().presence,
    @row.Required,
  )
  assert_true(@row.lookup_reference(schema, "q") is None)
  assert_true(@row.lookup_reference(schema, "company_key") is None)
  for
    body in [
      "{\"definition\":\"Unknown\"}", "{\"definition\":\"Person\",\"label\":\"Person\"}",
      "{}", "false",
    ] {
    assert_true(check(NodeRows, cursor(body), graph, limits()) is Err(_))
  }
  assert_true(
    check(EdgeRows, cursor("{\"definition\":\"Person\"}"), graph, limits())
    is Err(_),
  )
  let all = check(NodeRows, cursor("true"), graph, limits()).unwrap()
  let all_schema = @carrier.complete_schema(
    @carrier.relation_rows(output(all)).unwrap(),
  ).unwrap()
  assert_eq(
    @row.lookup_reference(all_schema, "p").unwrap().presence,
    @row.Conditional,
  )
  assert_true(
    check(NodeRows, cursor("{\"definition\":\"Person\"}"), graph, {
      ..limits(),
      max_nodes: 3,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    check(NodeRows, cursor("{\"definition\":\"Person\"}"), graph, {
      ..limits(),
      max_work: 2,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
}
