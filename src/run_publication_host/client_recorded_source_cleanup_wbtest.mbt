///|
// Issue the original fixture through common owners with a different grammar
// identity. Its Program and complete checked graph remain the same. This is
// historical cleanup evidence, never an executable replacement Template.
fn recorded_source_cleanup_fixture(
  foreign_graph? : Bool = false,
) -> (String, @publication.RecordedRunPublication, String, String) raise {
  let (prepared, compilation, _, _) = retained_input_run("recorded-cleanup")
  let template_value = parse_plan_identity_value(
    @publication.run_evidence_value_json(
      client_task_compilation_template(compilation),
    ),
    100000,
    10000,
    100,
  ).unwrap()
  let unsigned = @canonical.object_without_field(
    template_value, "bound_invocation_template_cid",
  ).unwrap()
  let historical = @canonical.object_with_string_field(
    @canonical.object_without_field(unsigned, "grammar_manifest_cid").unwrap(),
    "grammar_manifest_cid",
    retained_input_cid("f"),
  ).unwrap()
  let template = @publication.seal_run_evidence_value(
    "bound_invocation_template",
    @canonical.stringify_value(historical, 100000, 10000, 100),
    100000,
    10000,
    100,
  ).unwrap()
  let original_plan = client_task_compilation_compiled_plan(compilation)
  let plan = if foreign_graph {
    let value = parse_plan_identity_value(
      @publication.publication_contract_json(original_plan),
      100000,
      10000,
      100,
    ).unwrap()
    let unsigned_plan = @canonical.object_without_field(
      value, "compiled_plan_cid",
    ).unwrap()
    let changed = @canonical.object_with_string_field(
      @canonical.object_without_field(unsigned_plan, "aoa_logical_cid").unwrap(),
      "aoa_logical_cid",
      retained_input_cid("f"),
    ).unwrap()
    @publication.seal_publication_contract(
      "compiled_plan",
      @canonical.stringify_value(changed, 100000, 10000, 100),
      100000,
      10000,
      100,
    ).unwrap()
  } else {
    original_plan
  }
  let (original_prepared, authorization) = issue_client_allowed_run_evidence(
    template,
    plan,
    retained_input_cid("a"),
    retained_input_cid("b"),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let admission = @publication.admit_run_publication(
    template, original_prepared, authorization, plan,
  ).unwrap()
  let definition = @publication.issue_run_definition(
    admission,
    "retained-scope",
    "recorded-cleanup",
    @publication.empty_initial_input_artifact_set_cid(),
    "2026-10-05T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
    100000,
    10000,
    100,
  ).unwrap()
  let recorded = @publication.prepare_recorded_run_publication(
    admission,
    definition,
    @publication.prepare_result_definition(
      prepared_client_identity(prepared).program_definition_cid,
      "answer",
    ).unwrap(),
  ).unwrap()
  let environment = admit_client_check_environment(
    multi_source_environment,
    prepared_client_check_environment_cid(prepared),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let wire = issue_client_run_materials_input(
    prepared,
    admission,
    definition,
    environment,
    multi_source_environment,
    retained_input_program,
    None,
  ).unwrap()
  let facts = @planning.query_source_evidence_fact_values(
    prepared_client_source_evidence_facts(prepared, 0, 0).unwrap(),
  )
  (wire, recorded, facts[0], facts[1])
}

///|
test "recorded Source cleanup role requires exact root task Run and Source binding" {
  let (wire, recorded, source_ref, source_contract) = recorded_source_cleanup_fixture()
  let run = @publication.recorded_run_publication_run_cid(recorded)
  let context = admit_recorded_client_source_cleanup_graph(
    wire,
    run,
    recorded,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    run_materials_limits(),
    source_ref,
    source_contract,
  ).unwrap()
  let edge = resolve_client_retained_input_edge(context.prepared, run, 1, 0).unwrap()
  let input = prepare_client_task_input_binding(context.prepared, 0).unwrap()
  let request = fn(
    run_cid : String,
    task : String,
    binding : @remote.RemoteInputBinding,
  ) {
    @remote.prepare_dispatch_request(
      "authority-a",
      run_cid,
      task,
      1,
      "original-source",
      "site-a",
      1,
      retained_input_cid("a"),
      "local",
      "local/1",
      "strategy/1",
      @remote.remote_input_binding_cid(binding),
      retained_input_cid("2"),
      retained_input_cid("3"),
      retained_input_cid("4"),
      retained_input_cid("5"),
    ).unwrap()
  }
  let producer = request(run, edge.producer.node_id, input)
  assert_true(
    recorded_client_source_cleanup_matches_producer(
      context, producer, input, source_ref, source_contract,
    ),
  )
  for
    wrong in [
      request(retained_input_cid("f"), edge.producer.node_id, input),
      request(run, edge.consumer.node_id, input),
    ] {
    assert_false(
      recorded_client_source_cleanup_matches_producer(
        context, wrong, input, source_ref, source_contract,
      ),
    )
  }
  let foreign_input = @remote.prepare_remote_input_binding("{}", 8192).unwrap()
  assert_false(
    recorded_client_source_cleanup_matches_producer(
      context,
      request(run, edge.producer.node_id, foreign_input),
      foreign_input,
      source_ref,
      source_contract,
    ),
  )
  assert_false(
    recorded_client_source_cleanup_matches_producer(
      context, producer, input, "connector://another/source#v", source_contract,
    ),
  )
  assert_false(
    recorded_client_source_cleanup_matches_producer(
      context,
      producer,
      input,
      source_ref,
      retained_input_cid("f"),
    ),
  )
}

///|
test "recorded Source graph refuses another valid original Plan with a foreign graph" {
  let (wire, recorded, source_ref, source_contract) = recorded_source_cleanup_fixture(
    foreign_graph=true,
  )
  assert_true(
    admit_recorded_client_source_cleanup_graph(
      wire,
      @publication.recorded_run_publication_run_cid(recorded),
      recorded,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_limits(),
      source_ref,
      source_contract,
    )
    is Err(InvalidBinding),
  )
}

///|
test "recorded Source graph admits cleanup despite a different original Template" {
  let (wire, recorded, source_ref, source_contract) = recorded_source_cleanup_fixture()
  let run = @publication.recorded_run_publication_run_cid(recorded)
  // Execution admission still refuses the historical Template. The explicit
  // cleanup context does not supply materials, a borrow or a start claim.
  assert_true(
    admit_client_task_run_materials(
      wire,
      run,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_manifests(),
      run_materials_limits(),
    )
    is Err(Admission(@publication.RunAdmissionTemplateMismatch)),
  )
  assert_true(
    admit_recorded_client_source_cleanup_graph(
      wire,
      run,
      recorded,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_limits(),
      source_ref,
      source_contract,
    )
    is Ok(_),
  )
}

///|
test "recorded Source graph rejects foreign Run lifetime Program and Site Source" {
  let (wire, recorded, source_ref, source_contract) = recorded_source_cleanup_fixture()
  let run = @publication.recorded_run_publication_run_cid(recorded)
  let admit = fn(
    body : String,
    expected : String,
    source : String,
    contract : String,
  ) {
    admit_recorded_client_source_cleanup_graph(
      body,
      expected,
      recorded,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      run_materials_limits(),
      source,
      contract,
    )
  }
  assert_true(
    admit(wire, retained_input_cid("f"), source_ref, source_contract)
    is Err(InvalidBinding),
  )
  assert_true(
    admit(wire, run, "connector://foreign/r#v", source_contract)
    is Err(InvalidBinding),
  )
  assert_true(
    admit(wire, run, source_ref, retained_input_cid("f")) is Err(InvalidBinding),
  )
  for
    (before, after) in [
      ("recorded-cleanup", "another-run"),
      ("retained-scope", "another-scope"),
      ("2026-10-05T00:00:00.000Z", "2026-10-06T00:00:00.000Z"),
      ("2099-01-01T00:00:00.000Z", "2098-01-01T00:00:00.000Z"),
      ("id > 2", "id > 3"),
    ] {
    assert_true(
      admit(
        wire.replace(old=before, new=after),
        run,
        source_ref,
        source_contract,
      )
      is Err(InvalidBinding),
    )
  }
}
