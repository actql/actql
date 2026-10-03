///|
// A logical Source reference has no database path or connection credential.
let resident_source_program : String =
  #|{"version":"actql/0.1","id":"fixture.resident-source-filter-select","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}}],"results":{"answer":{"from":{"stage":"acquire","result":"rows"}}}}

///|
test "resident Source Result compiles its exact acquisition task without Compute" {
  let prepared = multi_source_prepared(resident_source_program)
  let graph = prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@strategy.graph_result_task(graph, 0), Some(0))
  assert_eq(@strategy.graph_task_target(graph, 0), None)
  let acquisition = match prepare_client_query_acquisition(prepared, 0, 0) {
    Ok(value) => value
    Err(MissingStage) => fail("acquisition stage missing")
    Err(MissingRequests) => fail("acquisition requests missing")
    Err(UnsupportedAcquisition(@acquisition.UnsupportedShape)) =>
      fail("acquisition shape unsupported")
    Err(UnsupportedAcquisition(@acquisition.UnboundRequest)) =>
      fail("acquisition request unbound")
    Err(_) => fail("acquisition bounds rejected")
  }
  assert_eq(
    @acquisition.query_acquisition_capture(acquisition),
    @pipeline.Step(1),
  )
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
  assert_eq(client_task_compilation_result_names(compilation), ["answer"])
  // The Plan remains exactly the checked acquisition; no replacement Values
  // or extra physical Compute task is added to make the Result publishable.
  assert_eq(@strategy.graph_task_count(prepared_client_graph(prepared)), 1)
}

///|
test "resident task materials preserve original Source and Values Run evidence" {
  let environment_cid = "sha256:4cfc3a08514b254c76ac810df9153072a3f0edbf0f211c18b85298aa0c51a92e"
  let environment = admit_client_check_environment(
    multi_source_environment,
    environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = run_materials_limits()
  for document in [resident_source_program, run_materials_document] {
    let prepared = multi_source_prepared(document)
    let compilation = issue_prepared_client_task_compilation(
      prepared,
      run_materials_manifests(),
      limits.sequence,
      limits.max_sequence_steps,
      limits.max_sequence_work,
      limits.max_evidence_bytes,
      limits.max_evidence_nodes,
      limits.max_evidence_depth,
    ).unwrap()
    let allowed = issue_client_task_compiled_run(
      prepared,
      compilation,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
    let definition = issue_client_compiled_run_definition(
      allowed, "resident-source-scope", "original-run", "2026-10-03T00:00:00.000Z",
      "2026-10-04T00:00:00.000Z",
    ).unwrap()
    let admission = client_compiled_run_admission(allowed)
    let wire = issue_client_task_run_materials(
      prepared,
      compilation,
      admission,
      definition,
      environment,
      multi_source_environment,
      document,
      None,
    ).unwrap()
    let admit = fn(body : String) {
      admit_client_task_run_materials(
        body,
        @publication.publication_contract_identity(definition),
        { text_time: false, veca: false, },
        {
          rela: true,
          sga: false,
          tea: false,
          calendar: false,
          text_rank: false,
        },
        run_materials_manifests(),
        limits,
      )
    }
    let rebuilt = admit(wire).unwrap()
    assert_eq(
      @publication.publication_contract_json(rebuilt.run_definition),
      @publication.publication_contract_json(definition),
    )
    assert_eq(
      @publication.run_evidence_value_json(
        @publication.run_publication_prepared(rebuilt.admission),
      ),
      @publication.run_evidence_value_json(
        @publication.run_publication_prepared(admission),
      ),
    )
    assert_eq(
      @publication.run_evidence_value_json(
        @publication.run_publication_authorization(rebuilt.admission),
      ),
      @publication.run_evidence_value_json(
        @publication.run_publication_authorization(admission),
      ),
    )
    assert_eq(
      @strategy.graph_task_count(prepared_client_graph(rebuilt.prepared)),
      1,
    )
    // Materials reconstruction cannot refresh the original Run lifetime or
    // give the same identity to another Run.
    assert_true(
      admit(
        wire.replace(
          old="2026-10-04T00:00:00.000Z",
          new="2026-10-05T00:00:00.000Z",
        ),
      )
      is Err(RunMismatch),
    )
    assert_true(
      admit(wire.replace(old="original-run", new="replacement-run"))
      is Err(RunMismatch),
    )
  }
}
