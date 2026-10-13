///|
// This freezes an unresolved installed-Source boundary, not successful public
// Vector acceptance. A local schema control supplies no implicit key or order.
fn vector_source_order_context(keyed : Bool) -> Context {
  let schema =
    #|{"id":{"type":"number","nullable":false},"left_vector":{"type":"vector","dimensions":2,"nullable":false},"right_vector":{"type":"vector","dimensions":2,"nullable":true}}
  let declaration = @wire.admit(
    @source.parse_json(
      "{\"carrier\":\"relation\",\"schema\":" +
      schema +
      (if keyed { ",\"primary_key\":[\"id\"]" } else { "" }) +
      "}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    captured_stage: Some("capture"),
    inputs: [
      {
        relation: [{ value: "vectors", quoted: false, }],
        name: "vectors",
        source: Captured(declaration),
        visible_fields: ["id", "left_vector", "right_vector"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn vector_source_projection_control(expression : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.vector_source_projection","stages":[{"id":"capture","inputs":{"vectors":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false},"left_vector":{"type":"vector","dimensions":2,"nullable":false},"right_vector":{"type":"vector","dimensions":2,"nullable":true}}}},"steps":[{"from":"vectors","filter":{"literal":true}},{"select":["id","left_vector","right_vector"],"as":"captured"},{"from":"captured","derive":{"value":
    ) +
    expression +
    (
      #|}},{"select":["id","value"],"as":"scalar_capture"}],"results":{"source":{"from":"scalar_capture","fields":["id","value"]}}},{"id":"main","inputs":{"vectors":{"result":{"stage":"capture","result":"source"}}},"steps":[{"from":"vectors","sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Source scalar projection precedes intermediate publication without inventing a key" {
  for (name, expression) in vector_scalar_expressions() {
    if name == "VECTOR_CONCAT" {
      continue
    }
    let text = "SELECT id, " +
      name +
      "(left_vector,right_vector) AS value FROM vectors ORDER BY id"
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      vector_source_order_context(false),
      construction_limits(),
    ).unwrap()
    guard @json.parse(with_carrier_argument(program, "derive"))
      is Object(fields) else {
      fail("one derived scalar object")
    }
    assert_eq(fields.length(), 1)
    for (_, value) in fields {
      assert_eq(value, @json.parse(expression))
    }
    for
      checked_program in [program, vector_source_projection_control(expression)] {
      match
        @check.check_parsed(
          checked_program,
          check_environment(veca=true),
          None,
          check_limits(),
        ) {
        Checked(checked) => {
          let schema = @pipeline.output_schema(
            @check.unit_pipeline(checked, 1).unwrap(),
          ).unwrap()
          assert_eq(@schema.field_reference_name_at(schema, 0), Some("id"))
          assert_eq(@schema.field_reference_name_at(schema, 1), Some("value"))
          assert_eq(
            @contract.stringify_checked(
              @schema.lookup(schema, Unqualified("value")).unwrap(),
              1000,
              100,
              10,
            ),
            "{\"nullable\":true,\"type\":\"number\"}",
          )
        }
        Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
        NeedsInputs(_) => fail("typed local control has no unresolved values")
      }
    }
    // The original filter/select acquisition port remains before evaluation.
    assert_true(
      semantic(program).contains(
        "\"select\":[\"id\",\"left_vector\",\"right_vector\"]",
      ),
    )
    assert_true(semantic(program).contains("\"as\":\"aql_capture_0\""))
  }
}

///|
test "Source Vector output still rejects absent publication order evidence" {
  let program = compile(
    @query.parse_query(
      "SELECT id, VECTOR_CONCAT(left_vector,right_vector) AS value FROM vectors ORDER BY id",
      syntax_limits(),
    ).unwrap(),
    vector_source_order_context(false),
    construction_limits(),
  ).unwrap()
  guard @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    )
    is Rejected(diagnostic) else {
    fail("Vector output still needs an authoritative order witness")
  }
  guard @check.diagnostic_cause(diagnostic)
    is Source(SourceView(Program(Program(Order(0, ResultOrder(issue)))))) else {
    raise @check.diagnostic_cause(diagnostic)
  }
  assert_eq(issue.kind, @relation_results.UnresolvedOrder)
  assert_eq(@wire.cursor_path(issue.source), [
    Key("stages"),
    Index(0),
    Key("results"),
    Key("source"),
  ])
}

///|
test "an explicitly declared local key distinguishes admitted Vector capture order" {
  // This positive control is not a replacement for the installed SourceView.
  // Local key declaration is authoritative only for this separate local input.
  for (name, _) in vector_scalar_expressions() {
    let program = compile(
      @query.parse_query(
        "SELECT id, " +
        name +
        "(left_vector,right_vector) AS value FROM vectors ORDER BY id",
        syntax_limits(),
      ).unwrap(),
      vector_source_order_context(true),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      NeedsInputs(_) => fail("the separate typed local key control is complete")
    }
  }
}
