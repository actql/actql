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
  let environment = explain_fixture_environment()
  let context = @frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    model_tasks=@checked.checking_environment_model_tasks(environment),
  ).unwrap()
  @local_host.prepare_native_client_program(
    document,
    format,
    environment,
    None,
    Some(context),
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
test "Native Effect explain keeps declared approval separate from current permission" {
  let original = @local_host.native_client_submitted_preparation(
    local_effect_prefix_fixture_preparation(),
  )
  let wire = local_static_plan_view(original)
  assert_true(
    wire.contains("\"version\":\"actql-effectful-static-plan-view/0.1\""),
  )
  assert_true(wire.contains("\"scope\":\"computation_component\""))
  assert_true(wire.contains("\"effect_id\":\"save\""))
  assert_true(wire.contains("\"effect_kind\":\"create\""))
  assert_true(
    wire.contains(
      "sha256:1be9426a9b8809a531aae1c2cac2bfe7bef35b4fccff982c52da4a4de350190b",
    ),
  )
  assert_true(
    wire.contains(
      "\"minimum_approval\":{\"kind\":\"contract_minimum\",\"value\":\"required\"}",
    ),
  )
  assert_true(
    wire.contains(
      "\"permission\":{\"reason\":\"not_observed\",\"state\":\"unknown\"}",
    ),
  )
  assert_true(
    wire.contains(
      "\"preview\":{\"reason\":\"not_sealed\",\"state\":\"unavailable\"}",
    ),
  )
  assert_true(!wire.contains("run_ref"))
  assert_true(!wire.contains("checkpoint_cid"))
  assert_true(!wire.contains("normalization_journal"))
}

///|
// The authored update and contract golden are independent of the CLI issuer.
let explain_update_document : String =
  #|{"version":"actql/0.1","id":"local-update","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"number","nullable":false}},"rows":[{"id":"original-id","value":1}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"},"id":"id","set":{"Name":{"field":"value"}}}}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}

///|
let explain_update_environment_wire : String =
  #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[],"evidence_bundle_cid":"sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283","mapping_ref":"mapping:crm.account.v1","minimum_approval":"none","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]},{"effect_kind":"update","permissions":["scope:update"],"selector_class":"ids","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","row_mapping":{"Name":{"field":"value","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"string"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:1208f407bf69f466944f865797ce7407361d822605d1fbbb502177af4b63958f","version":"salesforce-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}

///|
fn explain_update_fixture() -> @local_host.NativeClientPreparation {
  let environment = @run_host.admit_client_check_environment(
    explain_update_environment_wire,
    "sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  @local_host.prepare_native_client_program(
    explain_update_document,
    Json,
    environment,
    None,
    None,
    [],
    @run_host.client_standard_effect_computation_limits(),
  ).unwrap()
}

///|
test "Native update explain retains the original unit Program environment and declared Mapping" {
  let preparation = explain_update_fixture()
  guard preparation is EffectComputation(original) else {
    fail("missing original Effect preparation")
  }
  let wire = local_static_plan_view(preparation)
  let value = @publication.parse_interactive_run_control_shape(
    "effectful_static_plan_view", wire, 65536, 8192, 64,
  ).unwrap()
  ignore(value)
  let root = @decode.open_object(local_input_cursor(wire)).unwrap()
  assert_eq(
    @decode.text(@decode.required(root, "program_definition_cid").unwrap()).unwrap(),
    @run_host.prepared_client_effect_identity(original).program_definition_cid,
  )
  assert_eq(
    @decode.text(@decode.required(root, "check_environment_cid").unwrap()).unwrap(),
    "sha256:dde2a4ab7160672ec8f2fc7fc49e1b9e0ebd7992b7a60851d57e5a9ea161694b",
  )
  assert_true(wire.contains("\"effect_kind\":\"update\""))
  assert_true(
    wire.contains(
      "sha256:ce8b7dc9c08beafcd15440c15026a857361f9e04a2c1d9dec4bc8c9ab9f40283",
    ),
  )
  assert_true(wire.contains("\"unit_id\":\"source\""))
  assert_true(wire.contains("\"declared_target\":\"connector://crm/account\""))
  assert_true(
    wire.contains(
      "\"minimum_approval\":{\"kind\":\"contract_minimum\",\"value\":\"none\"}",
    ),
  )
  assert_true(
    wire.contains(
      "\"permission\":{\"reason\":\"not_observed\",\"state\":\"unknown\"}",
    ),
  )
  assert_true(wire.contains("\"provider_io\":0"))
  assert_true(!wire.contains("run_ref"))
  assert_true(!wire.contains("checkpoint_cid"))
}

///|
test "Native Effect explain preserves the complete wire limit without changing the original preparation" {
  let preparation = explain_update_fixture()
  let wire = local_static_plan_view(preparation)
  let exact_bytes = @utf8.encode(wire).length()
  assert_eq(local_static_plan_view(preparation, max_bytes=exact_bytes), wire)
  for limit in [exact_bytes - 1, 1] {
    let issue = try {
      ignore(local_static_plan_view(preparation, max_bytes=limit))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(issue, "LocalStaticEffectPlanUnavailable")
  }
  assert_eq(local_static_plan_view(preparation), wire)
}

///|
test "Native human explain displays original logical occurrences without choosing placement" {
  let wire = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  )
  let display = local_explain_reply(wire, false, verbose=true)
  assert_true(display.has_prefix("ActQL EXPLAIN · static\n"))
  assert_true(
    display.contains("Run: not started by EXPLAIN\nProvider I/O: 0\n"),
  )
  assert_true(display.contains("Logical occurrences: 3\n"))
  for operator in ["values", "filter", "select"] {
    assert_true(display.contains("Operator: \"" + operator + "\"\n"))
  }
  for name in ["original", "filtered", "selected"] {
    assert_true(display.contains("Names: [\"" + name + "\"]\n"))
  }
  assert_true(
    display.contains(
      "Site / Engine / pushdown: not represented in this static projection\n",
    ),
  )
  assert_false(display.contains("Engine: DuckDB"))
  assert_false(display.contains("Pushdown: selected"))
  assert_false(display.contains("Actual rows:"))
}

///|
test "Native human explain preserves every original port locator without adjacency edges" {
  let wire = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  )
  let display = local_explain_reply(wire, false, verbose=true)
  let value = @json.parse(wire) catch { _ => fail("invalid original Plan") }
  let map = local_explain_field(value, "logical_map")
  for step in local_explain_items(local_explain_field(map, "steps")) {
    assert_true(
      display.contains(
        "Step " + local_explain_literal(local_explain_field(step, "step_id")),
      ),
    )
    for port in local_explain_items(local_explain_field(step, "ports")) {
      assert_true(
        display.contains(
          "Source: " +
          local_explain_literal(local_explain_field(port, "source")) +
          "\n",
        ),
      )
    }
  }
  assert_false(display.contains("[1] -> [2]"))
  assert_false(display.contains("Dependencies: previous"))
}

