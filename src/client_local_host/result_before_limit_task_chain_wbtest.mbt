///|
// Exact public standard environment assembled by the existing ordinary fixture;
// no database, state, credential or Source path is part of this checker input.
let before_limit_standard_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"connector_catalogs":[{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:f89c038ba1c148b0ef1b1b6091226544bc7ef45c2ef3059ac0b87ed1897413d7","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_analytic_frame_memberships":10000,"max_analytic_input_wire_bytes":10000,"max_analytic_output_wire_bytes":10000,"max_analytic_partition_wire_bytes":10000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":4096,"max_input_utf8_bytes":16384,"max_output_bytes":1048576,"max_pattern_bytes":4096,"max_replacements":4096,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
fn before_limit_standard_prepared(
  text : String,
  format : @frontend.Format,
) -> @publication_host.PreparedClientProgram raise {
  let environment = @publication_host.admit_client_check_environment(
    before_limit_standard_environment,
    "sha256:f89c038ba1c148b0ef1b1b6091226544bc7ef45c2ef3059ac0b87ed1897413d7",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let body = @json.parse(before_limit_standard_environment)
  guard body is Object(root) &&
    root["schema_snapshots"] is Array(snapshots) &&
    snapshots[0] is Object(snapshot) else {
    abort("fixture snapshot")
  }
  let publication : Json = {
    "environmentCid": "sha256:f89c038ba1c148b0ef1b1b6091226544bc7ef45c2ef3059ac0b87ed1897413d7",
    "aliases": [
      {
        "name": "records",
        "sourceRef": snapshot["source_ref"],
        "sourceViewContractCid": snapshot["source_view_contract_cid"],
        "schemaContractCid": snapshot["carrier_schema_contract_cid"],
      },
    ],
  }
  let selected = @source_publication.prepare_published_query_environment(
    environment,
    publication.stringify(),
  ).unwrap()
  let (lowered, catalog) = @source_publication.lower_prepared_published_query(
    selected,
    environment,
    text,
    format,
    None,
    public_primary=true,
  ).unwrap()
  @publication_host.prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
    source_catalog=Some(catalog),
  ).unwrap()
}

///|
// Keep the original Result before the terminal LIMIT and all original parent
// outputs live through the selected Source/Compute chain and final cleanup.
test "Result before LIMIT retains both original outputs through the actual task selection" {
  let prepared = before_limit_standard_prepared(
    "FROM records |> ORDER BY id |> RESULT original |> LIMIT 1",
    @frontend.Text,
  )
  let publication_policy = @publication_host.prepared_client_publication_data_policy_cid(
    prepared,
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "result-before-limit-original",
  ).unwrap()
  guard select_installed_source_input(prepared, request, 0, 0).unwrap()
    is @sourceviews.WholeInputRoute(original) else {
    fail("the original request selects Whole Source")
  }
  let policy = installed_row_input_policy(10000, 10000000, 110101, 2, 10000)
  let source = prepare_installed_catalog_whole_source_capacity(
    prepared, original, contracts, policy,
  ).unwrap()
  let plan = prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    source,
    10000000L,
    239908928L,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=false,
    provider_factory=_ => [],
    runtime_admission=true,
  ).unwrap()
  let limits = {
    ..plan.limits,
    retained_bytes: client_local_retained_byte_ceiling(),
    execution_bytes: client_local_execution_byte_ceiling(),
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  let rows = @row_source_host.start_accounted_row_input_acquisition(
    source.acquisition,
    source.provider,
    "before-limit-original-source",
    _ => true,
    ledger,
    10000000L,
    239908928L,
  ).unwrap()
  @row_source_host.begin_row_run_with_page_limits(rows, policy.page, 10000).unwrap()
  let wire = @utf8.encode(
    "[{\"id\":3,\"amount\":30},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30}]",
  )
  let charged = @row_source_host.charge_row_run_page(rows, wire).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, wire).unwrap(),
    4,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut captured = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      captured = true
      break
    }
  }
  assert_true(captured)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let actual_source = @row_source_host.row_capture_source(capture).unwrap()
  let source_matches = Array::makei(
    @publication_host.prepared_client_acquisition_count(prepared),
    task => {
      @publication_host.prepared_client_captured_task_source_matches(
        prepared, actual_source, task,
      )
    },
  )
  assert_eq(source_matches, [true])

  let dag = @strategy.open_source_inputs_dag(
    plan.graph,
    [@row_source_host.row_capture_source(capture).unwrap()],
    ledger,
  ).unwrap()
  @row_source_host.check_row_input_compute_binding(capture, dag, 0).unwrap()
  let host = bind_client_local_configuration(
    dag,
    plan.configuration,
    1L,
    1L,
    1L,
    1L,
  ).unwrap()
  @host_driver.refresh_compute_host(@builtin.configured_host_runtime(host)).unwrap()
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  let count = @strategy.graph_task_count(plan.graph)
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(count, None)
  let output_live = Ref(true)
  let coexistence_fits = Ref(true)
  let mut failure : @local_driver.LocalDispatchIssue? = None
  let mut selection_missing = false
  for _ in 0..<count {
    let task = @strategy.next_captured_task(dag).unwrap()
    let producers = @strategy.captured_next_managed_producers(dag)
    let available = producers.map(producer => {
      if producer == -1 {
        @local_driver.local_managed_supplied_relation_input()
      } else {
        @local_driver.local_managed_relation_output(
          tasks[producer].unwrap().completed.unwrap(),
        )
      }
    })
    let dispatch = match
      @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        available,
        @strategy.captured_next_managed_obligations(dag, 100000).unwrap(),
        0L,
      ) {
      Ok(Some(value)) => value
      Ok(None) => {
        selection_missing = true
        break
      }
      Err(issue) => {
        failure = Some(issue)
        break
      }
    }
    @strategy.select_captured_managed_registration(
      dag,
      task,
      @local_driver.local_dispatch_registration(installed),
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let observed_prior_execution = before.reserved_execution_bytes
    coexistence_fits.val = coexistence_fits.val &&
      @local_driver.local_managed_dispatch_site_capacity(dispatch).unwrap().1 +
      observed_prior_execution <=
      client_local_execution_byte_ceiling()
    let operations = match
      @local_driver.start_local_managed_dispatch_node(dispatch) {
      Ok(value) => value
      Err(issue) => {
        failure = Some(issue)
        break
      }
    }
    let current : LocalValuesTaskExecution = {
      operations,
      settled: false,
      completed: None,
    }
    tasks[task] = Some(current)
    for transfer in operations.inputs {
      let input = @execution.managed_producer_read_input_index(transfer.input)
      let producer = tasks[producers[input]].unwrap()
      let original_output = producer.completed.unwrap()
      assert_true(
        @execution.managed_producer_read_matches_reference(
          transfer.input,
          @execution.managed_completed_reference(original_output),
        ),
      )
      for
        row in 0..<@execution.managed_completed_output_row_count(
          original_output,
        ) {
        (transfer.append)((producer.operations.output_row)(row).unwrap()).unwrap()
      }
      (transfer.finish)().unwrap()
    }
    (operations.execute)().unwrap()
    (operations.prepare_finalization)(task, operations.storage_bytes, () => {
      output_live.val
    }).unwrap()
    let mut finalized = false
    for _ in 0..<10000 {
      if (operations.advance_finalization)(256).unwrap().complete {
        finalized = true
        break
      }
    }
    assert_true(finalized)
    (operations.settle)().unwrap()
    current.settled = true
    current.completed = Some(
      (operations.complete)(task, operations.storage_bytes, () => {
        output_live.val
      }).unwrap(),
    )
  }
  if failure is None && !selection_missing {
    assert_eq(@strategy.graph_result_count(plan.graph), 2)
    for index in 0..<2 {
      let name = @strategy.graph_result_name(plan.graph, index).unwrap()
      let result = tasks[@strategy.graph_result_task(plan.graph, index).unwrap()].unwrap()
      let expected = match name {
        "original" =>
          @json.parse(
            "[{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":20},{\"id\":3,\"amount\":30},{\"id\":3,\"amount\":30}]",
          )
        "answer" => @json.parse("[{\"id\":1,\"amount\":null}]")
        _ => fail("unexpected Result name")
      }
      guard expected is Array(rows) else { fail("authored rows") }
      assert_eq(
        @execution.managed_completed_output_row_count(result.completed.unwrap()),
        rows.length(),
      )
      for row in 0..<rows.length() {
        assert_eq(
          @json.parse((result.operations.output_row)(row).unwrap()),
          rows[row],
        )
      }
    }
  }
  output_live.val = false
  let mut cleaned = false
  for _ in 0..<10000 {
    if close_local_values_tasks(dag, tasks) {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  @row_source_host.close_accounted_row_run(rows).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_true(failure is None)
  assert_false(selection_missing)
  assert_true(coexistence_fits.val)
  // Independently pinned effective-policy canonical preimage: original Source
  // policy inventory plus the checked LIMIT's conservative unknown provenance.
  assert_eq(
    publication_policy,
    Some(
      "sha256:0ab54a0637544a1b96c511cd698af0b3356ccbf0f3da626cfbbbd5fe17a2a589",
    ),
  )
}
