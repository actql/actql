///|
fn property_fixture_rows() -> @carrier.Carrier {
  let number = @contract.primitive(NumberType, nullable=true)
  let text = @contract.primitive(StringType, nullable=true)
  @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("tenant"), Some(text)),
        (Unqualified("id"), Some(number)),
        (Unqualified("edge_id"), Some(number)),
        (Unqualified("src"), Some(number)),
        (Unqualified("dst"), Some(number)),
        (Unqualified("name"), Some(text)),
      ],
      field_set=Closed,
      max_fields=6,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
fn property_fixture_constructor() -> String {
  (
    #|{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["tenant","id"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"name","to":"display"}]}},{"name":"Identified","properties":{"mode":"columns","columns":[{"from":"id","to":"id"}]}}]}],"edges":[{"name":"E","from":"edges","key":["tenant","edge_id"],"labels":[{"name":"Knows","properties":{"mode":"no_properties"}}],"source":{"definition":"n","key":["tenant","src"],"references_key":["tenant","id"]},"target":{"definition":"N","key":["tenant","dst"]}}]}
  )
}

///|
fn property_fixture_domain() -> String {
  "sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

///|
fn checked_property_fixture(
  text : String,
) -> Result[@graph_typing.CheckedGraphConstruction, @graph_typing.Issue] {
  @graph_typing.check_graph_construction(
    cursor(text),
    [("nodes", property_fixture_rows()), ("edges", property_fixture_rows())],
    property_fixture_domain(),
    limits(),
  )
}

///|
test "keyed constructor preserves independent keys endpoint order label subsets and source provenance" {
  let at = cursor(property_fixture_constructor())
  let checked = @graph_typing.check_graph_construction(
    at,
    [("nodes", property_fixture_rows()), ("edges", property_fixture_rows())],
    property_fixture_domain(),
    limits(),
  ).unwrap()
  assert_eq(@graph_typing.construction_node_count(checked), 1)
  assert_eq(@graph_typing.construction_edge_count(checked), 1)
  assert_eq(
    @decode.tree_index(at, @graph_typing.construction_source(checked)),
    Some(0),
  )
  let node = @graph_typing.construction_node_at(checked, 0).unwrap()
  assert_eq(@graph_typing.graph_element_input(node), "nodes")
  assert_eq(@graph_typing.graph_element_keys(node), [
    Unqualified("tenant"),
    Unqualified("id"),
  ])
  assert_eq(@graph_typing.graph_element_properties(node), [
    (Unqualified("name"), Unqualified("display")),
    (Unqualified("id"), Unqualified("id")),
  ])
  let definition = @graph_typing.graph_element_definition(node)
  assert_eq(@carrier.graph_element_definition_labels(definition), [
    "Identified", "Person",
  ])
  let labels = @carrier.graph_element_definition_label_properties(definition)
  assert_eq(labels[1].0, "Person")
  assert_eq(@carrier.field_count(labels[1].1), 1)
  assert_true(
    @carrier.graph_element_definition_keys(definition).all(c => !c.nullable),
  )
  let edge = @graph_typing.construction_edge_at(checked, 0).unwrap()
  assert_eq(
    @graph_typing.graph_element_keys(@graph_typing.graph_edge_element(edge)),
    [Unqualified("tenant"), Unqualified("edge_id")],
  )
  assert_eq(@graph_typing.graph_edge_definitions(edge), ("N", "N"))
  assert_eq(
    @graph_typing.graph_edge_keys(edge),
    (
      [Unqualified("tenant"), Unqualified("src")],
      [Unqualified("tenant"), Unqualified("dst")],
    ),
  )
  // Detached mappings cannot change the checked definition.
  let keys = @graph_typing.graph_element_keys(node)
  keys[0] = Unqualified("name")
  assert_eq(@graph_typing.graph_element_keys(node)[0], Unqualified("tenant"))
}

///|
test "omitted labels and properties retain typed schema even before any input rows exist" {
  let body =
    #|{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[]}
  let checked = checked_property_fixture(body).unwrap()
  let definition = @graph_typing.graph_element_definition(
    @graph_typing.construction_node_at(checked, 0).unwrap(),
  )
  assert_eq(@carrier.graph_element_definition_labels(definition), ["N"])
  assert_eq(
    @carrier.field_count(
      @carrier.graph_element_definition_properties(definition),
    ),
    6,
  )
  assert_true(
    @carrier.lookup(
      @carrier.graph_element_definition_properties(definition),
      Unqualified("name"),
    )
    is Present({ contract: Some({ nullable: true, shape: Text(_), }), .. }),
  )
}

///|
test "constructor rejects legacy bodies caller supplied domains and case folded definition collisions" {
  for
    body in [
      (
        #|{"source":"src","target":"dst"}
      ),
      (
        #|{"version":"actql-graph-constructor/0.1","domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","nodes":[],"edges":[]}
      ),
      (
        #|{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]},{"name":"n","from":"nodes","key":["id"]}],"edges":[]}
      ),
      (
        #|{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Person"},{"name":"person"}]}],"edges":[]}
      ),
    ] {
    assert_true(checked_property_fixture(body) is Err(_))
  }
}

///|
test "endpoint references must match declared ordered keys not just arity" {
  for
    reference in [
      "[\"id\",\"tenant\"]", "[\"tenant\"]", "[\"tenant\",\"name\"]",
    ] {
    let body = "{\"version\":\"actql-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"tenant\",\"id\"]}],\"edges\":[{\"name\":\"E\",\"from\":\"edges\",\"key\":[\"edge_id\"],\"source\":{\"definition\":\"N\",\"key\":[\"tenant\",\"src\"],\"references_key\":" +
      reference +
      "},\"target\":{\"definition\":\"N\",\"key\":[\"tenant\",\"dst\"]}}]}"
    assert_true(
      checked_property_fixture(body)
      is Err({ kind: InvalidConstructionIdentity, .. }),
    )
  }
  let incompatible =
    #|{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"]}],"edges":[{"name":"E","from":"edges","key":["edge_id"],"source":{"definition":"N","key":["name"]},"target":{"definition":"N","key":["dst"]}}]}
  assert_true(
    checked_property_fixture(incompatible)
    is Err({ kind: InvalidConstructionIdentity, .. }),
  )
}

///|
test "label property aliases cannot silently replace another source column" {
  let body =
    #|{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"A","properties":{"mode":"columns","columns":[{"from":"id","to":"key"}]}},{"name":"B","properties":{"mode":"columns","columns":[{"from":"src","to":"KEY"}]}}]}],"edges":[]}
  assert_true(
    checked_property_fixture(body)
    is Err({ kind: DuplicateConstructionField(_), .. }),
  )
  let body =
    #|{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"A","properties":{"mode":"all_columns_except","except":["tenant","id","edge_id","src","dst"]}}]}],"edges":[]}
  let checked = checked_property_fixture(body).unwrap()
  let element = @graph_typing.construction_node_at(checked, 0).unwrap()
  assert_eq(@graph_typing.graph_element_properties(element), [
    (Unqualified("name"), Unqualified("name")),
  ])
}

///|
test "shared constructor budget includes definition validation and is exact at its reported boundary" {
  let at = cursor(property_fixture_constructor())
  let inputs = [
    ("nodes", property_fixture_rows()),
    ("edges", property_fixture_rows()),
  ]
  let checked = @graph_typing.check_graph_construction(
    at,
    inputs,
    property_fixture_domain(),
    limits(),
  ).unwrap()
  let used = @graph_typing.construction_usage(checked)
  let exact = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    @graph_typing.check_graph_construction(
      at,
      inputs,
      property_fixture_domain(),
      exact,
    )
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(
      @graph_typing.check_graph_construction(
        at,
        inputs,
        property_fixture_domain(),
        cap,
      )
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}
