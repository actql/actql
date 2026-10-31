///|
// Existing source-free terminal Serialization purpose, authored independently
// of its compiler output. This fixture opens no provider, Store or public Run.
let request_serialization_document : String =
  #|{"version":"actql/0.1","id":"request-content-compilation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}

///|
test "source-free Serialization compilation remains on original Request capacity and compiler output" {
  let (parent, child, _, input) = registration_parent_fixture(
    text=request_serialization_document,
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("authored source-free Serialization check")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let component = @publication_host.issue_prepared_client_serialization_plan_graph(
    prepared,
    0,
    1,
    policy,
    2,
    128,
    3,
    @publication_host.client_standard_values_sequence_limits(),
    100000,
    10000,
    100,
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let ledger = parent.ledger
  let capacity = parent.program_capacity.unwrap()
  let compilation = prepare_request_serialization_compilation(
    parent,
    input,
    component,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  assert_true(physical_equal(parent.ledger, ledger))
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  guard parent.program_compilation is Some(@publication_host.Tasks(original)) else {
    fail("same retained Serialization TaskCompilation")
  }
  assert_true(physical_equal(original, compilation))
  assert_true(
    physical_equal(
      @publication_host.client_task_compilation_serialization(compilation).unwrap(),
      component,
    ),
  )
  assert_true(parent.phase == ContentPlanReserved)
  assert_true(parent.program_artifact_work_spent > 0L)
  let spent = parent.program_artifact_work_spent
  assert_true(
    prepare_request_serialization_compilation(
      parent,
      input,
      component,
      contracts,
      manifests~,
      compilation_limits~,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}
