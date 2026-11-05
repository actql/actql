///|
// Original selected installation DATA shared by the initial quote and the
// later checked Model demand. This is not a physical Model profile or Allow.
let effect_model_plan_limits : @resources.LedgerLimits = {
  planning_work: 17,
  attempts: 4,
  holdings: 3,
  transfer_bytes: 2048L,
  retained_bytes: 1000L,
  execution_bytes: 2000L,
}

///|
// Real checked Model/Effect/Run originals with independently selected finite
// test bounds. These component ports perform no Source/Model IO or permission.
fn effect_model_plan_source(
  declaration? : @row_source_host.RowDeclaration? = None,
  lookup_policy? : Json? = None,
  plural? : Bool = false,
) -> (@checked.CheckEnvironment, String) raise {
  let task =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"text":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let parsed = @json.parse(source_query_original_environment)
  guard parsed is Object(fields) else { fail("Model plan Environment") }
  fields.remove("evidence_bundle_cid")
  fields["model_task_contracts"] = @json.parse("[" + task + "]")
  if lookup_policy is Some(selected) {
    guard fields["host_policy_profile"] is Object(policy) else {
      fail("Model fixture Host policy")
    }
    policy["lookup_execution"] = selected
  }
  if declaration is Some(original) {
    let (schemas, capabilities) = @row_source_host.row_declaration_evidence_members(
      original,
    )
    fields["connector_catalogs"] = effect_plan_fixture_members(
      fields["connector_catalogs"],
      [original.catalog],
    )
    fields["contract_registry"] = effect_plan_fixture_members(
      fields["contract_registry"],
      original.contracts,
    )
    fields["source_views"] = effect_plan_fixture_members(
      fields["source_views"],
      original.view_bodies,
    )
    fields["schema_snapshots"] = effect_plan_fixture_members(
      fields["schema_snapshots"],
      schemas,
    )
    fields["connector_capabilities"] = effect_plan_fixture_members(
      fields["connector_capabilities"],
      capabilities,
    )
    guard fields["connector_manifest"] is Object(manifest) else {
      fail("Model fixture manifest")
    }
    manifest["connectors"] = effect_plan_fixture_members(
      manifest["connectors"],
      [original.manifest_entry],
    )
  }
  let unsigned = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  let cid = "sha256:" + @sha.hex(@utf8.encode(unsigned))
  fields["evidence_bundle_cid"] = @json.parse("\"" + cid + "\"")
  let wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  let environment = @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"model-effect-plan","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":1,"text":"hello"}]},"as":"seed"},{"assert_rows":{"unique_by":["id"]},"as":"joined"},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"inferred"},{"join":{"with":"joined","kind":"inner","cardinality":"one_to_one","on":[{"left":"id","right":"id"}],"select":{"id":"right.id"}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let document = if plural {
    let authored =
      #|{"version":"actql/0.1","id":"plural-model-effect","stages":[{"id":"input","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":1,"text":"hello"},{"id":2,"text":"world"}]},"as":"items"}],"results":{"rows":{"from":"items","fields":["id","text"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}},{"id":"combine","inputs":{"first":{"result":{"stage":"first","result":"rows"}},"second":{"result":{"stage":"second","result":"rows"}}},"steps":[{"from":"first","join":{"with":"second","kind":"inner","cardinality":"one_to_one","max_output_rows":2,"on":[{"left":"id","right":"id"}],"select":{"id":"left.id"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"combine","result":"rows"}}}}
    authored
  } else {
    document
  }
  (environment, document)
}

///|
fn effect_model_plan_inputs() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  ClientInstalledEffectModelDemand,
) raise {
  let (environment, document) = effect_model_plan_source()
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  effect_model_plan_for_prepared(prepared)
}

///|
fn effect_model_plan_for_prepared(
  prepared : @publication_host.PreparedClientEffectComputation,
  acquired? : Bool = false,
  infers? : Array[@publication_host.ClientInferPlanGraph] = [],
) -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  ClientInstalledEffectModelDemand,
) {
  let occurrence = @publication_host.prepared_client_effect_infer_occurrences(
      prepared,
    ).unwrap()[0]
  let execution = effect_model_plan_execution(occurrence)
  let graph = if !infers.is_empty() {
    infers[0]
  } else {
    @publication_host.issue_installed_client_composed_infer_plan_graph(
      occurrence,
      execution,
      @publication_host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ).unwrap()
  }
  effect_model_plan_for_graph(prepared, graph, acquired~, infers~)
}

