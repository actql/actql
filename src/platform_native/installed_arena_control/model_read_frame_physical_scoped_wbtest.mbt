///|
// Compilation-identity DATA from the existing ModelTask and Infer fixtures.
// No provider call, egress grant or complete Model constructor funding is issued.
fn model_frame_test_run(
  id : String,
) -> (
  @host.ClientCompiledRun,
  @publication.PublicationContract,
  @host.ClientInferPlanGraph,
) {
  let original =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let task =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let unsigned = original
    .replace(
      old="\"evidence_bundle_cid\":\"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904\",",
      new="",
    )
    .replace(
      old="\"model_task_contracts\":[]",
      new="\"model_task_contracts\":[" + task + "]",
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  let wire = unsigned.replace(
    old="\"host_policy_profile\":",
    new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
  )
  let environment = @host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let program =
    #|{"version":"actql/0.1","id":"infer-prefix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"input"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"captured"}],"results":{"captured":{"from":"captured","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"captured"}}}}
  let prepared = @host.prepare_effect_free_client_program(
    program,
    Json,
    environment,
    None,
    @host.client_standard_program_preparation_limits(),
  ).unwrap()
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  let execution = @host.read_prepared_client_infer_model_execution(
    prepared,
    2,
    @utf8.encode(execution_wire),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  let bounds : @lower.SequenceLimits = {
    max_steps: 10,
    max_rows: 10,
    max_cells: 10,
    max_bindings: 10,
    max_name_bytes: 1000,
    expressions: {
      max_nodes: 100,
      max_work: 1000,
      max_depth: 10,
      max_literal_nodes: 100,
      max_literal_text_bytes: 1000,
    },
  }
  let plan = @host.issue_prepared_client_infer_plan_graph(
    prepared,
    2,
    execution,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    bounds,
    100000,
    10000,
    100,
  ).unwrap()
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_infer_compilation(
    prepared, plan, manifests, 1000, 1000, 100000, 10000, 100,
  ).unwrap()
  let compiled = @host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_compiled_run_definition(
    compiled, "read-scope", id, "2026-10-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (compiled, definition, plan)
}

///|
// These are the existing Native component backings and original Request
// admission. Only its actual started Ledger can bind the Model scope.
fn model_frame_test_request(
  label : String,
) -> (
  InstalledArenaHost,
  InstalledArenaDomain,
  Int,
  Ref[Int],
  @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    Ref[Int],
  ],
  @resources.BackedPreparationAdmission[Ref[Int]],
  @resources.ImportedChildLedger,
  @resources.Ledger,
) raise {
  let (arena, domain, descriptor) = initialization_physical_fixture(label)
  let input = Ref(177)
  let live = match arena.prepare_domain_request_child(domain, input).unwrap() {
    @bootstrap.LiveChildReady(value) => value
    @bootstrap.LiveChildPending(_, _) =>
      fail("Model frame original Request pending")
  }
  let initial = arena.prepare_request_admission(live, input).unwrap()
  let frame = @resources.backed_preparation_original_frame(initial, input).unwrap()
  let ledger = @resources.start_backed_preparation_admission(initial, input).unwrap()
  (arena, domain, descriptor, input, live, initial, frame, ledger)
}

///|
test "actual Model public frame keeps the same Native Request and refuses a foreign frame" {
  let (compiled, definition, plan) = model_frame_test_run("frame-original")
  let (arena, domain, descriptor, input, live, initial, frame, ledger) = model_frame_test_request(
    "source-frame-left",
  )
  let (
    other,
    other_domain,
    other_descriptor,
    _other_input,
    other_live,
    other_initial,
    other_frame,
    _,
  ) = model_frame_test_request("source-frame-right")
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  arena.enter_domain_read(domain).unwrap()
  @host.check_client_model_read_frame(scope, compiled, definition, plan, frame).unwrap()
  @native_client.check_native_client_request_model_read(
    arena, live, input, scope, compiled, definition, plan,
  ).unwrap()
  assert_true(
    @host.check_client_model_read_frame(
      scope, compiled, definition, plan, other_frame,
    )
    is Err(_),
  )
  assert_true(
    @native_client.check_native_client_request_model_read(
      arena,
      live,
      Ref(177),
      scope,
      compiled,
      definition,
      plan,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  arena.leave_domain_read(domain).unwrap()
  assert_true(
    @host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  arena.close_request_preparation(live).unwrap()
  other.close_request_preparation(other_live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  @resources.cleanup_backed_preparation_admission(other_initial).unwrap()
  initialization_physical_finish(arena, domain, descriptor)
  initialization_physical_finish(other, other_domain, other_descriptor)
}

///|
// This is shutdown AFTER an actual physical observation, not an injected
// synchronous callback. It exercises the public final retained fence directly.
test "actual Model retained frame refuses shutdown after physical current observation" {
  let (compiled, definition, plan) = model_frame_test_run("frame-closed")
  let (arena, domain, descriptor, input, live, initial, frame, ledger) = model_frame_test_request(
    "source-frame-original",
  )
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  arena.enter_domain_read(domain).unwrap()
  @native_client.check_native_client_request_model_read(
    arena, live, input, scope, compiled, definition, plan,
  ).unwrap()
  arena.leave_domain_read(domain).unwrap()
  assert_true(
    @host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  arena.enter_domain_read(domain).unwrap()
  let same = arena.borrow_request_read_frame(live, input).unwrap()
  assert_true(physical_equal(frame, same))
  assert_true(
    @host.check_client_model_read_frame_retained(
      scope, compiled, definition, plan, same,
    )
    is Err(@host.ForeignRun),
  )
  assert_true(
    @native_client.check_native_client_request_model_read(
      arena, live, input, scope, compiled, definition, plan,
    )
    is Err(_),
  )
  arena.leave_domain_read(domain).unwrap()
  arena.close_request_preparation(live).unwrap()
  @resources.cleanup_backed_preparation_admission(initial).unwrap()
  initialization_physical_finish(arena, domain, descriptor)
}

///|
// A real parked original has no journal invalidation receipt in this API-only
// case. Keep that obligation pending; process exit is not a cleanup ACK.
test "actual Model public frame refuses the original parked Resource ledger" {
  let (compiled, definition, plan) = model_frame_test_run("frame-parked")
  let (arena, domain, _descriptor, input, live, _initial, frame, ledger) = model_frame_test_request(
    "source-frame-original",
  )
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  let read = @host.prepare_client_model_read(scope, 7L, 5L).unwrap()
  let consumer = @host.claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  @host.enter_client_model_read_consumer(
    consumer, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  arena.enter_domain_read(domain).unwrap()
  @native_client.check_native_client_request_model_read(
    arena, live, input, scope, compiled, definition, plan,
  ).unwrap()
  let parked = @host.park_client_model_read_consumer(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @host.check_client_model_read_frame(
      scope, compiled, definition, plan, frame,
    )
    is Err(_),
  )
  assert_true(
    @host.check_client_model_read_frame_retained(
      scope, compiled, definition, plan, frame,
    )
    is Err(_),
  )
  assert_true(
    @native_client.check_native_client_request_model_read(
      arena, live, input, scope, compiled, definition, plan,
    )
    is Err(_),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  arena.leave_domain_read(domain).unwrap()
  assert_true(@host.retire_client_model_resource_park(parked) is Err(_))
  assert_true(
    @host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    )
    is Err(_),
  )
  assert_true(arena.close_request_preparation(live) is Err(_))
  assert_true(
    @host.client_model_resource_park_current(
      parked, scope, compiled, definition, plan,
    )
    is Some(same) &&
    physical_equal(same, parked),
  )
}
