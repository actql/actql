///|
fn graph_row_definition(
  name : String,
  key_column : String,
  property_name : String,
  label? : String = "Person",
) -> @carrier.PropertyNodeDefinition {
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
  @carrier.property_node_definition(
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
test "graph rows finite schema separates roles raw keys presence and nullable" {
  let first = graph_row_definition("N", "person_key", "p")
  let second = graph_row_definition("M", "company_key", "p")
  let graph = @carrier.property_graph(
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
  let reordered = @carrier.property_graph(
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
    let graph = @carrier.property_graph(
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
  let graph = @carrier.property_graph(
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
  let graph = @carrier.property_graph(
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