///|
fn effect_model_plan_for_graph(
  prepared : @publication_host.PreparedClientEffectComputation,
  graph : @publication_host.ClientInferPlanGraph,
  acquired? : Bool = false,
  infers? : Array[@publication_host.ClientInferPlanGraph] = [],
) -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  ClientInstalledEffectModelDemand,
) {
  let occurrence = graph.occurrence
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
    infer=if infers.is_empty() { Some(graph) } else { None },
    infers~,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "Model-plan", "same-original", "2026-10-26T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = if acquired {
    @publication_host.client_effect_allowed_infer_run(allowed).unwrap()
  } else {
    @publication_host.client_effect_allowed_infer_run_with_policy_body(
      allowed,
      Some(
        "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      ),
      Some(
        "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
      ),
      10000,
      1000,
      20,
    ).unwrap()
  }
  let model = prepare_installed_effect_model_demand(
    prepared, compiled, compilation, definition, occurrence, graph, effect_model_plan_limits,
    500L, 700L, 20, 20, 20,
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "model-effect-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  (prepared, request, contracts, model)
}

///|
test "Effect Model read window projects its original selected demand without another quote" {
  let (_, _, _, model) = effect_model_plan_inputs()
  let window = installed_effect_model_read_window(model)
  assert_eq(window, [500L, 700L])
  window[0] = 0L
  assert_eq(installed_effect_model_read_window(model), [500L, 700L])
}

///|
fn effect_model_plan_fixture(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  contracts : ClientInstalledSequenceContracts,
  model : ClientInstalledEffectModelDemand,
  factory_calls : Ref[Int],
  content? : ClientInstalledEffectContentPreparation? = None,
  host_input? : Bool = false,
  stage_index? : Int = 0,
) -> ClientInstalledEffectManagedPlan {
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let members = [extent]
  if host_input {
    members.push(
      prepare_installed_effect_host_input_capture_recipe_extent(
        "preview",
        [
          @execution.execution_capacity(8L, 8L).unwrap(),
          @execution.execution_capacity(0L, 0L).unwrap(),
        ],
        4096,
        128,
        16,
      ).unwrap(),
    )
  }
  let operation = prepare_installed_effect_operation_demand(
    prepared,
    stage_index,
    "save",
    members,
    [extent],
  ).unwrap()
  prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [operation],
    model=Some(model),
    content~,
    provider_factory=capacity => {
      factory_calls.val += 1
      [
        @local.managed_provider(_ => true, _ => Some(capacity), (_, _, _, _, _) => {
          Err(@connector.ComputeUnsupported)
        }),
      ]
    },
  ).unwrap()
}

