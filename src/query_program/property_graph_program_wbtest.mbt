///|
fn mapping_limits() -> Limits {
  let source : @builder.Limits = {
    source: { max_input_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    tree: {
      max_nodes: 10000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 100000,
    },
    max_origin_entries: 20000,
    max_output_bytes: 100000,
  }
  {
    source,
    program: { source: source.source, tree: source.tree, max_stages: 20, },
    max_expression_work: 10000,
    max_join_output_rows: 1000L,
    max_collection_items: 1000L,
    max_collection_bytes: 10000L,
  }
}

///|
fn mapping_syntax_limits() -> @query.QueryLimits {
  let lexical : @query.LexicalLimits = {
    max_source_bytes: 10000,
    max_tokens: 1000,
    max_literal_bytes: 10000,
    max_work: 20000,
  }
  {
    lexical,
    expression: { lexical, max_nodes: 1000, max_depth: 100, max_work: 10000, },
    max_syntax_nodes: 1000,
    max_cte_count: 20,
    max_work: 20000,
  }
}

///|
fn mapping_context() -> Context {
  {
    program_id: "fixture.query_pair",
    stage_id: "main",
    stage_result: "rows",
    result_name: "answer",
    captured_stage: None,
    parameter_declarations: None,
    inputs: [],
  }
}

///|
fn mapping_semantic(program : @program.Program) -> String raise {
  let writer = @encode.writer(100000, 10000, 100)
  @program.emit_metadata_stripped_program(program, writer)
  @encode.finish(writer)
}

///|
fn mapping_issue(result : Result[@program.Program, Issue]) -> String {
  match result {
    Err(UnknownRelation) => "UnknownRelation"
    Err(AmbiguousRelation) => "AmbiguousRelation"
    Err(UnknownColumn) => "UnknownColumn"
    Err(AmbiguousColumn) => "AmbiguousColumn"
    Err(UnsupportedGraph) => "UnsupportedGraph"
    Err(_) => "OtherIssue"
    Ok(_) => "Accepted"
  }
}

///|
fn property_input(
  name : String,
  fields : Array[String],
  body : String,
) -> Input {
  let at = @wire.admit(
    @source.parse_json(body, mapping_limits().source.source).unwrap(),
    mapping_limits().source.tree,
  ).unwrap()
  {
    relation: [{ value: name, quoted: false, }],
    name,
    source: GeneratedValues(at),
    visible_fields: fields,
    graph_bindings: [],
  }
}

///|
fn property_mapping_program(
  text : String,
  known : Array[Input],
) -> Result[@program.Program, Issue] {
  let mapping = @query.parse_property_graph(text, mapping_syntax_limits()).unwrap()
  let document = @origin.document(text, 10000).unwrap()
  let generated = @origin.range(document, mapping.start, mapping.end).unwrap()
  let builder = @builder.create(document, mapping_limits().source).unwrap()
  let construction : Construction = { builder, generated, }
  try {
    let steps : Array[@builder.Node] = []
    for input in known {
      guard input.source is GeneratedValues(at) else {
        raise Abort(InvalidContext)
      }
      steps.push(import_query_cursor(construction, at))
    }
    steps.push(lower_property_graph_step(construction, mapping, known, "g"))
    steps.push(
      construction.object([
        ("from", construction.text("g")),
        (
          "match_edges",
          construction.object([
            ("definition", construction.text("E")),
            ("label", construction.text("R")),
            ("where", construction.text("key > 0")),
            ("fields", construction.array([construction.text("key")])),
          ]),
        ),
        ("as", construction.text("matched")),
      ]),
    )
    let stage = construction.object([
      ("id", construction.text("main")),
      ("inputs", construction.object([])),
      ("steps", construction.array(steps)),
      (
        "results",
        construction.object([
          (
            "rows",
            construction.object([
              ("from", construction.text("matched")),
              ("fields", construction.array([construction.text("key")])),
            ]),
          ),
        ]),
      ),
    ])
    let root = program_root(
      construction,
      { ..mapping_context(), inputs: [], },
      [stage],
    )
    let source = @builder.finish(builder, root)
    match source {
      Err(issue) => raise Abort(Construction(issue))
      Ok(source) =>
        match
          @program.admit_generated_source(source, mapping_limits().program) {
          Ok(program) => Ok(program)
          Err(issue) => Err(Admission(issue))
        }
    }
  } catch {
    Abort(issue) => {
      @builder.discard(builder)
      Err(issue)
    }
  }
}

///|
fn property_mapping_inputs() -> Array[Input] {
  [
    property_input(
      "nodes",
      ["id"],
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"}
      ),
    ),
    property_input(
      "edges",
      ["key", "src", "dst"],
      (
        #|{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1},{"key":11,"src":1,"dst":1}]},"as":"edges"}
      ),
    ),
  ]
}

