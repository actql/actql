///|
// Fixed existing ModelTask/execution/environment inputs. Expected output rows
// below are independently authored, never captured from a prefix execution.
// This is a common Owner integration fixture, not installed-product acceptance.
fn original_prefix_execution_fixture(
  source? : Bool = false,
  environment_override? : String? = None,
  document_override? : String? = None,
  serialization_coordinate? : (Int, Int)? = None,
  serialization_bounds? : (Int, Int) = (2, 128),
  model_task_override? : String? = None,
  model_execution_override? : (String, String)? = None,
) -> (
  @publication_host.PreparedClientProgram,
  @publication_host.ClientCompiledRun,
  @publication.PublicationContract,
  @publication_host.ClientInferPlanGraph,
) {
  let baseline =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  let task =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let task = model_task_override.unwrap_or(task)
  let baseline = if environment_override is Some(value) {
    value
  } else if source {
    source_query_original_environment
  } else {
    baseline
  }
  let baseline_cid = if environment_override is Some(_) {
    let parsed = @json.parse(baseline) catch {
      _ => abort("fixture environment JSON")
    }
    match parsed {
      Object(fields) =>
        match fields.get("evidence_bundle_cid") {
          Some(String(value)) => value
          _ => abort("fixture environment CID")
        }
      _ => abort("fixture environment object")
    }
  } else if source {
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554"
  } else {
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904"
  }
  let unsigned = baseline
    .replace(old="\"evidence_bundle_cid\":\"" + baseline_cid + "\",", new="")
    .replace(
      old="\"model_task_contracts\":[]",
      new="\"model_task_contracts\":[" + task + "]",
    )
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  let environment = @publication_host.admit_client_check_environment(
    unsigned.replace(
      old="\"host_policy_profile\":",
      new="\"evidence_bundle_cid\":\"" + cid + "\",\"host_policy_profile\":",
    ),
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"original-content-prefix","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["name","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let document = if document_override is Some(value) {
    value
  } else if source {
    (
      #|{"version":"actql/0.1","id":"original-content-source","stages":[{"id":"capture","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id","amount"]}}},{"id":"classify","inputs":{"rows":{"result":{"stage":"capture","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"serialize":{"format":"jsonl","fields":["id","amount"],"order_by":[{"id":"asc"}],"name":"out.jsonl","bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"},{"assert_rows":{"unique_by":["name"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"name","input":{"text":{"field":"name"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["name","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"classify","result":"rows"}}}}
    )
  } else {
    document
  }
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let sequence = @publication_host.client_standard_values_sequence_limits()
  let policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let content = if source {
    let (task, step) = serialization_coordinate.unwrap_or((1, 1))
    if serialization_coordinate is Some(_) {
      let occurrences = @publication_host.prepared_client_serialization_occurrences(
        prepared,
      )
      for (actual_task, actual_step) in occurrences {
        println(
          "keyed fixture serialization task=" +
          actual_task.to_string() +
          ", step=" +
          actual_step.to_string(),
        )
      }
      if @publication_host.select_client_single_keyed_acquisition(prepared)
        is Ok(Some(keyed)) &&
        @publication_host.client_keyed_acquisition_coordinates(keyed)
        is Some((stage, keyed_task, join)) {
        println(
          "keyed fixture acquisition stage=" +
          stage.to_string() +
          ", task=" +
          keyed_task.to_string() +
          ", join=" +
          join.to_string(),
        )
      }
    }
    @publication_host.issue_prepared_client_acquired_serialization_plan_component(
      prepared,
      task,
      step,
      serialization_bounds.0,
      serialization_bounds.1,
      10000,
      sequence,
      1000000,
      100000,
      100,
    ).unwrap()
  } else {
    @publication_host.issue_prepared_client_serialization_plan_component(
      prepared, 0, 1, policy, 2, 128, 10000, sequence, 1000000, 100000, 100,
    ).unwrap()
  }
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  if serialization_coordinate is Some(_) {
    let (stage, task, step) = @publication_host.client_infer_occurrence_coordinates(
      occurrence,
    )
    println(
      "keyed fixture Infer stage=" +
      stage.to_string() +
      ", task=" +
      task.to_string() +
      ", step=" +
      step.to_string(),
    )
  }
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  let (execution_wire, execution_cid) = model_execution_override.unwrap_or(
    (
      execution_wire, "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    ),
  )
  let execution = @publication_host.read_client_infer_occurrence_model_execution(
    occurrence,
    @utf8.encode(execution_wire),
    execution_cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  let plan = match
    @publication_host.issue_prepared_client_serialized_infer_plan_graph(
      occurrence, content, execution, sequence, 1000000, 100000, 100,
    ) {
    Ok(value) => value
    Err(@publication_host.UnsupportedProgram) =>
      abort("fixture serialized Infer: UnsupportedProgram")
    Err(@publication_host.ForeignExecution) =>
      abort("fixture serialized Infer: ForeignExecution")
    Err(@publication_host.InvalidDependency) =>
      abort("fixture serialized Infer: InvalidDependency")
    Err(@publication_host.Execution(_)) =>
      abort("fixture serialized Infer: Execution")
    Err(@publication_host.Input(_)) => abort("fixture serialized Infer: Input")
    Err(@publication_host.Mapping(_)) =>
      abort("fixture serialized Infer: Mapping")
    Err(@publication_host.Result(_)) =>
      abort("fixture serialized Infer: Result")
    Err(@publication_host.Encoding) =>
      abort("fixture serialized Infer: Encoding")
    Err(@publication_host.ItemLimit(_)) =>
      abort("fixture serialized Infer: ItemLimit")
    Err(@publication_host.Serialization(_)) =>
      abort("fixture serialized Infer: Serialization")
  }
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_infer_compilation(
    prepared, plan, manifests, 1000, 1000, 1000000, 100000, 100,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "prefix-execution", "same-original", "2026-10-13T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (prepared, compiled, definition, plan)
}

///|
test "original checked Content prefix executes through the new Local entry on the same Ledger" {
  let (prepared, compiled, definition, plan) = original_prefix_execution_fixture()
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 2,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: source_capture_values(),
      output_values: source_capture_values(),
    },
    max_work: 100000,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let registry = @identity.stringify_value(
    content_recovery_registered_body(),
    1000000,
    100000,
    100,
  )
  let values = @identity.stringify_value(
    content_recovery_registered_values(),
    1000000,
    100000,
    100,
  )
  let prefix_contracts = prepare_installed_sequence_contracts(registry, values, None, None).unwrap()
  let capacity = client_serialization_prefix_capacity(
    prepared,
    0,
    1,
    prefix_contracts,
    values,
    None,
    None,
    execution,
    measurement,
  ).unwrap()
  let retention = @execution.execution_capacity_retained_bytes(capacity)
  let workspace = @execution.execution_capacity_execution_bytes(capacity)
  // Reserve exactly the EXISTING selected provider capacity plus this
  // independent bootstrap lifetime fixture. No Node numeric policy is issued.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: retention + 3L,
    execution_bytes: workspace + 2L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 3, 1, 0,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    start_client_original_serialization_prefix(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      0,
      2,
      prefix_contracts,
      values,
      None,
      None,
      execution,
      measurement,
    )
    is Err(Original(@publication_host.ForeignRun)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let prefix = start_client_original_serialization_prefix(
    scope,
    compiled,
    definition,
    plan,
    prepared,
    0,
    1,
    prefix_contracts,
    values,
    None,
    None,
    execution,
    measurement,
  ).unwrap()
  assert_true(physical_equal(prefix.ledger, ledger))
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_retention_bytes,
    retention + 3L,
  )
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    workspace + 2L,
  )
  assert_true(
    start_client_original_serialization_prefix(
      scope,
      compiled,
      definition,
      plan,
      prepared,
      0,
      1,
      prefix_contracts,
      values,
      None,
      None,
      execution,
      measurement,
    )
    is Err(
      Original(@publication_host.Resource(@resources.ChangedOriginalState))
    ),
  )
  let mut output : @execution.CompletedOutput? = None
  let mut polls = 0
  while output is None && polls < 1000 {
    polls += 1
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => output = Some(value)
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("checked original prefix did not complete")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 100).unwrap(),
    "{\"id\":2}",
  )
  assert_eq(
    @execution.completed_output_row_wire(output, 1, 10000, 1000, 100).unwrap(),
    "{\"id\":1}",
  )
  assert_true(client_serialization_prefix_work(prefix).unwrap() > 0L)
  assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 2L)
  // Issue the ORIGINAL descriptor only after prefix work, from its actual
  // census including the spent attempt. Zero read bytes are not a send grant.
  let read = @publication_host.prepare_client_model_read(scope, 0L, 0L).unwrap()
  assert_true(
    @publication_host.client_model_read_available(
      read, compiled, definition, plan,
    ),
  )
  assert_true(
    physical_equal(
      @publication_host.handoff_client_model_read(
        read, compiled, definition, plan,
      ).unwrap(),
      ledger,
    ),
  )
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, plan, true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
}
