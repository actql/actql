///|
fn field_projection_capture_context() -> Context {
  let declaration = @wire.admit(
    @source.parse_json(
      (
        #|{"carrier":"relation","schema":{"Id":{"type":"string","nullable":false},"Name":{"type":"string","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"city":{"type":"string","nullable":true}}}}}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..fixture_context(),
    captured_stage: Some("capture"),
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "records",
        source: Captured(declaration),
        visible_fields: ["Id", "Name", "payload"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "captured field projection does not publish an unselected structured column" {
  let actual = compile(
    @query.parse_query(
      "SELECT r.Id AS Id, r.Name AS previous_name FROM records AS r WHERE r.Id = 'selected'",
      syntax_limits(),
    ).unwrap(),
    field_projection_capture_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_true(body.contains("\"fields\":[\"Id\",\"previous_name\"]"))
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("a projected scalar Result has no unresolved order")
  }
}

///|
test "captured parameter projection retains its one original declaration" {
  let actual = compile(
    @query.parse_query(
      "SELECT r.Id AS Id, @p AS next_value FROM records AS r WHERE r.Id = 'selected'",
      syntax_limits(),
    ).unwrap(),
    {
      ..field_projection_capture_context(),
      parameter_declarations: Some(number_parameter_declarations()),
    },
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_eq(body.split("\"$param\":\"p\"").length(), 2)
  assert_true(body.contains("\"fields\":[\"Id\",\"next_value\"]"))
  match
    @check.check_parsed(
      actual,
      check_environment(),
      Some(analytic_frame_parameter_values("1")),
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the same supplied Parameter remains bound")
  }
  // The existing Direct Source corpus supplies real request/mode originals;
  // a schema-only Source cannot establish this acquisition contract.
  let direct_context = {
    ..chain_right_context(direct=true, captured=true, parameters=false),
    parameter_declarations: Some(number_parameter_declarations()),
  }
  let direct = compile_query_script(
    @query.parse_query_script(
      "SELECT r.id AS id, @p AS next_value FROM remote AS r WHERE r.id = 1 |> RESULT rows",
      syntax_limits(),
    ).unwrap(),
    direct_context,
    construction_limits(),
  ).unwrap()
  let prepared = @publication_host.prepare_parsed_effect_free_client_program(
    direct,
    @check.checking_environment(
      chain_right_wire(host_capacity=true),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    ),
    Some(analytic_frame_parameter_values("1")),
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let acquisition = @publication_host.prepare_client_query_acquisition(
    prepared, 0, 0,
  ).unwrap()
  assert_eq(
    @schema.field_count(
      @relation.input_schema(
        @source_resolution.query_acquisition_filter(acquisition),
      ),
    ),
    2,
  )
  assert_eq(
    @schema.field_count(
      @relation.output_schema(
        @source_resolution.query_acquisition_select(acquisition),
      ),
    ),
    1,
  )
}

///|
test "captured structured publication still requires a real order witness" {
  let actual = compile(
    @query.parse_query("SELECT payload FROM records", syntax_limits()).unwrap(),
    field_projection_capture_context(),
    construction_limits(),
  ).unwrap()
  guard @check.check_parsed(actual, check_environment(), None, check_limits())
    is Rejected(issue) else {
    fail("projection cannot make an object CanonicalOrderable")
  }
  guard @check.diagnostic_cause(issue)
    is Source(SourceView(Program(Program(Order(0, ResultOrder(order)))))) else {
    raise @check.diagnostic_cause(issue)
  }
  assert_true(order.kind is UnresolvedOrder)
}

///|
test "later projections and function calls keep their original capture placement" {
  for
    text in [
      "FROM records |> SELECT Id, payload |> SELECT Id", "SELECT Id, LOWER(Name) AS name FROM records",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      field_projection_capture_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_true(body.contains("\"fields\":[\"Id\",\"Name\",\"payload\"]"))
    guard @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(issue) else {
      fail("the nonselected placement keeps the original full capture")
    }
    guard @check.diagnostic_cause(issue)
      is Source(SourceView(Program(Program(Order(0, ResultOrder(order)))))) else {
      raise @check.diagnostic_cause(issue)
    }
    assert_true(order.kind is UnresolvedOrder)
  }
}

///|
test "captured original Salesforce UPDATE text retains its scalar Result and Parameters" {
  let context = field_projection_capture_context()
  let input = context.inputs[0]
  let actual = compile(
    @query.parse_query(
      "SELECT r.Id AS Id, r.Name AS previous_name, @next_name AS next_name FROM salesforce.accounts AS r WHERE r.Id = @record_id |> ASSERT UNIQUE BY (Id) |> RESULT updates |> EFFECT UPDATE salesforce.Account ID Id SET (Name = next_name);",
      syntax_limits(),
    ).unwrap(),
    {
      ..context,
      parameter_declarations: Some(
        parameter_reference_declarations(
          "{\"record_id\":{\"type\":\"string\"},\"next_name\":{\"type\":\"string\"}}",
        ),
      ),
      inputs: [
        {
          ..input,
          relation: [
            { value: "salesforce", quoted: false, },
            { value: "accounts", quoted: false, },
          ],
        },
      ],
    },
    construction_limits(),
    update_targets=Some(keyed_record_publication("all")),
  ).unwrap()
  let supplied = @wire.admit(
    @source.parse_json(
      "{\"record_id\":\"selected\",\"next_name\":\"after\"}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let result = @check.prepare_effect_computation_candidate(
    actual,
    keyed_record_environment("all"),
    Some(supplied),
    [],
    check_limits(),
    1,
    1000,
  )
  guard result is Ok(_) else {
    match result {
      Err(
        Computation(
          Source(SourceView(Program(Program(Order(stage, ResultOrder(order))))))
        )
      ) =>
        fail(
          "original UPDATE capture stage " +
          stage.to_string() +
          ": " +
          @debug.to_string(order.kind),
        )
      Err(Computation(issue)) => raise issue
      _ =>
        fail(
          "the complete original UPDATE must reach its same computation owner",
        )
    }
  }
  assert_eq(@program.exports(actual).map(entry => entry.0), ["updates"])
  let capture = @program.stage_body(@program.stages(actual)[0])
  let capture_steps = @wire.elements(store_capture_field(capture, "steps")).unwrap()
  // Keep the existing acquisition Select before the Parameter Derive, but
  // receive only columns used by the selected projection from that Source.
  let acquisition = capture_steps.filter(step => {
      @wire.lookup(@wire.open_object(step).unwrap(), "select") is Some(_)
    })[0]
  assert_eq(
    @wire.elements(store_capture_field(acquisition, "select"))
    .unwrap()
    .map(column => @wire.text(column).unwrap()),
    ["Id", "Name"],
  )
  assert_eq(
    @wire.text(store_capture_field(acquisition, "as")).unwrap(),
    "aql_capture_0",
  )
  assert_eq(
    @wire.text(store_capture_field(capture_steps[0], "from")).unwrap(),
    "records",
  )
  let original = store_capture_field(
    store_capture_field(capture, "inputs"),
    "records",
  )
  let original_schema = store_capture_field(original, "schema")
  assert_eq(@wire.object_length(original_schema), Some(3))
  assert_eq(@wire.field_at(original_schema, 0).unwrap().0, "Id")
  assert_eq(@wire.field_at(original_schema, 1).unwrap().0, "Name")
  assert_eq(@wire.field_at(original_schema, 2).unwrap().0, "payload")
  let body = semantic(actual)
  assert_eq(body.split("\"$param\":\"next_name\"").length(), 2)
  assert_eq(body.split("\"$param\":\"record_id\"").length(), 2)
  assert_true(
    body.contains("\"fields\":[\"Id\",\"previous_name\",\"next_name\"]"),
  )
}

///|
test "captured projection preserves invalid Parameter and construction limit refusal" {
  let query = @query.parse_query(
    "SELECT Id, @p AS next_value FROM records",
    syntax_limits(),
  ).unwrap()
  let context = {
    ..field_projection_capture_context(),
    parameter_declarations: Some(number_parameter_declarations()),
  }
  let actual = compile(query, context, construction_limits()).unwrap()
  assert_true(
    @check.check_parsed(
      actual,
      check_environment(),
      Some(analytic_frame_parameter_values("\"wrong type\"")),
      check_limits(),
    )
    is Rejected(_),
  )
  let limits = construction_limits()
  assert_true(
    compile(query, context, {
      ..limits,
      source: { ..limits.source, max_output_bytes: 1, },
    })
    is Err(Construction(_)),
  )
}

///|
test "LIMIT and OFFSET preserve the original full capture ordering boundary" {
  // Original canonical input order for (Id=1,Name=z),(Id=2,Name=a) is Id,
  // not Name. Moving SELECT Name before that Result would change LIMIT's row.
  for suffix in ["LIMIT 1", "LIMIT 1 OFFSET 1", "ORDER BY Name LIMIT 1"] {
    let actual = compile(
      @query.parse_query("SELECT Name FROM records " + suffix, syntax_limits()).unwrap(),
      field_projection_capture_context(),
      construction_limits(),
    ).unwrap()
    let body = semantic(actual)
    assert_true(body.contains("\"fields\":[\"Id\",\"Name\",\"payload\"]"))
    assert_true(!body.contains("aql_capture_projection_"))
    // This unchanged structured capture remains unorderable rather than
    // silently becoming executable by changing the input seen by LIMIT.
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
    )
  }
}

///|
test "scalar LIMIT retains the complete independently authored original Program" {
  let declaration = @wire.admit(
    @source.parse_json(
      "{\"carrier\":\"relation\",\"schema\":{\"Id\":{\"type\":\"string\",\"nullable\":false},\"Name\":{\"type\":\"string\",\"nullable\":false}}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = field_projection_capture_context()
  let input = context.inputs[0]
  let context = {
    ..context,
    inputs: [
      {
        ..input,
        source: Captured(declaration),
        visible_fields: ["Id", "Name"],
      },
    ],
  }
  for offset in [0, 1] {
    // Full original scalar capture sorts Id before Name. With rows (1,z),
    // (2,a), LIMIT 1 observes z and OFFSET 1 observes a, not the reverse.
    let expected = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"capture\",\"inputs\":{\"records\":{\"carrier\":\"relation\",\"schema\":{\"Id\":{\"type\":\"string\",\"nullable\":false},\"Name\":{\"type\":\"string\",\"nullable\":false}}}},\"steps\":[{\"from\":\"records\",\"select\":[\"Id\",\"Name\"],\"as\":\"aql_capture_0\"}],\"results\":{\"source\":{\"from\":\"aql_capture_0\",\"fields\":[\"Id\",\"Name\"]}}},{\"id\":\"main\",\"inputs\":{\"records\":{\"result\":{\"stage\":\"capture\",\"result\":\"source\"}}},\"steps\":[{\"from\":\"records\",\"select\":[\"Name\"]},{\"take\":{\"count\":1,\"offset\":" +
      offset.to_string() +
      "},\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"Name\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    let actual = compile(
      @query.parse_query(
        "SELECT Name FROM records LIMIT 1 OFFSET " + offset.to_string(),
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    for program in [actual, expected] {
      assert_true(
        @check.check_parsed(program, check_environment(), None, check_limits())
        is Checked(_),
      )
    }
  }
}
