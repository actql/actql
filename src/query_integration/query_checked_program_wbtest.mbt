///|
fn query_checked_program_fixture(
  nullable? : Bool = false,
  catalog? : @environment.SourceRequestContracts? = None,
  dag? : Bool = false,
  dag_count? : Bool = false,
  dag_join? : Bool = false,
  self_join? : Bool = false,
  numeric_dag? : Bool = false,
  sort_take? : Bool = false,
  join_steps? : Array[Int] = [0],
  acquisition_filter? : String = "id > $minimum",
  compute_filter? : String = "id > 2",
  parameter_json? : String = "{\"minimum\":1}",
) -> @program_check.CheckedProgram raise {
  let text =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}}],"results":{"out":{"from":{"stage":"a","result":"r"}}}}
  let text = if dag {
    text.replace(
      old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
      new="},{\"id\":\"compute_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}},{\"id\":\"compute_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id > 0\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}},{\"id\":\"compute_c\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id < 9\"},{\"select\":[\"id\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"id\"]}}}],\"results\":{\"b\":{\"from\":{\"stage\":\"compute_b\",\"result\":\"r\"}},\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}}",
    )
  } else {
    text
  }
  let text = if sort_take {
    text.replace(
      old="{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}",
      new="{\"sort\":[{\"id\":\"desc\"}]},{\"take\":2,\"as\":\"out\"}",
    )
  } else {
    text
  }
  let text = if dag_count {
    text.replace(
      old="{\"filter\":\"id > 2\"},{\"select\":[\"id\"],\"as\":\"out\"}",
      new="{\"group\":{\"by\":[],\"aggregates\":{\"id\":{\"fn\":\"count\"}}},\"as\":\"out\"}",
    )
  } else {
    text
  }
  let text = if dag_join {
    let joined = text.replace(
      old="\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}}},\"steps\":[{\"filter\":\"id < 9\"},{\"select\":[\"id\"],\"as\":\"out\"}]",
      new="\"inputs\":{\"l\":{\"result\":{\"stage\":\"compute_a\",\"result\":\"r\"}},\"r\":{\"result\":{\"stage\":\"" +
        (if self_join { "compute_a" } else { "compute_b" }) +
        "\",\"result\":\"r\"}}},\"steps\":[{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}},\"from\":\"l\",\"as\":\"out\"}]",
    )
    joined.replace(
      old="}],\"results\":{\"b\":{\"from\":{\"stage\":\"compute_b\",\"result\":\"r\"}},\"c\":{\"from\":{\"stage\":\"compute_c\",\"result\":\"r\"}}}}",
      new="},{\"id\":\"count_d\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"compute_c\",\"result\":\"r\"}}},\"steps\":[{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"n\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"count_d\",\"result\":\"r\"}}}}",
    )
  } else {
    text
  }
  let text = if dag_join && join_steps != [0] {
    let start = "{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}},\"from\":\"l\",\"as\":\"out\"}"
    let join = "{\"join\":{\"with\":\"r\",\"kind\":\"inner\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"select\":{\"id\":\"left.id\"}}"
    text.replace(
      old=start,
      new="{\"filter\":\"id > 0\",\"from\":\"l\"}," +
        (if join_steps.length() == 2 { join + "}," } else { "" }) +
        join +
        ",\"as\":\"out\"}",
    )
  } else {
    text
  }
  let text = if numeric_dag {
    text.replace(old="id < 9", new="id > 2")
  } else {
    text
  }
  let text = text.replace(old="id > $minimum", new=acquisition_filter)
  let text = text.replace(old="id > 2", new=compute_filter)
  let input_limits : @syntax.Limits = {
    source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    tree: {
      max_nodes: 100000,
      max_depth: 100,
      max_string_bytes: 1000000,
      max_total_string_bytes: 1000000,
    },
    max_stages: 10,
  }
  let program = @syntax.parse(text, input_limits, format=Json).unwrap()
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(
        @environment.carrier_schema_modes(
          @environment.source_request_carriers(
            if catalog is Some(catalog) {
              catalog
            } else if nullable {
              query_nullable_catalog_fixture()
            } else {
              query_program_catalog_fixture()
            },
          ),
        ),
      ),
    ),
  )
  let environment = @environment.contract_registry_environment(
    @environment.catalog_registry(
      @environment.reference_contents(
        @environment.data_policy_references(policies),
      ),
    ),
  )
  let evidence = if dag_join {
    [join_graph_capacity_material(environment, "compute_c", steps=join_steps)]
  } else {
    []
  }
  match
    @program_check.check_parsed_with_evidence(
      program,
      @program_check.checking_environment(
        environment,
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
      ),
      Some(input_cursor(parameter_json)),
      evidence,
      { input: input_limits, compilation: query_checked_limits(10), },
    ) {
    Checked(value) => value
    NeedsInputs(_) => fail("fixture requires complete checking inputs")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
}

