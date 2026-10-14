///|
fn explain_fixture_environment() -> @checked.CheckEnvironment {
  @run_host.admit_client_check_environment(
    (
      #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn explain_fixture(
  document : String,
  format : @frontend.Format,
) -> @local_host.NativeClientPreparation {
  @local_host.prepare_native_client_program(
    document,
    format,
    explain_fixture_environment(),
    None,
    None,
    [],
    @run_host.client_standard_effect_computation_limits(),
  ).unwrap()
}

///|
let explain_fixture_chain : String =
  #|{"version":"actql/0.1","id":"cli-static-chain","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"original"},{"from":"original","filter":"id > 1","as":"filtered"},{"from":"filtered","select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
test "Native Local explain grammar retains explicit format and separate parameters" {
  let parsed = command().parse(argv=[
    "--mode", "local", "explain", "--program-file", "input.sql", "--format", "sql",
    "--parameters-file", "parameters.json", "--json",
  ])
  guard parsed.subcommand is Some((operation, child)) else {
    fail("missing explain command")
  }
  assert_eq(operation, "explain")
  assert_eq(required(child, "format"), "sql")
  assert_eq(optional(child, "parameters-file"), Some("parameters.json"))
  assert_true(child.flags.get("json").unwrap_or(false))
  assert_true(local_product_operation(operation))
  assert_true(optional(parsed, "config-file") is None)
}

///|
test "Native explain refuses Remote before reading an absent input or connection" {
  let parsed = command().parse(argv=[
    "explain", "--program-file", "absent.sql", "--format", "sql",
  ])
  let issue = try {
    ignore(execute(parsed))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "operation requires an explicit Local configuration")
}

///|
test "Native Local explain returns checked logical occurrences and honest unavailable controls" {
  let prepared = explain_fixture(explain_fixture_chain, Json)
  let wire = local_static_plan_view(prepared)
  let root = @decode.open_object(local_input_cursor(wire)).unwrap()
  assert_eq(
    @decode.text(@decode.required(root, "version").unwrap()).unwrap(),
    "actql-plan-view/0.1",
  )
  assert_eq(
    @decode.text(@decode.required(root, "observation").unwrap()).unwrap(),
    "static",
  )
  assert_eq(
    @decode.safe_integer(@decode.required(root, "provider_io").unwrap()).unwrap(),
    0L,
  )
  assert_true(@decode.lookup(root, "run_ref") is None)
  let capabilities = @decode.open_object(
    @decode.required(root, "capabilities").unwrap(),
  ).unwrap()
  assert_true(
    @decode.boolean(@decode.required(capabilities, "static_plan").unwrap()).unwrap(),
  )
  assert_false(
    @decode.boolean(@decode.required(capabilities, "inspect").unwrap()).unwrap(),
  )
  assert_false(
    @decode.boolean(@decode.required(capabilities, "durable_control").unwrap()).unwrap(),
  )
  let quantities = @decode.required(root, "quantities").unwrap()
  let quantity = @decode.open_object(@decode.element_at(quantities, 0).unwrap()).unwrap()
  assert_eq(
    @decode.text(@decode.required(quantity, "kind").unwrap()).unwrap(),
    "unknown",
  )
  let map = @decode.open_object(@decode.required(root, "logical_map").unwrap()).unwrap()
  let steps = @decode.required(map, "steps").unwrap()
  // Independent authored chain has three logical occurrences, irrespective of
  // a backend's physical task fusion. This does not execute its row filter.
  assert_eq(@decode.array_length(steps), Some(3))
  guard prepared is Computation(original) else { fail("unexpected Effect") }
  assert_eq(
    @decode.text(@decode.required(map, "program_definition_cid").unwrap()).unwrap(),
    @run_host.prepared_client_identity(original).program_definition_cid,
  )
}

///|
test "Native Local explain SQL SELECT1 is a static observation without a Run" {
  let wire = local_static_plan_view(explain_fixture("SELECT 1 AS n", Sql))
  let root = @decode.open_object(local_input_cursor(wire)).unwrap()
  assert_eq(
    @decode.text(@decode.required(root, "observation").unwrap()).unwrap(),
    "static",
  )
  assert_eq(
    @decode.safe_integer(@decode.required(root, "provider_io").unwrap()).unwrap(),
    0L,
  )
  assert_true(@decode.lookup(root, "run_ref") is None)
}

///|
test "Native Local explain keeps the existing bounded PlanView refusal" {
  let preparation = explain_fixture(explain_fixture_chain, Json)
  let issue = try {
    ignore(local_static_plan_view(preparation, max_bytes=16))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "LocalStaticPlanUnavailable")
}

///|
test "Native Local explain does not replace original Effect preparation with an empty journal" {
  let original = @local_host.native_client_submitted_preparation(
    local_effect_prefix_fixture_preparation(),
  )
  let issue = try {
    ignore(local_static_plan_view(original))
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "LocalStaticEffectPlanUnavailable")
}