///|
test "Native human Effect explain preserves declared targets and unknown decisions" {
  let wire = local_static_plan_view(explain_update_fixture())
  let display = local_explain_reply(wire, false, verbose=true)
  assert_true(
    display.contains(
      "computation CID above covers only its computation component",
    ),
  )
  assert_true(display.contains("Unit: \"source\"\n"))
  assert_true(display.contains("Effect \"save\" \"update\"\n"))
  assert_true(
    display.contains("\"declared_target\":\"connector://crm/account\""),
  )
  assert_true(
    display.contains("\"kind\":\"contract_minimum\",\"value\":\"none\""),
  )
  assert_true(
    display.contains(
      "A contract minimum is not current permission or an approval decision.",
    ),
  )
  for
    label in [
      "Permission", "Gate", "Approval", "Resolved targets", "Changed values",
    ] {
    assert_true(
      display.contains(
        label + ": {\"reason\":\"not_observed\",\"state\":\"unknown\"}\n",
      ),
    )
  }
  assert_true(
    display.contains(
      "Preview: {\"reason\":\"not_sealed\",\"state\":\"unavailable\"}\n",
    ),
  )
  assert_false(display.contains("Permission: allowed"))
  assert_false(display.contains("Checkpoint: none"))
}

///|
test "Native human Effect explain does not turn required approval into a human-only gate" {
  let wire = local_static_plan_view(
    @local_host.native_client_submitted_preparation(
      local_effect_prefix_fixture_preparation(),
    ),
  )
  let display = local_explain_reply(wire, false, verbose=true)
  assert_true(
    display.contains("\"kind\":\"contract_minimum\",\"value\":\"required\""),
  )
  assert_true(
    display.contains(
      "Approval: {\"reason\":\"not_observed\",\"state\":\"unknown\"}",
    ),
  )
  assert_false(display.contains("human approval required"))
}

