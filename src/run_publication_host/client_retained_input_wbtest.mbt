///|
let retained_input_program : String =
  #|{"version":"actql/0.1","id":"retained-source-compute","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id > 2","as":"filtered"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"rows"}}}}

///|
fn retained_input_cid(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn retained_input_run(
  run_id : String,
) -> (
  PreparedClientProgram,
  ClientTaskCompilation,
  @publication.RunPublicationAdmission,
  @publication.PublicationContract,
) raise {
  let prepared = multi_source_prepared(retained_input_program)
  let compilation = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = issue_client_task_compiled_run(
    prepared,
    compilation,
    retained_input_cid("a"),
    retained_input_cid("b"),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_compiled_run_definition(
    allowed, "retained-scope", run_id, "2026-10-05T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (prepared, compilation, client_compiled_run_admission(allowed), definition)
}

///|
fn retained_input_completed(
  run : String,
  task : String,
  attempt : Int,
  generation : Int,
  schema : String,
  measurement_cid? : String = retained_input_cid("b"),
) -> (
  @remote.DispatchRecord,
  @remote.RemoteExecutionEvidence,
  @remote.RemoteManagedOutputSubject,
) {
  let bundle = retained_input_cid("a")
  let site = @site.create_site(
    "site-a", generation, bundle, 4, 4, 1048576L, 1048576L,
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let request = @remote.prepare_dispatch_request(
    "authority-a",
    run,
    task,
    attempt,
    "producer-dispatch",
    "site-a",
    generation,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    retained_input_cid("1"),
    retained_input_cid("2"),
    retained_input_cid("3"),
    retained_input_cid("4"),
    retained_input_cid("5"),
  ).unwrap()
  let record = @remote.commit_dispatch_acceptance(
      @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
      true,
    ).unwrap().1
  let holding = @remote.remote_output_holding_evidence_cid(
    request, "producer-material", 8L,
  ).unwrap()
  // Exercise the public journal restoration boundary. These are protocol
  // unit tests, not evidence of a Native executor or physical payload.
  @remote.restore_dispatch_record(
    record, 4, 3, 1, 0, true, false, "producer-material", holding, "",
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    bundle,
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_managed_output_evidence_kind(),
    retained_input_cid("4"),
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "producer-material",
    holding,
    retained_input_cid("6"),
    schema,
    retained_input_cid("7"),
    retained_input_cid("8"),
    retained_input_cid("9"),
    measurement_cid,
    1,
    8L,
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_durable_execution_evidence(record, evidence).unwrap(),
    true,
  ).unwrap()
  (record, evidence, subject)
}

///|
test "retained input resolves the original Source to checked consumer port" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "run-a",
  )
  assert_eq(@strategy.graph_task_count(prepared_client_graph(prepared)), 2)
  let edge = prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let ports = client_retained_input_edge_projection(edge)
  assert_eq(ports[0], @publication.publication_contract_identity(definition))
  assert_eq(ports[7], "input")
  // Independent canonical object contract: one required nonnullable number.
  assert_eq(
    ports[4],
    "sha256:999395be222d44c0d3dafb4eb4e306cc6f0329a2096af1aeb380341d4cfa588c",
  )
  // Independent canonical field-map schema: {"id":{"nullable":false,"type":"number"}}.
  let schema = client_retained_input_edge_schema_cid(edge)
  assert_eq(
    schema, "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  assert_true(schema != ports[4])
  assert_true(ports[1] != ports[5])
  assert_true(
    prepare_client_retained_input_edge(
      prepared, compilation, admission, definition, 0, 0,
    )
    is Err(MissingEdge),
  )
  assert_true(
    prepare_client_retained_input_edge(
      prepared, compilation, admission, definition, 1, 1,
    )
    is Err(MissingEdge),
  )
  let (foreign, _, _, _) = retained_input_run("run-a")
  assert_true(
    prepare_client_retained_input_edge(
      foreign, compilation, admission, definition, 1, 0,
    )
    is Err(Run(ForeignRun)),
  )
  // Issuing a checked edge is not installing a retained physical input.
  assert_true(
    prepare_client_task_input_binding(prepared, 1) is Err(UnsupportedTask),
  )
}

///|
test "retained input rejects another Run producer schema or attempt evidence" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "run-a",
  )
  let edge = prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let ports = client_retained_input_edge_projection(edge)
  let schema_cid = client_retained_input_edge_schema_cid(edge)
  let (record, evidence, subject) = retained_input_completed(
    ports[0],
    ports[1],
    1,
    1,
    schema_cid,
  )
  let producer = prepare_client_retained_input_producer(
    edge, record, evidence, subject,
  ).unwrap()
  assert_true(client_retained_input_producer_available(producer))
  let (_, _, _, other_definition) = retained_input_run("run-b")
  for
    (run, task, schema) in [
      (
        @publication.publication_contract_identity(other_definition),
        ports[1],
        schema_cid,
      ),
      (ports[0], ports[5], schema_cid),
      (ports[0], ports[1], retained_input_cid("f")),
      // The equal checked row contract is still the wrong physical schema.
      (ports[0], ports[1], ports[4]),
    ] {
    let (foreign, proof, output) = retained_input_completed(
      run, task, 1, 1, schema,
    )
    assert_true(
      prepare_client_retained_input_producer(edge, foreign, proof, output)
      is Err(ForeignProducer),
    )
  }
  for (attempt, generation) in [(2, 1), (1, 2)] {
    let (foreign, _, _) = retained_input_completed(
      ports[0],
      ports[1],
      attempt,
      generation,
      schema_cid,
    )
    assert_true(
      prepare_client_retained_input_producer(edge, foreign, evidence, subject)
      is Err(ForeignProducer),
    )
  }
}

///|
test "retained producer reference revokes new handoff while cleanup is pending" {
  let (prepared, compilation, admission, definition) = retained_input_run(
    "run-a",
  )
  let edge = prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let ports = client_retained_input_edge_projection(edge)
  let schema_cid = client_retained_input_edge_schema_cid(edge)
  let (record, evidence, subject) = retained_input_completed(
    ports[0],
    ports[1],
    1,
    1,
    schema_cid,
  )
  let producer = prepare_client_retained_input_producer(
    edge, record, evidence, subject,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_begin_remote_release(record).unwrap(),
    true,
  ).unwrap()
  assert_false(client_retained_input_producer_available(producer))
  assert_true(
    prepare_client_retained_input_producer(edge, record, evidence, subject)
    is Err(ProducerUnavailable),
  )
  // Revocation is not a claim that the original reservation or bytes were freed.
  assert_false(@remote.remote_runtime_record_released(record))
  @remote.commit_dispatch_transition(
    @remote.prepare_confirm_remote_release(record).unwrap(),
    true,
  ).unwrap()
  assert_false(client_retained_input_producer_available(producer))
}