///|
fn mapping_resolved_name(
  path : Array[@query.NamePart],
  known : Array[Input],
) -> String {
  property_mapping_input(path, known).name catch {
    Abort(UnknownRelation) => "UnknownRelation"
    Abort(AmbiguousRelation) => "AmbiguousRelation"
    Abort(_) => "OtherIssue"
  }
}

///|
test "Property Graph producer references use the shared query name rules" {
  // Values-backed relation inputs use the same path rule as published
  // Source Views. A quoted path is exact; DATA bindings are aliases instead.
  let relation = property_mapping_inputs()[0]
  for
    (name, quoted, expected) in [
      ("nodes", false, "nodes"),
      ("NODES", false, "nodes"),
      ("nodes", true, "nodes"),
      ("NODES", true, "UnknownRelation"),
    ] {
    assert_eq(
      mapping_resolved_name([{ value: name, quoted, }], [relation]),
      expected,
    )
  }
  let data = {
    ..relation,
    relation: [{ value: "n", quoted: true, }],
    name: "aql_data_0",
    source: StepReference,
  }
  for (name, quoted) in [("n", false), ("N", false), ("n", true), ("N", true)] {
    assert_eq(
      mapping_resolved_name([{ value: name, quoted, }], [data]),
      "aql_data_0",
    )
  }
  let other = {
    ..relation,
    relation: [{ value: "NODES", quoted: false, }],
    name: "other_nodes",
  }
  assert_eq(
    mapping_resolved_name([{ value: "nodes", quoted: false, }], [
      relation, other,
    ]),
    "AmbiguousRelation",
  )
  assert_eq(
    mapping_resolved_name([{ value: "nodes", quoted: true, }], [relation, other]),
    "nodes",
  )
  let repeated_data = {
    ..data,
    relation: [{ value: "N", quoted: false, }],
    name: "aql_data_1",
  }
  assert_eq(
    mapping_resolved_name([{ value: "n", quoted: true, }], [data, repeated_data]),
    "AmbiguousRelation",
  )
  let qualified = {
    ..relation,
    relation: [
      { value: "dataset", quoted: false, },
      { value: "nodes", quoted: false, },
    ],
  }
  assert_eq(
    mapping_resolved_name(
      [{ value: "DATASET", quoted: false, }, { value: "nodes", quoted: true, }],
      [qualified],
    ),
    "nodes",
  )
  assert_eq(
    mapping_resolved_name(
      [{ value: "dataset", quoted: true, }, { value: "NODES", quoted: true, }],
      [qualified],
    ),
    "UnknownRelation",
  )
}

///|
test "Property Graph mapping lowers to an independent keyed Program" {
  let text = "PROPERTY GRAPH (NODE TABLES (`nodes` AS N KEY (`ID`) LABEL Node PROPERTIES (id)) EDGE TABLES (edges AS E KEY (key) SOURCE KEY (src) REFERENCES `n` (`id`) DESTINATION KEY (dst) REFERENCES N LABEL R PROPERTIES ARE ALL COLUMNS EXCEPT (src, dst)))"
  let program = property_mapping_program(text, property_mapping_inputs()).unwrap()
  // Written from the adopted mapping contract: no domain, Result, sort,
  // acquisition or storage is invented by the constructor lowering.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"values":{"schema":{"key":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"key":10,"src":1,"dst":1},{"key":11,"src":1,"dst":1}]},"as":"edges"},{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"}]}}]}],"edges":[{"name":"E","from":"edges","key":["key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"R","properties":{"mode":"all_columns_except","except":["src","dst"]}}]}]},"as":"g"},{"from":"g","match_edges":{"definition":"E","label":"R","where":"key > 0","fields":["key"]},"as":"matched"}],"results":{"rows":{"from":"matched","fields":["key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    mapping_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(mapping_semantic(program), mapping_semantic(expected))
}

///|
test "Property Graph references resolve element definitions separately" {
  let base = "PROPERTY GRAPH (NODE TABLES (nodes AS N KEY (id) NO PROPERTIES) EDGE TABLES (edges AS E KEY (key) SOURCE KEY (src) REFERENCES "
  for
    (name, expected) in [
      ("nodes", "UnknownRelation"),
      ("Node", "UnknownRelation"),
    ] {
    assert_eq(
      mapping_issue(
        property_mapping_program(
          base + name + " DESTINATION KEY (dst) REFERENCES N NO PROPERTIES))",
          property_mapping_inputs(),
        ),
      ),
      expected,
    )
  }
  let valid = property_mapping_program(
    base + "n DESTINATION KEY (dst) REFERENCES `N` NO PROPERTIES))",
    property_mapping_inputs(),
  ).unwrap()
  assert_true(mapping_semantic(valid).contains("\"mode\":\"no_properties\""))
  assert_true(!mapping_semantic(valid).contains("\"domain\""))
}