///|
test "query Program reaches the public main checked entry" {
  let checked = query_checked_program_fixture()
  assert_eq(@program_check.unit_count(checked), 1)
  assert_eq(@program_check.source_execution_count(checked), 5)
  for i in 0..<5 {
    let execution = @program_check.source_execution_at(checked, i).unwrap()
    assert_true(
      physical_equal(
        @program_check.source_execution_subject(execution).owner,
        @program_check.source_identity(checked),
      ),
    )
  }
}

///|
fn query_checked_sequence(
  checked : @program_check.CheckedProgram,
) -> @query.QuerySequence raise {
  let identity = @program_check.source_identity(checked)
  let requests = @context.program_identity_stage_requests(identity, 0).unwrap()
  let query = @acquisition.derive_query_acquisition(requests, 0, 1000000).unwrap()
  assert_true(
    physical_equal(
      @program_check.unit_pipeline(checked, 0).unwrap(),
      @acquisition.query_acquisition_pipeline(query),
    ),
  )
  let prepared = @lower.prepare(
    @acquisition.query_acquisition_pipeline(query),
    {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    },
  ).unwrap()
  let values = @acquisition.request_parameter_values(
    @acquisition.pipeline_requests_parameters(requests),
  )
  let bound = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  @query.prepare_query_sequence(query, query_generated(bound), 10000).unwrap()
}

///|
test "public CheckedProgram feeds both query strategies capture and checked consumer" {
  let checked = query_checked_program_fixture()
  let identity = @program_check.source_identity(checked)
  let sequence = query_checked_sequence(checked)
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let requirement = @planning.prepare_query_requirement(
    material,
    identity,
    { max_rows: 10, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let unit_cid = @program_check.unit_definition_cid(checked, 0).unwrap()
  let requirement_cid = @planning.query_requirement_cid(requirement)
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let contracts = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let issuer = @mock.prepare_mock_query_issuer(
    contracts, requirement, "checked-program-test", 100,
  ).unwrap()
  let owner = @query.query_sequence_owner(sequence)
  let receiver = typed_receiver(owner, "[{\"select\":[\"id\"]}]")
  for route in [@mock.NativeQuery, @mock.BroadWithResidual] {
    let attempt = query_issuer_attempt(issuer, sequence, route)
    query_issuer_run(attempt)
    let records = @mock.issue_mock_query_records(
      attempt,
      query_material_limits(),
    ).unwrap()
    let observation = @mock.capture_mock_query(
      issuer,
      attempt,
      records,
      query_capture_limits(),
    ).unwrap()
    let input = @mock.bind_captured_query_input(
      issuer, attempt, observation, receiver, 0, owner,
    ).unwrap()
    let consumer = @execution.prepare_local_compute_attempt(
      compute_test_sequence(receiver),
      [input],
      3,
    ).unwrap()
    let complete = @execution.execute_local_compute_attempt(
      consumer,
      compute_test_limits(),
    ).unwrap()
    let output = @execution.completed_output(complete, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2)))
    assert_eq(@program_check.unit_definition_cid(checked, 0).unwrap(), unit_cid)
    assert_eq(@planning.query_requirement_cid(requirement), requirement_cid)
  }
  let foreign = query_checked_program_fixture()
  assert_eq(
    @context.program_identity_definition_cid(
      @program_check.source_identity(foreign),
    ),
    @context.program_identity_definition_cid(identity),
  )
  assert_true(
    @planning.prepare_query_requirement(
      material,
      @program_check.source_identity(foreign),
      { max_rows: 10, max_value_bytes: 100, },
      query_material_limits(),
    )
    is Err(ForeignProgram),
  )
}