///|
test "Native explain JSON preserves the exact original response in both alternatives" {
  for
    prepared in [
      explain_fixture("SELECT 1 AS n", Sql),
      explain_update_fixture(),
    ] {
    let wire = local_static_plan_view(prepared)
    assert_eq(local_explain_reply(wire, true), wire)
    ignore(local_explain_reply(wire, false, verbose=true))
    assert_eq(local_static_plan_view(prepared), wire)
  }
}

///|
test "Native human explain quotes authored terminal controls without executing them" {
  assert_eq(
    local_explain_literal(Json::string("name\n\r\t\u001b[31m\"\\")),
    "\"name\\n\\r\\t\\u001b[31m\\\"\\\\\"",
  )
  let wire = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  )
  // A shape-only display vector, not a new compiler original or authority.
  let changed = wire.replace(
    old="\"names\":[\"original\"]",
    new="\"names\":[\"name\\n\\u001b[31m\"]",
  )
  assert_true(changed != wire)
  let display = local_explain_reply(changed, false, verbose=true)
  assert_true(display.contains("Names: [\"name\\n\\u001b[31m\"]\n"))
  assert_false(display.contains("\u001b"))
}

///|
test "Native human explain rejects malformed closed views instead of displaying partial facts" {
  let wire = local_static_plan_view(explain_fixture("SELECT 1 AS n", Sql))
  for
    rejected in [
      "{}",
      wire.replace(old="actql-plan-view/0.1", new="unknown-plan"),
      wire.replace(old="\"provider_io\":0", new="\"provider_io\":1"),
      wire.replace(
        old="\"provider_io\":0",
        new="\"provider_io\":0,\"provider_io\":0",
      ),
      wire.replace(old="\"static_plan\":true", new="\"static_plan\":null"),
    ] {
    assert_true(rejected != wire)
    let issue = try {
      ignore(local_explain_reply(rejected, false))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_true(
      issue == "LocalExplainDisplayUnavailable" ||
      issue == "LocalInputNotAdmitted",
    )
  }
}

///|
test "Native human explain admits the exact UTF8 display bound and refuses one byte less" {
  let wire = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  )
  let display = local_explain_reply(wire, false, verbose=true)
  let bytes = @utf8.encode(display).length()
  assert_eq(
    local_explain_reply(wire, false, max_bytes=bytes, verbose=true),
    display,
  )
  for bound in [bytes - 1, 0, -1] {
    let issue = try {
      ignore(local_explain_reply(wire, false, max_bytes=bound, verbose=true))
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(issue, "LocalExplainDisplayLimit")
  }
  assert_eq(local_explain_reply(wire, true), wire)
}

///|
test "Human explain defaults to numbered operations and resolves actual input locators" {
  let wire = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  )
  let display = local_explain_reply(wire, false)
  assert_true(display.contains("Plan: 3 logical steps"), msg=display)
  assert_true(display.contains("1. values · \"original\""), msg=display)
  assert_true(display.contains("2. filter · \"filtered\""), msg=display)
  assert_true(display.contains("3. select · \"selected\""), msg=display)
  assert_true(
    display.contains("Input 1: relation from step 1 output 1"),
    msg=display,
  )
  assert_true(
    display.contains("Input 1: relation from step 2 output 1"),
    msg=display,
  )
  assert_false(display.contains("sha256:"))
  assert_true(display.contains("unknown"))
  assert_true(display.contains("not execution order"))
  assert_eq(local_explain_reply(wire, true, verbose=true), wire)
}

///|
test "Human explain summary keeps declared Effects separate from current decisions" {
  let wire = local_static_plan_view(explain_update_fixture())
  let display = local_explain_reply(wire, false)
  assert_true(display.contains("Declared Effects: 1"))
  assert_true(display.contains("Declared target: \"connector://crm/account\""))
  assert_true(display.contains("Minimum approval: \"none\" (contract minimum)"))
  assert_true(display.contains("Permission: \"unknown\" (\"not_observed\")"))
  assert_true(display.contains("Preview: \"unavailable\" (\"not_sealed\")"))
  assert_false(display.contains("sha256:"))
  assert_false(display.contains("Permission: allowed"))
}

