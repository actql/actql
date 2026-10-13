///|
fn calendar_source_selected() -> @environment.SelectedCalendarProfile {
  let wire = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe","host_policy_profile":{"calendar":{"conversion_law":"actql-calendar-boundaries/0.1","table_bytes_cid":"sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca","tzdb_version":"test-fixture","version":"actql-calendar-selection/0.1"},"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":1000,"max_analytic_input_wire_bytes":1000,"max_analytic_output_wire_bytes":1000,"max_analytic_partition_wire_bytes":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_construction_edges":1000,"max_graph_construction_input_rows":1000,"max_graph_construction_nodes":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      ),
    ),
    "sha256:eaa253817c6be7a3e1141487b87b702bfa23052afe190461db6c83369bd13ffe",
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  ).unwrap()
  @environment.admit_calendar_profile(
    @environment.read_calendar_selection(wire, 10000).unwrap(),
    @utf8.encode(
      (
        #|{"conversion_law":"actql-calendar-boundaries/0.1","coverage_end_ms":253402300800000,"coverage_start_ms":-62135596800000,"tzdb_version":"test-fixture","version":"actql-tzdb-table/0.1","zones":{"UTC":{"initial_offset_seconds":0,"transitions":[]}}}
      ),
    ),
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
}

///|
fn calendar_source_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.calendar_source","stages":[{"id":"main","inputs":{},"steps":[{"calendar_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-03T00:00:00.000Z","unit":"day","timezone":"UTC"},"as":"days"},{"calendar_bucket":{"time":"start","into":"month","unit":"month","timezone":"UTC"},"as":"bucketed"},{"from":"bucketed","sort":[{"field":"start","dir":"asc","nulls":"first"}]},{"select":["start","end","month"],"as":"out"}],"results":{"rows":{"from":"out","fields":["start","end","month"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent Calendar Program uses the existing selected common profile" {
  let source = @stage_parameters.prepare(calendar_source_control(), {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let profile = @environment.selected_calendar_profile(
    calendar_source_selected(),
  )
  assert_true(
    @stage_results.prepare_local_program(
      source,
      {
        max_stages: 10,
        max_steps: 100,
        max_results: 100,
        max_work: 1000000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
        max_text_bytes: 100000,
      },
      calendar_profile=Some(profile),
    )
    is Ok(_),
  )
}

///|
test "adopted Calendar series is a normal Relation generator primary" {
  let query = calendar_source_query(
    "WITH days AS (calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-03T00:00:00.000Z',unit:'day',timezone:'UTC')) SELECT start,`end` FROM days ORDER BY start",
  )
  assert_true(
    @query.producer_primary(@query.query_binding_at(query, 0).unwrap().query)
    is Some(RelationGenerator(_)),
  )
}

///|
test "adopted Calendar bucket preserves field and authored output-name roles" {
  let call = @query.parse_sga_call(
    "calendar_bucket(time:r.start,unit:'month',timezone:'UTC',into:`SELECT`)",
    syntax_limits(),
  ).unwrap()
  assert_true(call.arguments[0].1 is FieldReference([_, _]))
  assert_true(
    call.arguments[3].1 is OutputName({ value: "SELECT", quoted: true, }),
  )
}

///|
fn calendar_source_checked(
  program : @program.Program,
  profile : @environment.SelectedCalendarProfile,
) -> @check.CheckedProgram raise {
  let environment = @check.checking_environment(
    @environment.calendar_selection_environment(
      @environment.selected_calendar_selection(profile),
    ),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: true, text_rank: false, },
    numeric_profile=Some(@numeric.builtin_profile()),
    calendar=Some(profile),
  )
  match @check.check_parsed(program, environment, None, check_limits()) {
    Checked(checked) => checked
    Rejected(issue) => {
      graph_rows_rejected(issue)
      fail("Calendar common checked Program")
    }
    NeedsInputs(_) => fail("literal Calendar control has no external inputs")
  }
}

///|
fn calendar_source_lower(
  text : String,
  profile : @environment.SelectedCalendarProfile,
) -> @program.Program raise {
  compile_query_script(
    calendar_source_script(text),
    { ..pair_context(), inputs: [], calendar_profile: Some(profile), },
    construction_limits(),
  ).unwrap()
}

///|
test "Calendar text reaches unchanged series and bucket operation bodies" {
  let profile = calendar_source_selected()
  let actual = calendar_source_lower(
    "WITH days AS (calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-03T00:00:00.000Z',unit:'day',timezone:'UTC')) FROM days AS d |> calendar_bucket(time:d.start,unit:'month',timezone:'UTC',into:month) |> SELECT start,`end`,month |> ORDER BY start",
    profile,
  )
  let expected = calendar_source_control()
  for op in ["calendar_series", "calendar_bucket"] {
    assert_eq(
      @json.parse(with_carrier_argument(actual, op)),
      @json.parse(with_carrier_argument(expected, op)),
    )
  }
  let schemas = [actual, expected].map(program => {
    let checked = calendar_source_checked(program, profile)
    let stage = @stage_results.stage_at(
      @check.checked_stage_results(checked),
      0,
    ).unwrap()
    let result = @relation_results.lookup(stage, "rows").unwrap()
    assert_eq(@relation_results.fields(result), ["start", "end", "month"])
    let fields = @schema.fields(@relation_results.output_schema(result))
    assert_eq(fields.map(@schema.field_reference_name), [
      "end", "month", "start",
    ])
    for field in fields {
      assert_true(field.presence is Required)
      assert_false(field.contract.nullable)
      if @schema.field_reference_name(field) == "month" {
        guard field.contract.shape is @contract.Object(members) else {
          fail("month is a closed boundary object")
        }
        assert_eq(@contract.fields(members).map(member => member.name), [
          "end", "start",
        ])
        for member in @contract.fields(members) {
          assert_false(member.contract.nullable)
          assert_true(member.contract.shape is @contract.Timestamp)
        }
      } else {
        assert_true(field.contract.shape is @contract.Timestamp)
      }
    }
    fields
  })
  for index in 0..<schemas[0].length() {
    assert_true(
      @contract.type_equal(
        schemas[0][index].contract,
        schemas[1][index].contract,
        10000,
      ),
    )
  }
}

///|
test "Calendar missing profile remains an explicit common refusal" {
  let text = "WITH days AS (calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-03T00:00:00.000Z',unit:'day',timezone:'UTC')) SELECT start,`end` FROM days"
  guard compile_query_script(
      calendar_source_script(text),
      { ..pair_context(), inputs: [], },
      construction_limits(),
    )
    is Err(
      BindingPreparation(
        LocalProgram(Pipeline(_, { kind: Calendar(MissingProfile), .. }))
      )
    ) else {
    fail("Calendar source must not choose an ambient or default profile")
  }
}

///|
test "Calendar generator placement and bucket output-name checks remain static" {
  for
    text in [
      "WITH rows AS (SELECT 1 AS id) FROM rows |> calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-03T00:00:00.000Z',unit:'day',timezone:'UTC')",
      "WITH days AS (calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-03T00:00:00.000Z',unit:'day',timezone:'UTC')) FROM days |> calendar_bucket(time:start,unit:'month',timezone:'UTC',into:SELECT)",
    ] {
    assert_true(
      @query.parse_query_script(text, syntax_limits())
      is Err({ issue: Syntax(_), .. }),
    )
  }
}

///|
fn calendar_source_query(text : String) -> @query.Query raise {
  match @query.parse_query(text, syntax_limits()) {
    Ok(query) => query
    Err(issue) => fail("Calendar syntax: " + @debug.to_string(issue.issue))
  }
}

///|
fn calendar_source_script(text : String) -> @query.QueryScript raise {
  match @query.parse_query_script(text, syntax_limits()) {
    Ok(script) => script
    Err(issue) => fail("Calendar syntax: " + @debug.to_string(issue.issue))
  }
}

///|
test "Calendar source context retains the exact selection and rejects foreign Catalog owners" {
  let selected = calendar_source_selected()
  let wire = @environment.calendar_selection_environment(
    @environment.selected_calendar_selection(selected),
  )
  let environment = @check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: true, calendar: true, text_rank: false, },
    calendar=Some(selected),
  )
  assert_true(
    physical_equal(
      @check.checking_environment_calendar_profile(environment).unwrap(),
      selected,
    ),
  )
  let catalog = @check.source_catalog_contracts(
    @check.prepare_source_catalog(environment, {
      max_work: 1000000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap(),
  )
  let context = @frontend.bind_query_context(
    [],
    @environment.cid(wire),
    source_catalog=Some(catalog),
    calendar_profile=Some(selected),
  ).unwrap()
  assert_true(physical_equal(context.calendar_profile.unwrap(), selected))
  let publication = "{\"environmentCid\":\"" +
    @environment.cid(wire) +
    "\",\"aliases\":[],\"tableWrites\":[]}"
  let published = @source_publication.bind_published_query_context(
    environment,
    publication,
    None,
  ).unwrap()
  assert_true(physical_equal(published.calendar_profile.unwrap(), selected))
  let text = "WITH days AS (calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-03T00:00:00.000Z',unit:'day',timezone:'UTC')) SELECT start,`end` FROM days ORDER BY start"
  let actual = @frontend.lower(text, Sql, Some(context)).unwrap().program.unwrap()
  calendar_source_checked(actual, selected) |> ignore
  let published_actual = @frontend.lower(text, Sql, Some(published)).unwrap().program.unwrap()
  calendar_source_checked(published_actual, selected) |> ignore
  let local_context = @local_preparation.bind_local_input_context(
    environment,
    [],
    "fixture.calendar_source",
  ).unwrap()
  // This is a real common preparation boundary, not an installed Run. The
  // existing physical lowerer has no Calendar payload; keep that refusal
  // separate from the now-connected source/checker and profile ownership.
  assert_true(
    @local_preparation.prepare_local_input(
      @local_preparation.Aql(text),
      environment,
      None,
      Some(local_context),
      @publication_host.client_standard_program_preparation_limits(),
    )
    is Err(
      Preparation(
        @publication_host.Lowering({ kind: OperationNotImplemented, .. })
      )
    ),
  )
  assert_true(
    @frontend.bind_query_context(
      [],
      "sha256:" + "0".repeat(64),
      calendar_profile=Some(selected),
    )
    is Err(EnvironmentMismatch),
  )
  // Fresh admission of identical bytes is not the same environment owner.
  let foreign = calendar_source_selected()
  assert_eq(
    @environment.cid(
      @environment.calendar_selection_environment(
        @environment.selected_calendar_selection(foreign),
      ),
    ),
    @environment.cid(wire),
  )
  assert_true(
    @frontend.bind_query_context(
      [],
      @environment.cid(wire),
      source_catalog=Some(catalog),
      calendar_profile=Some(foreign),
    )
    is Err(EnvironmentMismatch),
  )
}

///|
test "Calendar empty and week signatures preserve exact authored arguments" {
  let selected = calendar_source_selected()
  for
    (unit, extra) in [
      ("day", ""),
      ("week", ",week_start:'monday'"),
      ("week", ",week_start:'sunday'"),
    ] {
    let actual = calendar_source_lower(
      "WITH days AS (calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-01T00:00:00.000Z',unit:'" +
      unit +
      "',timezone:'UTC'" +
      extra +
      ")) SELECT start,`end` FROM days ORDER BY start",
      selected,
    )
    let expected = "{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.000Z\",\"unit\":\"" +
      unit +
      "\",\"timezone\":\"UTC\"" +
      (if extra.contains("monday") {
        ",\"week_start\":\"monday\""
      } else if extra.contains("sunday") {
        ",\"week_start\":\"sunday\""
      } else {
        ""
      }) +
      "}"
    assert_eq(
      @json.parse(with_carrier_argument(actual, "calendar_series")),
      @json.parse(expected),
    )
    calendar_source_checked(actual, selected) |> ignore
  }
}

///|
test "Calendar literal-only selectors and timestamp domains keep common refusals" {
  let selected = calendar_source_selected()
  for
    options in [
      "unit:'week',timezone:'UTC'", "unit:'day',timezone:'UTC',week_start:'monday'",
      "unit:'day',timezone:'utc'", "unit:'fortnight',timezone:'UTC'", "unit:NULL,timezone:'UTC'",
    ] {
    let result = compile_query_script(
      calendar_source_script(
        "WITH days AS (calendar_series(start:'2000-01-01T00:00:00.000Z',end:'2000-01-03T00:00:00.000Z'," +
        options +
        ")) SELECT start,`end` FROM days",
      ),
      { ..pair_context(), inputs: [], calendar_profile: Some(selected), },
      construction_limits(),
    )
    assert_true(
      result
      is Err(
        BindingPreparation(LocalProgram(Pipeline(_, { kind: Calendar(_), .. })))
      ),
    )
  }
  let numeric = compile_query_script(
    calendar_source_script(
      "WITH rows AS (SELECT 1 AS clock) FROM rows |> calendar_bucket(time:clock,unit:'day',timezone:'UTC',into:bucket) |> SELECT bucket",
    ),
    { ..pair_context(), inputs: [], calendar_profile: Some(selected), },
    construction_limits(),
  )
  assert_true(
    numeric
    is Err(
      BindingPreparation(LocalProgram(Pipeline(_, { kind: Calendar(_), .. })))
    ),
  )
}

///|
test "Calendar endpoints retain non-null whole timestamp Parameters" {
  let selected = calendar_source_selected()
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"begin\":{\"type\":\"timestamp\",\"nullable\":false},\"finish\":{\"type\":\"timestamp\",\"nullable\":false}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 128, max_depth: 16, max_text_bytes: 4096, },
  ).unwrap()
  let actual = with_carrier_program(
    "WITH days AS (calendar_series(start:@BEGIN,end:@finish,unit:'day',timezone:'UTC')) SELECT start,`end` FROM days ORDER BY start",
    {
      ..pair_context(),
      inputs: [],
      calendar_profile: Some(selected),
      parameter_declarations: Some(declarations),
    },
  ).unwrap()
  assert_eq(
    @json.parse(with_carrier_argument(actual, "calendar_series")),
    @json.parse(
      "{\"start\":{\"$param\":\"begin\"},\"end\":{\"$param\":\"finish\"},\"unit\":\"day\",\"timezone\":\"UTC\"}",
    ),
  )
}