///|
test "Property Graph rejects unresolved ambiguous and non-key mapping" {
  for
    (text, expected) in [
      (
        "PROPERTY GRAPH (NODE TABLES (missing AS N KEY (id)))", "UnknownRelation",
      ),
      (
        "PROPERTY GRAPH (NODE TABLES (nodes AS N KEY (missing)))", "UnknownColumn",
      ),
      (
        "PROPERTY GRAPH (NODE TABLES (nodes AS N KEY (id), nodes AS `n` KEY (id)))",
        "AmbiguousRelation",
      ),
      (
        "PROPERTY GRAPH (NODE TABLES (nodes AS N KEY (id)) EDGE TABLES (edges AS E KEY (key) SOURCE KEY (src) REFERENCES N (missing) DESTINATION KEY (dst) REFERENCES N))",
        "UnknownColumn",
      ),
    ] {
    assert_eq(
      mapping_issue(property_mapping_program(text, property_mapping_inputs())),
      expected,
    )
  }
  let both = property_mapping_inputs()
  both.push({ ..both[0], relation: [{ value: "NODES", quoted: false, }], })
  assert_eq(
    mapping_issue(
      property_mapping_program(
        "PROPERTY GRAPH (NODE TABLES (nodes AS N KEY (id)))", both,
      ),
    ),
    "AmbiguousRelation",
  )
  let fields = property_mapping_inputs()
  fields[0] = property_input(
    "nodes",
    ["id", "ID"],
    (
      #|{"values":{"schema":{"id":{"type":"number","nullable":false},"ID":{"type":"number","nullable":false}},"rows":[{"id":1,"ID":2}]},"as":"nodes"}
    ),
  )
  assert_eq(
    mapping_issue(
      property_mapping_program(
        "PROPERTY GRAPH (NODE TABLES (nodes AS N KEY (id)))", fields,
      ),
    ),
    "AmbiguousColumn",
  )
}

///|
test "DATA Relation binds an existing step without a materialization boundary" {
  let script = @query.parse_query_script(
    "DATA n = SELECT 2 AS id; FROM `N` |> SELECT id",
    mapping_syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    mapping_context(),
    mapping_limits(),
  ).unwrap()
  // The DATA output reserves the first producer slot before its Values seed.
  // The existing collision allocator therefore assigns seed slot 1.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","derive":{"aql_query_expr_0":{"literal":2}}},{"select":[{"id":"aql_query_expr_0"}],"as":"aql_data_0"},{"from":"aql_data_0","select":["id"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    mapping_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(mapping_semantic(program), mapping_semantic(expected))
  assert_eq(@program.stage_count(program), 1)
  assert_eq(@program.export_count(program), 1)
}

///|
test "DATA Relation rejects forward references without substituting a source" {
  for
    text in [
      "DATA n = FROM m |> SELECT id; DATA m = SELECT 1 AS id; FROM n |> SELECT id",
      "DATA n = FROM n |> SELECT id; FROM n |> SELECT id",
    ] {
    let script = @query.parse_query_script(text, mapping_syntax_limits()).unwrap()
    assert_eq(
      mapping_issue(
        compile_query_script(script, mapping_context(), mapping_limits()),
      ),
      "UnknownRelation",
    )
  }
  let script = @query.parse_query_script(
    "DATA n = SELECT 1 AS id; DATA m = FROM `N` |> SELECT id; FROM m |> SELECT id",
    mapping_syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    mapping_context(),
    mapping_limits(),
  ).unwrap()
  let body = mapping_semantic(program)
  assert_eq(@program.stage_count(program), 1)
  assert_eq(body.split("\"values\"").length(), 2)
  let unowned = {
    ..mapping_context(),
    inputs: [
      {
        relation: [{ value: "n", quoted: false, }],
        name: "unowned",
        source: StepReference,
        visible_fields: ["id"],
        graph_bindings: [],
      },
    ],
  }
  let query = @query.parse_query("FROM n |> SELECT id", mapping_syntax_limits()).unwrap()
  assert_true(compile(query, unowned, mapping_limits()) is Err(InvalidContext))
}