///|
test "Human explain summary resolves explicit locators independently of display order" {
  let wire = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  )
  let value = @json.parse(wire) catch { _ => fail("invalid plan") }
  let map = local_explain_field(value, "logical_map")
  let steps = local_explain_items(local_explain_field(map, "steps"))
  guard map is Object(fields) else { fail("missing map") }
  fields["steps"] = Json::array([steps[2], steps[0], steps[1]])
  let output = { text: StringBuilder(), remaining: 65536, }
  local_explain_computation(output, value)
  let text = output.text.to_string()
  assert_true(text.contains("1. select"))
  assert_true(text.contains("Input 1: relation from step 3 output 1"))
  assert_true(text.contains("3. filter"))
  assert_true(text.contains("Input 1: relation from step 2 output 1"))
}

///|
test "Human explain summary remains bounded and quotes terminal controls" {
  let wire = local_static_plan_view(
    explain_fixture(explain_fixture_chain, Json),
  )
  let changed = wire.replace(
    old="\"names\":[\"original\"]",
    new="\"names\":[\"name\\n\\u001b[31m\"]",
  )
  let text = local_explain_reply(changed, false)
  assert_true(text.contains("name\\n\\u001b[31m"))
  assert_false(text.contains("\u001b"))
  let bytes = @utf8.encode(text).length()
  assert_eq(local_explain_reply(changed, false, max_bytes=bytes), text)
  let issue = try {
    ignore(local_explain_reply(changed, false, max_bytes=bytes - 1))
    "accepted"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(issue, "LocalExplainDisplayLimit")
}

///|
test "Human explain summary distinguishes output ports and preserves forwarded outputs" {
  // Presentation-only shape vector, never compiler or execution evidence.
  let plan = @json.parse(
    local_static_plan_view(explain_fixture(explain_fixture_chain, Json)),
  ) catch {
    _ => fail("invalid fixture")
  }
  let steps = local_explain_items(
    local_explain_field(local_explain_field(plan, "logical_map"), "steps"),
  )
  let ports = local_explain_items(local_explain_field(steps[0], "ports"))
  let output = @json.parse(local_explain_literal(ports[0])) catch {
    _ => fail("invalid port")
  }
  guard output is Object(fields) else { fail("missing port") }
  let port_id = Json::string("sha256:" + "b".repeat(64))
  fields["port_id"] = port_id
  fields["port_ordinal"] = Json::number(1)
  fields["source"] = Json::object(
    Map([
      ("kind", Json::string("logical_output")),
      ("step_id", local_explain_field(steps[0], "step_id")),
      ("output_port_id", port_id),
    ]),
  )
  ports.push(output)
  let next_ports = local_explain_items(local_explain_field(steps[1], "ports"))
  for port in next_ports {
    guard port is Object(fields) else { fail("missing next port") }
    fields["source"] = local_explain_field(output, "source")
  }
  let display = { text: StringBuilder(), remaining: 65536, }
  local_explain_computation(display, plan)
  let text = display.text.to_string()
  assert_true(text.contains("Output 2: relation"), msg=text)
  assert_true(text.contains("Input 1: relation from step 1 output 2"), msg=text)
  assert_true(
    text.contains("Output 1: relation from step 1 output 2"),
    msg=text,
  )
}

///|
test "Native Local compilation and explain use the checked authored row demand" {
  for count in [101, 1000] {
    let rows = Array::makei(count, index => "{\"id\":" + index.to_string() + "}").join(
      ",",
    )
    let document = explain_fixture_chain.replace(
      old="{\"id\":1},{\"id\":2}",
      new=rows,
    )
    let preparation = explain_fixture(document, Json)
    guard preparation is Computation(prepared) else {
      fail("expected a pure checked Program")
    }
    let limits = @run_host.prepared_client_values_sequence_limits(prepared)
    assert_eq(limits.max_rows, count)
    let wire = local_static_plan_view(preparation)
    let root = @decode.open_object(local_input_cursor(wire)).unwrap()
    assert_eq(
      @decode.text(@decode.required(root, "version").unwrap()).unwrap(),
      "actql-plan-view/0.1",
    )
    assert_eq(
      @decode.safe_integer(@decode.required(root, "provider_io").unwrap()).unwrap(),
      0L,
    )
  }
}