///|
test "Model Effect plan retains exact checked binding and one provider selection" {
  let (prepared, request, contracts, model) = effect_model_plan_inputs()
  let calls = Ref(0)
  let plan = effect_model_plan_fixture(
    prepared, request, contracts, model, calls,
  )
  assert_eq(calls.val, 1)
  assert_true(plan.model is Some(original) && physical_equal(original, model))
  assert_true(physical_equal(plan.prepared, prepared))
  assert_eq(model.limits.retained_bytes, 2000L)
  assert_eq(model.limits.execution_bytes, 3400L)
  assert_eq(
    plan.limits.planning_work - plan._observed_compute_limits.planning_work,
    17,
  )
  // The policy retains its 100-row ceiling. Before actual rows arrive, only
  // the one member operation and the original Model attempt budget are funded.
  assert_eq(plan.rows, 100)
  assert_eq(
    plan.limits.attempts - plan._observed_compute_limits.attempts,
    effect_model_plan_limits.attempts + 1,
  )
  assert_true(
    plan.limits.retained_bytes >=
    plan._observed_compute_limits.retained_bytes + 2000L,
  )
  assert_true(
    plan.limits.execution_bytes >=
    plan._observed_compute_limits.execution_bytes + 3400L,
  )
  let (foreign, _, _, _) = effect_model_plan_inputs()
  assert_true(
    prepare_installed_effect_model_demand(
      foreign,
      model.compiled,
      model._compilation,
      model.definition,
      model._occurrence,
      model.graph,
      model.limits,
      500L,
      700L,
      20,
      20,
      20,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_effect_model_demand(
      prepared,
      model.compiled,
      model._compilation,
      model.definition,
      model._occurrence,
      model.graph,
      model.limits,
      9223372036854775807L,
      700L,
      20,
      20,
      20,
    )
    is Err(InsufficientCapacity),
  )
  assert_eq(calls.val, 1)
}

///|
test "Model Effect Plan projection refuses a copied or foreign selected demand" {
  let (prepared, request, contracts, model) = effect_model_plan_inputs()
  let plan = effect_model_plan_fixture(
    prepared,
    request,
    contracts,
    model,
    Ref(0),
  )
  assert_true(installed_effect_plan_matches_model_demand(plan, model))
  let copied = { ..model, }
  assert_false(installed_effect_plan_matches_model_demand(plan, copied))
  let (_, _, _, foreign) = effect_model_plan_inputs()
  assert_false(installed_effect_plan_matches_model_demand(plan, foreign))
  let without_model = { ..plan, model: None, }
  assert_false(installed_effect_plan_matches_model_demand(without_model, model))
}

///|
test "Effect Model keeps physical read and bootstrap overlap on the same checked demand" {
  let (prepared, _, _, original) = effect_model_plan_inputs()
  let prepare = bootstrap => {
    prepare_installed_effect_model_demand(
      prepared,
      original.compiled,
      original._compilation,
      original.definition,
      original._occurrence,
      original.graph,
      effect_model_plan_limits,
      17L,
      19L,
      12,
      8,
      4,
      bootstrap=Some(bootstrap),
    )
  }
  let demand = prepare((23L, 29L)).unwrap()
  assert_eq(installed_effect_model_read_window(demand), [17L, 19L])
  assert_eq(
    (demand.bootstrap_retained_bytes, demand.bootstrap_execution_bytes),
    (23L, 29L),
  )
  assert_eq(
    (demand.limits.retained_bytes, demand.limits.execution_bytes),
    (1040L, 2048L),
  )
  assert_true(physical_equal(demand.compiled, original.compiled))
  assert_true(physical_equal(demand.graph, original.graph))
  guard prepare((0L, 29L)) is Err(InsufficientCapacity) else {
    fail("Missing physical bootstrap must not borrow the read window")
  }
}

///|
fn effect_model_plan_execution(
  occurrence : @publication_host.ClientInferOccurrence,
) -> @environment.ModelExecutionContract {
  let execution =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  @publication_host.read_client_infer_occurrence_model_execution(
    occurrence,
    @utf8.encode(execution),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
}

///|
fn effect_models_plan_for_prepared(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> (
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  ClientInstalledEffectModelDemand,
  Array[ClientInstalledEffectModelDemand],
) {
  let graphs = @publication_host.prepared_client_effect_infer_occurrences(
      prepared,
    )
    .unwrap()
    .map(occurrence => {
      @publication_host.issue_installed_client_composed_infer_plan_graph(
        occurrence,
        effect_model_plan_execution(occurrence),
        @publication_host.client_standard_values_sequence_limits(),
        1000000,
        100000,
        100,
      ).unwrap()
    })
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
    infers=graphs,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "plural-effect", "same-original", "2026-11-05T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = @publication_host.client_effect_allowed_infer_run_with_policy_body(
    allowed,
    Some(
      "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    ),
    Some(
      "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    ),
    10000,
    1000,
    20,
  ).unwrap()
  let members = graphs.map(graph => {
    prepare_installed_effect_model_demand(
      prepared,
      compiled,
      compilation,
      definition,
      graph.occurrence,
      graph,
      effect_model_plan_limits,
      500L,
      700L,
      20,
      20,
      20,
    ).unwrap()
  })
  let selected = prepare_installed_effect_models_demand(members).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "plural-effect-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  (request, contracts, selected, members)
}

///|
test "plural Effect demand retains complete original members and funds one shared bootstrap" {
  let (environment, document) = effect_model_plan_source(plural=true)
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let (request, contracts, model, members) = effect_models_plan_for_prepared(
    prepared,
  )
  assert_eq(model.limits.planning_work, 34)
  assert_eq(model.limits.attempts, 8)
  assert_eq(model.limits.retained_bytes, 3500L)
  assert_eq(model.limits.execution_bytes, 6100L)
  assert_eq(model.read_retained_bytes, 1000L)
  assert_eq(model.read_execution_bytes, 1400L)
  assert_true(installed_effect_model_demand_complete(model))
  assert_true(!installed_effect_model_demand_complete(members[0]))
  for
    invalid in [
      [members[0]],
      [members[0], members[0]],
      [members[1], members[0]],
    ] {
    assert_true(
      prepare_installed_effect_models_demand(invalid) is Err(ForeignOriginal),
    )
  }
  let (_, _, _, foreign_members) = effect_models_plan_for_prepared(prepared)
  assert_true(
    prepare_installed_effect_models_demand([members[0], foreign_members[1]])
    is Err(ForeignOriginal),
  )
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let operation = prepare_installed_effect_operation_demand(
    prepared,
    3,
    "save",
    [extent],
    [extent],
  ).unwrap()
  let partial_calls = Ref(0)
  assert_true(
    prepare_installed_effect_managed_plan(
      prepared,
      request,
      [],
      "",
      "",
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      [operation],
      model=Some(members[0]),
      provider_factory=_ => {
        partial_calls.val += 1
        []
      },
    )
    is Err(ForeignOriginal),
  )
  assert_eq(partial_calls.val, 0)
  let calls = Ref(0)
  let plan = effect_model_plan_fixture(
    prepared,
    request,
    contracts,
    model,
    calls,
    stage_index=3,
  )
  assert_eq(calls.val, 1)
  assert_true(installed_effect_plan_matches_model_demand(plan, model))
  assert_eq(plan.model.unwrap().components.unwrap().length(), 2)
}
