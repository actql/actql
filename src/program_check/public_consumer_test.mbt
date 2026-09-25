///|
// Public test-package setup: no private constructor or reissued checked handle.
fn public_program_fixture(
  generated? : Bool = false,
  repeated? : Bool = false,
  max_work? : Int = 10000000,
  document? : Bool = false,
) -> @program_check.CheckedProgram raise {
  let (text, program, environment, evidence, limits) = public_input_fixture(
    generated~,
    repeated~,
  )
  let limits = {
    ..limits,
    compilation: { ..limits.compilation, work: max_work, },
  }
  let outcome = if document {
    @program_check.check_document_with_evidence(
      text,
      environment,
      None,
      evidence,
      limits,
      format=Json,
      source_path="fixture.actql",
    )
  } else {
    @program_check.check_parsed_with_evidence(
      program,
      environment,
      None,
      evidence,
      limits,
    )
  }
  public_checked(outcome)
}

///|
fn public_checked(
  outcome : @program_check.CheckOutcome,
) -> @program_check.CheckedProgram raise {
  match outcome {
    Checked(program) => program
    NeedsInputs(_) => fail("fixture has missing inputs")
    Rejected(diagnostic) => raise @program_check.diagnostic_cause(diagnostic)
  }
}

///|
fn public_effect_preview_canonical(wire : String) -> String {
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 20000,
    max_nodes: 1000,
    max_depth: 20,
  }).unwrap()
  let value = @json.from_source(parsed, 1000, 20, 20000) catch {
    _ => abort("Expected Preview fixture")
  }
  @json.stringify_value(value, 20000, 1000, 20) catch {
    _ => abort("Expected canonical Preview fixture")
  }
}

///|
fn public_effect_plan_limits() -> @results.EffectPlanIdentityLimits {
  {
    max_work: 1000,
    max_fields: 100,
    max_bytes: 20000,
    max_nodes: 1000,
    max_depth: 20,
  }
}

///|
fn public_effect_preview_member(
  id : String,
  mapping_cid : String,
  placeholder : String,
  max_items? : Int = 1,
  target_cid? : String? = None,
  source_name? : String? = None,
) -> String {
  let cid = "sha256:" + "a".repeat(64)
  let effect_identity_cid = "sha256:" +
    (if id == "first" { "b" } else { "c" }).repeat(64)
  "{\"effect_id\":\"" +
  id +
  "\",\"effect_kind\":\"create\",\"target\":\"Object\"," +
  "\"mapping\":\"mapping:crm.account.v1\"," +
  "\"resolved_mapping_contract_cid\":\"" +
  mapping_cid +
  "\",\"effect_identity_cid\":\"" +
  effect_identity_cid +
  (if source_name is Some(source) {
    "\",\"source_result\":\"" + source + "\",\"result_artifact_cid\":\"" + cid
  } else {
    ""
  }) +
  "\",\"preview_strength\":\"full_diff\",\"source_binding_cid\":\"" +
  cid +
  "\",\"capability_evidence_cid\":\"" +
  cid +
  "\",\"authority_scope_cid\":\"" +
  cid +
  "\",\"write_footprint\":{\"kind\":\"exact_targets\"," +
  "\"resource_identity_scheme_cid\":\"" +
  cid +
  "\",\"provider_namespace\":\"provider\",\"provider_boundary_cid\":\"" +
  cid +
  "\",\"resource_kind\":\"Object\",\"provider_object_identity_cids\":" +
  (if target_cid is Some(target) { "[\"" + target + "\"]" } else { "[]" }) +
  "}," +
  "\"count\":0,\"max_items\":" +
  max_items.to_string() +
  ",\"required_permissions\":[\"write\"]," +
  "\"approval\":\"none\",\"on_item_failure\":\"halt\",\"changes\":[]," +
  "\"row_order\":[],\"effect_member_preview_cid\":\"" +
  placeholder +
  "\",\"executed\":false}"
}

///|
fn public_effect_preview_for_static(
  candidate : @program_check.EffectProgramStaticCandidate,
  mapping_cid : String,
  definition_cid? : String? = None,
  semantics_cid? : String? = None,
  environment_cid? : String? = None,
  run_cid? : String? = None,
  plan_cid? : String? = None,
  invocation_cid? : String? = None,
  first_max_items? : Int = 1,
  second_max_items? : Int = 1,
  first_target_cid? : String? = None,
  second_target_cid? : String? = None,
  reverse_members? : Bool = false,
) -> @run_publication.EffectPreviewIdentity {
  let cid = "sha256:" + "a".repeat(64)
  let definition = definition_cid.unwrap_or(
    @program_check.effect_program_static_definition_cid(candidate),
  )
  let semantics = semantics_cid.unwrap_or(
    @program_check.effect_program_static_semantics_cid(candidate),
  )
  let environment = environment_cid.unwrap_or(
    @environment.cid(
      @program_check.effect_program_static_environment(candidate),
    ),
  )
  let run_identity = run_cid.unwrap_or(cid)
  let plan_identity = plan_cid.unwrap_or(cid)
  let invocation_identity = invocation_cid.unwrap_or(cid)
  let authoring_body = "{\"annotations\":[],\"program_definition_cid\":\"" +
    definition +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  let authoring_cid = "sha256:" + @sha.hex(@utf8.encode(authoring_body))
  let first_placeholder = "sha256:" + "b".repeat(64)
  let second_placeholder = "sha256:" + "c".repeat(64)
  let first = public_effect_preview_member(
    "first",
    mapping_cid,
    first_placeholder,
    max_items=first_max_items,
    target_cid=first_target_cid,
    source_name=Some("out"),
  )
  let second = public_effect_preview_member(
    "second",
    mapping_cid,
    second_placeholder,
    max_items=second_max_items,
    target_cid=second_target_cid,
  )
  let members = if reverse_members {
    second + "," + first
  } else {
    first + "," + second
  }
  let raw = "{\"version\":\"actql-effect-preview/0.1\"," +
    "\"sensitivity\":\"private\",\"retention_class\":\"authority-evidence\"," +
    "\"encryption_required\":true,\"program_semantics_cid\":\"" +
    semantics +
    "\",\"program_definition_cid\":\"" +
    definition +
    "\",\"invocation_cid\":\"" +
    invocation_identity +
    "\",\"run_identity_cid\":\"" +
    run_identity +
    "\",\"compiled_plan_cid\":\"" +
    plan_identity +
    "\",\"check_environment_cid\":\"" +
    environment +
    "\",\"authoring_context\":{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    definition +
    "\",\"annotations\":[],\"authoring_context_cid\":\"" +
    authoring_cid +
    "\"},\"barrier_provenance_cids\":[],\"model_derived\":false," +
    "\"model_task_contract_cids\":[],\"model_invocation_evidence_cids\":[]," +
    "\"model_response_artifact_cids\":[],\"effects\":[" +
    members +
    "],\"executed\":false,\"effect_preview_cid\":\"" +
    cid +
    "\"}"
  let canonical = public_effect_preview_canonical(raw)
  let (_, member_cids) = @run_publication.derive_effect_preview_identities(
    canonical, 20000, 1000, 20,
  ).unwrap()
  let members_fixed = public_effect_preview_canonical(
    canonical
    .replace_all(
      old="\"effect_member_preview_cid\":\"" + first_placeholder + "\"",
      new="\"effect_member_preview_cid\":\"" +
        member_cids[if reverse_members { 1 } else { 0 }] +
        "\"",
    )
    .replace_all(
      old="\"effect_member_preview_cid\":\"" + second_placeholder + "\"",
      new="\"effect_member_preview_cid\":\"" +
        member_cids[if reverse_members { 0 } else { 1 }] +
        "\"",
    ),
  )
  let (preview_cid, _) = @run_publication.derive_effect_preview_identities(
    members_fixed, 20000, 1000, 20,
  ).unwrap()
  @run_publication.admit_effect_preview_identity(
    members_fixed.replace_all(
      old="\"effect_preview_cid\":\"" + cid + "\"",
      new="\"effect_preview_cid\":\"" + preview_cid + "\"",
    ),
    run_identity,
    authoring_cid,
    20000,
    1000,
    20,
  ).unwrap()
}

///|
fn public_effect_run_fixture(
  candidate : @program_check.EffectProgramStaticCandidate,
  semantics_cid? : String? = None,
  environment_cid? : String? = None,
) -> (
  @run_publication.RunPublicationAdmission,
  @run_publication.PublicationContract,
  @run_publication.PublicationContract,
) {
  let cid = "sha256:" + "a".repeat(64)
  let definition = @program_check.effect_program_static_definition_cid(
    candidate,
  )
  let semantics = semantics_cid.unwrap_or(
    @program_check.effect_program_static_semantics_cid(candidate),
  )
  let environment = environment_cid.unwrap_or(
    @environment.cid(
      @program_check.effect_program_static_environment(candidate),
    ),
  )
  let template = @run_publication.seal_run_evidence_value(
    "bound_invocation_template",
    "{\"version\":\"actql-bound-invocation-template/0.1\"," +
    "\"program_definition_cid\":\"" +
    definition +
    "\",\"parameter_values_cid\":\"" +
    cid +
    "\",\"invocation_bindings_cid\":\"" +
    cid +
    "\",\"check_environment_cid\":\"" +
    environment +
    "\",\"grammar_manifest_cid\":\"" +
    cid +
    "\",\"required_profile_contracts\":[]," +
    "\"barrier_contract_manifest_cid\":\"" +
    cid +
    "\",\"source_evidence\":\"unbound\"}",
    16384,
    128,
    8,
  ).unwrap()
  let plan = @run_publication.seal_publication_contract(
    "compiled_plan",
    "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"fixture\",\"aoa_ir_version\":\"fixture\"," +
    "\"executable_plan_cid\":\"" +
    cid +
    "\",\"program_definition_cid\":\"" +
    definition +
    "\",\"program_semantics_cid\":\"" +
    semantics +
    "\",\"aoa_contract_cid\":\"" +
    cid +
    "\",\"aoa_logical_cid\":\"" +
    cid +
    "\"}",
    16384,
    128,
    8,
  ).unwrap()
  let prepared = @run_publication.seal_run_evidence_value(
    "prepared_invocation",
    "{\"version\":\"actql-prepared-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @run_publication.run_evidence_value_identity(template) +
    "\",\"compiled_plan_cid\":\"" +
    @run_publication.publication_contract_identity(plan) +
    "\",\"execution_context_cid\":\"" +
    cid +
    "\",\"host_policy_cid\":\"" +
    cid +
    "\",\"policy_decision\":\"allow\"," +
    "\"expires_at\":\"2026-09-25T03:00:00.000Z\"}",
    16384,
    128,
    8,
  ).unwrap()
  let authorization = @run_publication.seal_run_evidence_value(
    "run_authorization",
    "{\"version\":\"actql-run-authorization/0.1\"," +
    "\"prepared_invocation_cid\":\"" +
    @run_publication.run_evidence_value_identity(prepared) +
    "\",\"execution_context_cid\":\"" +
    cid +
    "\",\"host_policy_cid\":\"" +
    cid +
    "\",\"decision\":\"allowed\"}",
    16384,
    128,
    8,
  ).unwrap()
  let admission = @run_publication.admit_run_publication(
    template, prepared, authorization, plan,
  ).unwrap()
  let run = @run_publication.issue_run_definition(
    admission, "scope", "run", cid, "2026-09-24T00:00:00.000Z", "2026-09-25T02:00:00.000Z",
    16384, 128, 8,
  ).unwrap()
  let invocation = @run_publication.seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\"," +
    "\"invocation_template_cid\":\"" +
    @run_publication.run_evidence_value_identity(template) +
    "\",\"observation_set_cid\":\"" +
    cid +
    "\"}",
    16384,
    128,
    8,
  ).unwrap()
  (admission, run, invocation)
}

///|
test "checked Program retains its exact admitted Environment owner" {
  let (_, source, configured, evidence, limits) = public_input_fixture()
  let checked = public_checked(
    @program_check.check_parsed_with_evidence(
      source,
      configured,
      None,
      evidence,
      limits,
    ),
  )
  let retained = @program_check.checked_environment(checked)
  let references = @program_check.checked_catalog_references(checked)
  assert_true(
    physical_equal(
      @environment.contract_registry_environment(
        @environment.catalog_registry(
          @environment.reference_contents(references),
        ),
      ),
      retained,
    ),
  )
  assert_true(
    physical_equal(
      retained,
      @program_check.checking_environment_wire(configured),
    ),
  )
  let (_, _, foreign, _, _) = public_input_fixture()
  assert_eq(
    @environment.cid(retained),
    @environment.cid(@program_check.checking_environment_wire(foreign)),
  )
  assert_false(
    physical_equal(retained, @program_check.checking_environment_wire(foreign)),
  )
}

///|
test "Effect computation candidate retains owners without admitting execution" {
  let (plain, _, environment, evidence, limits) = public_input_fixture()
  let text = plain.replace(
    old="\"id\":\"consumer\",\"inputs\":",
    new="\"id\":\"consumer\",\"effects\":{\"save\":{\"store\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.store.v1\",\"from\":{\"result\":\"out\"}}}},\"inputs\":",
  )
  let program = @syntax.parse(
    text,
    limits.input,
    format=Json,
    source_path="effect-fixture.actql",
  ).unwrap()
  match
    @program_check.check_parsed_with_evidence(
      program,
      environment,
      None,
      evidence,
      limits,
    ) {
    Rejected(diagnostic) =>
      match @program_check.diagnostic_cause(diagnostic) {
        Source(UnsupportedEffects(_)) => ()
        _ => fail("ordinary checker admitted an unclosed Effect")
      }
    _ => fail("ordinary checker admitted an unclosed Effect")
  }
  let candidate = @program_check.prepare_effect_computation_candidate(
    program,
    environment,
    None,
    evidence,
    limits,
    1,
    1,
  ).unwrap()
  let headers = @program_check.effect_computation_headers(candidate)
  assert_true(physical_equal(@syntax.effect_headers_owner(headers), program))
  assert_eq(@syntax.effect_header_count(headers), 1)
  assert_eq(
    @syntax.effect_header_kind(@syntax.effect_header_at(headers, 0).unwrap()),
    "store",
  )
  let results = @program_check.effect_computation_stage_results(candidate)
  let source = @stages.operations_source(@results.operations(results))
  assert_eq(@stages.stage_count(source), 2)
  assert_true(
    @publication.lookup(@results.stage_at(results, 1).unwrap(), "out")
    is Some(_),
  )
  let bound = @results.bind_effect_results(headers, results, 100).unwrap()
  assert_eq(@results.effect_result_binding_count(bound), 1)
  assert_true(
    physical_equal(
      @program_check.effect_computation_environment(candidate),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let references = @program_check.effect_computation_catalog_references(
    candidate,
  )
  assert_true(
    physical_equal(
      @environment.contract_registry_environment(
        @environment.catalog_registry(
          @environment.reference_contents(references),
        ),
      ),
      @program_check.checking_environment_wire(environment),
    ),
  )
  let mappings = @environment.check_mapping_contract_shapes(
    @program_check.effect_computation_environment(candidate),
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
    1000,
  ).unwrap()
  assert_true(
    @program_check.close_effect_computation_static(candidate, mappings, {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    })
    is Err(_),
  )
  match
    @program_check.prepare_effect_computation_candidate(
      program,
      environment,
      None,
      evidence,
      limits,
      1,
      0,
    ) {
    Err(Headers(issue)) =>
      assert_eq(@syntax.effect_header_issue_kind(issue), BudgetExceeded)
    _ => fail("unmetered Effect header escaped")
  }
  let (_, plain_program, _, _, _) = public_input_fixture()
  assert_true(
    @program_check.prepare_effect_computation_candidate(
      plain_program,
      environment,
      None,
      evidence,
      limits,
      1,
      1,
    )
    is Err(MissingEffects),
  )
  let malformed = @syntax.parse(
    text.replace(
      old="\"store\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.store.v1\",\"from\":{\"result\":\"out\"}}",
      new="\"store\":{}",
    ),
    limits.input,
    format=Json,
  ).unwrap()
  assert_true(
    @program_check.prepare_effect_computation_candidate(
      malformed,
      environment,
      None,
      evidence,
      limits,
      1,
      1,
    )
    is Err(Headers(_)),
  )
  let with_bindings = @syntax.parse(
    text.replace(
      old="\"id\":\"public-reader\",",
      new="\"id\":\"public-reader\",\"bindings\":{\"b\":{\"type\":\"string\"}},",
    ),
    limits.input,
    format=Json,
  ).unwrap()
  match
    @program_check.prepare_effect_computation_candidate(
      with_bindings,
      environment,
      None,
      evidence,
      limits,
      1,
      1,
    ) {
    Err(Computation(Source(UnsupportedBindings(_)))) => ()
    _ => fail("Effect candidate bypassed the unrelated binding audit")
  }
}

///|
fn public_effect_mapping_closure(
  generated : Bool,
  split_source? : Bool = false,
  split_intermediate? : Bool = false,
  split_before? : Bool = false,
) -> Unit raise {
  let (plain, _, _, evidence, base_limits) = public_input_fixture(generated~)
  let plain = if split_before {
    plain.replace(
      old="},{\"id\":\"consumer\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"producer\",\"result\":\"out\"}}}",
      new="},{\"id\":\"middle\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"producer\",\"result\":\"out\"}}},\"steps\":[{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\",\"fields\":[\"value\"]},\"edges\":{\"from\":\"rows\",\"source\":\"id\",\"target\":\"id\",\"fields\":[]}},\"as\":\"g\"},{\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{\"from\":\"normalized\",\"node_rows\":true,\"as\":\"projected\"},{\"from\":\"projected\",\"filter\":\"true\",\"as\":\"selected\"}],\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\",\"value\"]}}},{\"id\":\"consumer\",\"inputs\":{\"rows\":{\"result\":{\"stage\":\"middle\",\"result\":\"out\"}}}",
    )
  } else {
    plain
  }
  let limits : @program_check.CheckLimits = if split_before {
    {
      input: { ..base_limits.input, max_stages: 3, },
      compilation: {
        ..base_limits.compilation,
        structure: {
          ..base_limits.compilation.structure,
          stages: 3,
          steps: 10,
          results: 3,
        },
      },
    }
  } else {
    base_limits
  }
  let program = @syntax.parse(
    plain
    .replace(
      old="\"id\":\"consumer\",\"inputs\":",
      new="\"id\":\"consumer\",\"effects\":{\"first\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"out\"},\"max_items\":{\"$param\":\"n\"}}},\"second\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{\"Name\":8},\"max_items\":1}}},\"inputs\":",
    )
    .replace(
      old="\"results\":{\"out\":{\"from\":{\"stage\":\"consumer\",\"result\":\"out\"}}}",
      new="\"results\":{\"published\":{\"from\":{\"stage\":\"consumer\",\"result\":\"out\"}}}",
    )
    .replace(
      old="{\"take\":1,\"as\":\"selected\"}",
      new=if split_source {
        "{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\",\"fields\":[\"value\"]},\"edges\":{\"from\":\"rows\",\"source\":\"id\",\"target\":\"id\",\"fields\":[]}},\"as\":\"g\"},{\"from\":\"g\",\"normalize_graph\":true,\"as\":\"normalized\"},{\"from\":\"normalized\",\"node_rows\":true,\"as\":\"projected\"},{\"from\":\"projected\",\"filter\":\"true\",\"as\":\"selected\"}"
      } else {
        "{\"take\":1,\"as\":\"selected\"}"
      },
    )
    .replace(
      old="\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\",\"value\"]}}}",
      new=if split_intermediate {
        "\"results\":{\"out\":{\"from\":\"projected\",\"fields\":[\"id\",\"value\"]}}}"
      } else {
        "\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\",\"value\"]}}}"
      },
    ),
    limits.input,
    format=Json,
  ).unwrap()
  let target_schema = "{\"additional_properties\":false,\"fields\":{\"Id\":{\"nullable\":false,\"type\":\"string\"},\"Name\":{\"nullable\":true,\"type\":\"number\"}},\"nullable\":false,\"type\":\"object\"}"
  let target_schema_cid = "sha256:" + @sha.hex(@utf8.encode(target_schema))
  let mapping_before = "{\"connector_manifest_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"conversions\":[],"
  let mapping_after = "\"mapping_ref\":\"mapping:crm.account.v1\",\"minimum_approval\":\"none\",\"permission_rules\":[{\"effect_kind\":\"create\",\"permissions\":[\"scope:create\"],\"selector_class\":\"none\",\"write_fields\":[\"Name\"]}],\"primary_identity\":\"Id\",\"required_fields\":[],\"required_permissions\":[],\"resource_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"row_mapping\":{\"Name\":{\"field\":\"value\",\"null_behavior\":\"reject\"}},\"schema\":\"actql.mapping_contract/0.1\",\"target_ref\":\"connector://crm/account\",\"target_schema\":" +
    target_schema +
    ",\"target_schema_identity\":\"" +
    target_schema_cid +
    "\",\"version\":\"salesforce-v1\",\"writable_fields\":[\"Name\"]}"
  let mapping_cid = "sha256:" +
    @sha.hex(@utf8.encode(mapping_before + mapping_after))
  let mapping_body = mapping_before +
    "\"mapping_contract_cid\":\"" +
    mapping_cid +
    "\"," +
    mapping_after
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_construction_edges\":1000,\"max_graph_construction_input_rows\":1000,\"max_graph_construction_nodes\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[" +
    mapping_body +
    "],\"model_task_contracts\":[],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let wire = @environment.read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let environment = @program_check.checking_environment(
    wire,
    { text_time: false, veca: false, },
    {
      rela: true,
      sga: split_source || split_before,
      tea: false,
      calendar: false,
      text_rank: false,
    },
  )
  match
    @program_check.prepare_effect_computation_candidate(
      program,
      environment,
      None,
      evidence,
      limits,
      1,
      2,
    ) {
    Err(Headers(issue)) =>
      assert_eq(@syntax.effect_header_issue_kind(issue), BudgetExceeded)
    _ => fail("partial multi-member Effect inventory escaped")
  }
  let candidate = @program_check.prepare_effect_computation_candidate(
    program,
    environment,
    None,
    evidence,
    limits,
    2,
    2,
  ).unwrap()
  let mappings = @environment.check_mapping_contract_shapes(
    wire,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
    1000,
  ).unwrap()
  let static_candidate = @program_check.close_effect_computation_static(
    candidate,
    mappings,
    {
      max_members: 2,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  ).unwrap()
  let computation = @program_check.effect_program_static_checked_computation(
    static_candidate,
  )
  assert_true(@program_check.checked_program_has_effects(computation))
  let source_identity = @program_check.source_identity(computation)
  let selected_profiles = @program_check.selected_expression_profiles(
    computation,
  )
  let owners = Array::makei(@program_check.unit_count(computation), stage => {
    let pipeline = @program_check.unit_pipeline(computation, stage).unwrap()
    let prepared = @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 100000,
      max_identifier_bytes: 10000,
    }).unwrap()
    let values = @parameter_refs.bound_values(
      @context.stage_identity_parameter_values(
        @context.program_identity_stage_at(source_identity, stage).unwrap(),
      ),
    )
    @lower.bind_parameters(
      prepared,
      Some(values),
      max_parameters=100,
      max_name_bytes=10000,
      expression_profiles={
        text_time: selected_profiles.text_time,
        veca: selected_profiles.veca,
      },
    ).unwrap()
  })
  let graph_owner = @strategy.prepare_checked_effect_computation_dag(
    static_candidate,
    owners,
    if split_source || split_before {
      8
    } else {
      2
    },
    10000,
    source_free_root=generated,
  ).unwrap()
  assert_eq(
    @strategy.graph_result_name(
      @strategy.checked_effect_computation_graph(graph_owner),
      0,
    ),
    Some("published"),
  )
  assert_eq(@strategy.checked_effect_source_count(graph_owner), 2)
  let first_source = @strategy.checked_effect_source_at(graph_owner, 0).unwrap()
  assert_eq(@strategy.checked_effect_source_member(first_source), 0)
  assert_eq(
    @strategy.checked_effect_source_stage(first_source),
    if split_before {
      2
    } else {
      1
    },
  )
  if split_source {
    assert_eq(
      @strategy.checked_effect_source_task(first_source),
      if split_intermediate {
        3
      } else {
        4
      },
    )
  } else if split_before {
    assert_eq(@strategy.checked_effect_source_task(first_source), 5)
  } else {
    assert_eq(@strategy.checked_effect_source_task(first_source), 1)
  }
  let occurrence = @strategy.checked_effect_source_occurrence(first_source)
  assert_eq(
    @strategy.graph_stage_target_task(
      @strategy.checked_effect_computation_graph(graph_owner),
      if split_before {
        2
      } else {
        1
      },
      @publication.port_target(
        @execution.managed_result_occurrence_port(occurrence),
      ),
    ),
    Some(@strategy.checked_effect_source_task(first_source)),
  )
  assert_eq(@execution.managed_result_occurrence_name(occurrence), "out")
  assert_true(
    physical_equal(
      @execution.managed_result_occurrence_owner(occurrence),
      owners[if split_before { 2 } else { 1 }],
    ),
  )
  assert_true(
    physical_equal(
      @publication.port_result(
        @execution.managed_result_occurrence_port(occurrence),
      ),
      @results.effect_result_binding_result(
        @results.effect_result_binding_at(
          @results.effect_static_candidate_results(
            @program_check.effect_program_static_effects(static_candidate),
          ),
          0,
        ).unwrap(),
      ).unwrap(),
    ),
  )
  assert_true(@strategy.checked_effect_source_at(graph_owner, 1) is None)
  if split_before {
    assert_eq(
      @strategy.graph_task_count(
        @strategy.checked_effect_computation_graph(graph_owner),
      ),
      6,
    )
    return
  }
  assert_true(
    @strategy.prepare_checked_dag(computation, owners, 2, 10000)
    is Err(EffectGraphOwnerRequired),
  )
  assert_true(
    physical_equal(
      @strategy.checked_effect_computation_owner(graph_owner),
      static_candidate,
    ),
  )
  assert_eq(
    @strategy.graph_task_count(
      @strategy.checked_effect_computation_graph(graph_owner),
    ),
    if split_source {
      5
    } else {
      2
    },
  )
  assert_true(
    @strategy.graph_program_has_effects(
      @strategy.checked_effect_computation_graph(graph_owner),
    ),
  )
  assert_true(
    @strategy.prepare_checked_effect_computation_dag(
      static_candidate,
      owners,
      @strategy.graph_task_count(
        @strategy.checked_effect_computation_graph(graph_owner),
      ) -
      1,
      10000,
    )
    is Err(TaskLimit),
  )
  let preview = public_effect_preview_for_static(static_candidate, mapping_cid)
  let bound = @program_check.bind_effect_program_static_preview(
    static_candidate,
    1,
    preview,
    1000,
    public_effect_plan_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      @program_check.effect_program_static_preview_identity(bound),
      preview,
    ),
  )
  assert_eq(@program_check.effect_program_static_preview_stage(bound), 1)
  assert_eq(
    @run_publication.effect_preview_member_max_items(preview, 0),
    Some(1L),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      static_candidate,
      1,
      public_effect_preview_for_static(
        static_candidate,
        mapping_cid,
        first_max_items=2,
      ),
      1000,
      public_effect_plan_limits(),
    )
    is Err(ForeignResolvedLimit("first")),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      static_candidate,
      1,
      public_effect_preview_for_static(
        static_candidate,
        mapping_cid,
        second_max_items=2,
      ),
      1000,
      public_effect_plan_limits(),
    )
    is Err(ForeignResolvedLimit("second")),
  )
  let supplied = @decode.admit(
    @source.parse_json("{\"n\":2}", {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    {
      max_nodes: 100,
      max_depth: 10,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
  let rebound = @program_check.prepare_effect_computation_candidate(
    program,
    environment,
    Some(supplied),
    evidence,
    limits,
    2,
    2,
  ).unwrap()
  let rebound_static = @program_check.close_effect_computation_static(
    rebound,
    mappings,
    {
      max_members: 2,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  ).unwrap()
  let rebound_preview = public_effect_preview_for_static(
    rebound_static,
    mapping_cid,
    first_max_items=2,
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      rebound_static,
      1,
      rebound_preview,
      1000,
      public_effect_plan_limits(),
    )
    is Ok(_),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      rebound_static,
      1,
      public_effect_preview_for_static(
        rebound_static,
        mapping_cid,
        first_max_items=3,
      ),
      1000,
      public_effect_plan_limits(),
    )
    is Err(ForeignResolvedLimit("first")),
  )
  let (run_admission, run_definition, invocation) = public_effect_run_fixture(
    static_candidate,
  )
  let run_owner = @program_check.bind_effect_program_static_run(
    static_candidate, run_admission, run_definition,
  ).unwrap()
  assert_true(
    physical_equal(
      @program_check.effect_program_run_static_candidate(run_owner),
      static_candidate,
    ),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_run_admission(run_owner),
      run_admission,
    ),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_run_definition(run_owner),
      run_definition,
    ),
  )
  let checked_run = @strategy.bind_checked_effect_run_dag(
    graph_owner, run_owner,
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
  if generated {
    assert_true(
      @strategy.open_source_free_dag(
        @strategy.checked_effect_run_graph(checked_run),
        ledger,
      )
      is Err(UnsupportedGraph),
    )
    let captured = @strategy.open_source_free_effect_run_dag(
      checked_run, ledger,
    ).unwrap()
    assert_true(
      physical_equal(@strategy.captured_effect_run_owner(captured), run_owner),
    )
    assert_true(
      @strategy.pin_captured_effect_sources(captured, 2)
      is Err(@strategy.NotReady),
    )
    assert_true(
      physical_equal(
        @strategy.captured_dag_graph(
          @strategy.captured_effect_run_dag(captured),
        ),
        @strategy.checked_effect_run_graph(checked_run),
      ),
    )
    @strategy.stop_captured_dag(@strategy.captured_effect_run_dag(captured))
  } else {
    assert_true(
      @strategy.open_source_free_effect_run_dag(checked_run, ledger)
      is Err(UnsupportedGraph),
    )
  }
  assert_eq(@strategy.checked_effect_run_source_count(checked_run), 2)
  assert_true(
    physical_equal(
      @strategy.checked_effect_run_source_at(checked_run, 0).unwrap(),
      first_source,
    ),
  )
  assert_true(@strategy.checked_effect_run_source_at(checked_run, 1) is None)
  assert_true(
    physical_equal(@strategy.checked_effect_run_owner(checked_run), run_owner),
  )
  assert_true(
    physical_equal(
      @strategy.checked_effect_run_graph(checked_run),
      @strategy.checked_effect_computation_graph(graph_owner),
    ),
  )
  let (rebound_admission, rebound_definition, _) = public_effect_run_fixture(
    rebound_static,
  )
  let foreign_run = @program_check.bind_effect_program_static_run(
    rebound_static, rebound_admission, rebound_definition,
  ).unwrap()
  assert_true(
    @strategy.bind_checked_effect_run_dag(graph_owner, foreign_run)
    is Err(ForeignCandidate),
  )
  let (foreign_plan_admission, foreign_plan_run, _) = public_effect_run_fixture(
    static_candidate,
    semantics_cid=Some("sha256:" + "f".repeat(64)),
  )
  assert_true(
    @program_check.bind_effect_program_static_run(
      static_candidate, foreign_plan_admission, foreign_plan_run,
    )
    is Err(Binding(@run_publication.RunProgramForeignPlan)),
  )
  let (foreign_env_admission, foreign_env_run, _) = public_effect_run_fixture(
    static_candidate,
    environment_cid=Some("sha256:" + "f".repeat(64)),
  )
  assert_true(
    @program_check.bind_effect_program_static_run(
      static_candidate, foreign_env_admission, foreign_env_run,
    )
    is Err(Binding(@run_publication.RunProgramForeignTemplate)),
  )
  let run_identity = @run_publication.publication_contract_identity(
    run_definition,
  )
  let plan_identity = @run_publication.run_publication_compiled_plan_cid(
    run_admission,
  )
  let invocation_identity = @run_publication.publication_contract_identity(
    invocation,
  )
  let run_preview = public_effect_preview_for_static(
    static_candidate,
    mapping_cid,
    run_cid=Some(run_identity),
    plan_cid=Some(plan_identity),
    invocation_cid=Some(invocation_identity),
  )
  let bound_run_preview = @program_check.bind_effect_program_run_preview(
    run_owner,
    invocation,
    1,
    run_preview,
    1000,
    public_effect_plan_limits(),
  ).unwrap()
  assert_eq(
    @strategy.checked_effect_preview_source_indexes(
      checked_run, bound_run_preview, 4,
    ).unwrap(),
    [Some(0), None],
  )
  let reordered_preview = public_effect_preview_for_static(
    static_candidate,
    mapping_cid,
    run_cid=Some(run_identity),
    plan_cid=Some(plan_identity),
    invocation_cid=Some(invocation_identity),
    reverse_members=true,
  )
  let reordered_owner = @program_check.bind_effect_program_run_preview(
    run_owner,
    invocation,
    1,
    reordered_preview,
    1000,
    public_effect_plan_limits(),
  ).unwrap()
  assert_eq(
    @strategy.checked_effect_preview_source_indexes(
      checked_run, reordered_owner, 4,
    ).unwrap(),
    [None, Some(0)],
  )
  assert_true(
    @strategy.checked_effect_preview_source_indexes(
      checked_run, bound_run_preview, 3,
    )
    is Err(PreviewWorkLimit),
  )
  let duplicate_run = @program_check.bind_effect_program_static_run(
    static_candidate, run_admission, run_definition,
  ).unwrap()
  let duplicate_preview = @program_check.bind_effect_program_run_preview(
    duplicate_run,
    invocation,
    1,
    run_preview,
    1000,
    public_effect_plan_limits(),
  ).unwrap()
  assert_true(
    @strategy.checked_effect_preview_source_indexes(
      checked_run, duplicate_preview, 4,
    )
    is Err(ForeignCandidate),
  )
  assert_true(
    @program_check.check_effect_program_run_preview_footprints(
      bound_run_preview, 2, 2, 100,
    )
    is Ok(_),
  )
  assert_true(
    @program_check.check_effect_program_run_preview_footprints(
      bound_run_preview, 2, 2, 2,
    )
    is Err(@effect.CapacityExceeded),
  )
  let same_target = "sha256:" + "9".repeat(64)
  let overlapping = public_effect_preview_for_static(
    static_candidate,
    mapping_cid,
    run_cid=Some(run_identity),
    plan_cid=Some(plan_identity),
    invocation_cid=Some(invocation_identity),
    first_target_cid=Some(same_target),
    second_target_cid=Some(same_target),
  )
  let overlapping_owner = @program_check.bind_effect_program_run_preview(
    run_owner,
    invocation,
    1,
    overlapping,
    1000,
    public_effect_plan_limits(),
  ).unwrap()
  assert_true(
    @program_check.check_effect_program_run_preview_footprints(
      overlapping_owner, 2, 2, 100,
    )
    is Err(@effect.OverlappingTarget),
  )
  assert_true(
    @program_check.check_effect_program_run_preview_footprints(
      overlapping_owner, 2, 1, 100,
    )
    is Err(@effect.CapacityExceeded),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_run_preview_identity(bound_run_preview),
      run_preview,
    ),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_run_preview_invocation(bound_run_preview),
      invocation,
    ),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_run_preview_owner(bound_run_preview),
      run_owner,
    ),
  )
  for
    (wrong_run, wrong_plan, wrong_invocation, expected) in [
      (true, false, false, @run_publication.PreviewRunForeignRun),
      (false, true, false, @run_publication.PreviewRunForeignPlan),
      (false, false, true, @run_publication.PreviewRunForeignInvocation),
    ] {
    let foreign = public_effect_preview_for_static(
      static_candidate,
      mapping_cid,
      run_cid=Some(
        if wrong_run {
          "sha256:" + "f".repeat(64)
        } else {
          run_identity
        },
      ),
      plan_cid=Some(
        if wrong_plan {
          "sha256:" + "f".repeat(64)
        } else {
          plan_identity
        },
      ),
      invocation_cid=Some(
        if wrong_invocation {
          "sha256:" + "f".repeat(64)
        } else {
          invocation_identity
        },
      ),
    )
    match
      @program_check.bind_effect_program_run_preview(
        run_owner,
        invocation,
        1,
        foreign,
        1000,
        public_effect_plan_limits(),
      ) {
      Err(Run(actual)) => assert_eq(actual, expected)
      _ => fail("Foreign Run Preview escaped")
    }
  }
  let foreign_invocation = @run_publication.seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\"," +
    "\"invocation_template_cid\":\"sha256:" +
    "f".repeat(64) +
    "\",\"observation_set_cid\":\"sha256:" +
    "a".repeat(64) +
    "\"}",
    16384,
    128,
    8,
  ).unwrap()
  assert_true(
    @program_check.bind_effect_program_run_preview(
      run_owner,
      foreign_invocation,
      1,
      run_preview,
      1000,
      public_effect_plan_limits(),
    )
    is Err(Run(@run_publication.PreviewRunForeignTemplate)),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_static_preview_candidate(bound),
      static_candidate,
    ),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      static_candidate,
      1,
      public_effect_preview_for_static(
        static_candidate,
        mapping_cid,
        definition_cid=Some("sha256:" + "f".repeat(64)),
      ),
      1000,
      public_effect_plan_limits(),
    )
    is Err(ForeignProgramDefinition),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      static_candidate,
      1,
      public_effect_preview_for_static(
        static_candidate,
        mapping_cid,
        semantics_cid=Some("sha256:" + "f".repeat(64)),
      ),
      1000,
      public_effect_plan_limits(),
    )
    is Err(ForeignProgramSemantics),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      static_candidate,
      1,
      public_effect_preview_for_static(
        static_candidate,
        mapping_cid,
        environment_cid=Some("sha256:" + "f".repeat(64)),
      ),
      1000,
      public_effect_plan_limits(),
    )
    is Err(ForeignCheckEnvironment),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      static_candidate,
      1,
      public_effect_preview_for_static(
        static_candidate,
        "sha256:" + "f".repeat(64),
      ),
      1000,
      public_effect_plan_limits(),
    )
    is Err(Inventory(@results.ForeignResolvedContract("first"))),
  )
  assert_true(
    @program_check.bind_effect_program_static_preview(
      static_candidate,
      0,
      preview,
      1000,
      public_effect_plan_limits(),
    )
    is Err(Inventory(@results.Inventory(@results.MemberCountMismatch))),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_static_headers(static_candidate),
      @program_check.effect_computation_headers(candidate),
    ),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_static_stage_results(static_candidate),
      @program_check.effect_computation_stage_results(candidate),
    ),
  )
  assert_true(
    physical_equal(
      @program_check.effect_program_static_environment(static_candidate),
      wire,
    ),
  )
  assert_eq(
    @results.effect_result_binding_count(
      @results.effect_static_candidate_results(
        @program_check.effect_program_static_effects(static_candidate),
      ),
    ),
    2,
  )
  let bindings = @results.effect_static_candidate_results(
    @program_check.effect_program_static_effects(static_candidate),
  )
  assert_eq(
    @syntax.effect_header_id(
      @results.effect_result_binding_header(
        @results.effect_result_binding_at(bindings, 0).unwrap(),
      ),
    ),
    "first",
  )
  assert_eq(
    @syntax.effect_header_id(
      @results.effect_result_binding_header(
        @results.effect_result_binding_at(bindings, 1).unwrap(),
      ),
    ),
    "second",
  )
  assert_eq(
    @results.effect_mapping_rule_count(
      @results.effect_static_candidate_mapping_rules(
        @program_check.effect_program_static_effects(static_candidate),
      ),
    ),
    2,
  )
  let foreign_wire = @environment.read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
  ).unwrap()
  let foreign_mappings = @environment.check_mapping_contract_shapes(
    foreign_wire,
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
    1000,
  ).unwrap()
  assert_true(
    @program_check.close_effect_computation_static(
      candidate,
      foreign_mappings,
      {
        max_members: 2,
        max_work: 1000,
        max_admission_nodes: 100,
        max_admission_depth: 10,
        max_admission_text_bytes: 1000,
      },
    )
    is Err(ForeignEnvironment),
  )
}

///|
test "Effect computation candidate closes the exact Mapping environment" {
  public_effect_mapping_closure(false)
}

///|
test "Values-root Effect Run keeps its checked owner through capture" {
  public_effect_mapping_closure(true)
}

///|
test "Effect source binds the final physical task of a split Stage" {
  public_effect_mapping_closure(false, split_source=true)
}

///|
test "Effect source binds an intermediate physical task of a split Stage" {
  public_effect_mapping_closure(
    false,
    split_source=true,
    split_intermediate=true,
  )
}

///|
test "Effect source follows a preceding split Stage" {
  public_effect_mapping_closure(false, split_before=true)
}

///|
fn public_input_fixture(
  generated? : Bool = false,
  repeated? : Bool = false,
  analytic_policy? : Bool = false,
  graph_policy? : Bool = false,
  text_policy? : (String, String)? = None,
  text_profile? : Bool = true,
  lexical_selection? : (String, String)? = None,
  lexical_profile? : Bool = false,
  calendar_selection? : (String, String)? = None,
  calendar_profile? : Bool = false,
  numeric_profile? : @numeric.Profile? = None,
  temporal_join_step? : Int? = None,
) -> (
  String,
  @syntax.Program,
  @program_check.CheckEnvironment,
  Array[@context.StageCapacityInput],
  @program_check.CheckLimits,
) {
  let text = (
      #|{"version":"actql/0.1","id":"public-reader","params":{"n":{"type":"number","default":1}},"stages":[{"id":"producer","inputs":{"rows":{"carrier":"relation","schema":{"id":{"type":"number","nullable":false}},"primary_key":["id"]}},"steps":[{"derive":{"value":"id + $n"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["id","value"]}}},{"id":"consumer","inputs":{"rows":{"result":{"stage":"producer","result":"out"}}},"steps":[{"take":1,"as":"selected"}],"results":{"out":{"from":"selected","fields":["id","value"]}}}],"results":{"out":{"from":{"stage":"consumer","result":"out"}}}}
    )
    .replace(
      old="\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":[",
      new=if generated {
        "\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"id\"]}},"
      } else {
        "\"inputs\":{\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}},\"steps\":["
      },
    )
    .replace(
      old="{\"take\":1,\"as\":\"selected\"}",
      new=if repeated {
        "{\"append\":{\"with\":\"rows\"}},{\"distinct\":[\"id\",\"value\"],\"as\":\"selected\"}"
      } else {
        "{\"take\":1,\"as\":\"selected\"}"
      },
    )
  let input_limits : @syntax.Limits = {
    source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
    tree: {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
    max_stages: 2,
  }
  let program = @syntax.parse(
    text,
    input_limits,
    format=Json,
    source_path="fixture.actql",
  ).unwrap()
  // Input envelope CID independently calculated from canonical JSON with Node SHA-256.
  // It is not an expected Program identity computed by the product under test.
  let environment_cid = if calendar_selection is Some((_, cid)) {
    cid
  } else if lexical_selection is Some((_, cid)) {
    cid
  } else if text_policy is Some((_, cid)) {
    cid
  } else if graph_policy {
    "sha256:0e1e713a191318e1e3a418ca4c104e93dc6d32c9425096eda1a3ad004a7c6792"
  } else if analytic_policy {
    "sha256:04185e37572a0a791a18909c4bc09da47f393976a9b6bb940ed9658a0497de07"
  } else {
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904"
  }
  let environment = @environment.read(
    @utf8.encode(
      (
        #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
      )
      .replace(
        old="\"host_policy_profile\":{\"capacity\":",
        new=if calendar_selection is Some((body, _)) {
          "\"host_policy_profile\":{\"calendar\":" + body + ",\"capacity\":"
        } else {
          "\"host_policy_profile\":{\"capacity\":"
        },
      )
      .replace(
        old="\"version\":\"actql-capacity-host-policy/0.1\"}",
        new=if lexical_selection is Some((body, _)) {
          "\"version\":\"actql-capacity-host-policy/0.1\"},\"text_rank\":" +
          body
        } else if text_policy is Some((body, _)) {
          "\"version\":\"actql-capacity-host-policy/0.1\"},\"text_time_evaluation\":" +
          body
        } else {
          "\"version\":\"actql-capacity-host-policy/0.1\"}"
        },
      )
      .replace(
        old="sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
        new=environment_cid,
      )
      .replace(
        old="\"max_artifact_bytes\":1000",
        new=if analytic_policy {
          "\"max_analytic_frame_memberships\":1000,\"max_analytic_input_wire_bytes\":1000,\"max_analytic_output_wire_bytes\":1000,\"max_analytic_partition_wire_bytes\":1000,\"max_artifact_bytes\":1000"
        } else {
          "\"max_artifact_bytes\":1000"
        },
      )
      .replace(
        old="\"max_graph_input_edges\":1000",
        new=if graph_policy {
          "\"max_graph_construction_edges\":1000,\"max_graph_construction_input_rows\":1000,\"max_graph_construction_nodes\":1000,\"max_graph_input_edges\":1000"
        } else {
          "\"max_graph_input_edges\":1000"
        },
      ),
    ),
    environment_cid,
    { max_bytes: 10000, max_nodes: 1000, max_depth: 100, max_members: 10, },
  ).unwrap()
  let proofs = if generated { [public_seed_claim()] } else { [] }
  let mixed = @wire.check_mixed_claims(
    proofs.map(p => @wire.program_proof_witness(p)),
    [],
    {
      max_entities: 100,
      max_references: 100,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, proofs, {
    max_witnesses: 100,
    max_references: 100,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  // Explicit proofs target Stage definitions. The compiler, not this public
  // consumer, assigns them to the actual imported producer occurrences.
  let consumer_sources = if repeated {
    let all = [public_seed_claim(), public_append_claim()]
    let mixed = @wire.check_mixed_claims(
      all.map(p => @wire.program_proof_witness(p)),
      [],
      {
        max_entities: 100,
        max_references: 100,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    ).unwrap()
    let claims = @wire.check_mixed_program_claims(mixed, all, {
      max_witnesses: 100,
      max_references: 100,
    }).unwrap()
    let sources = @host.bind_claim_sources(claims, [], {
      max_entries: 100,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    }).unwrap()
    sources
  } else {
    sources
  }
  (
    text,
    program,
    @program_check.checking_environment(
      environment,
      { text_time: text_profile && text_policy is Some(_), veca: false, },
      {
        rela: true,
        sga: graph_policy,
        tea: temporal_join_step is Some(_) || calendar_profile,
        calendar: calendar_profile,
        text_rank: lexical_profile,
      },
      numeric_profile~,
    ),
    if temporal_join_step is Some(step) {
      [
        public_search_capacity(environment, step) catch {
          _ => abort("invalid temporal search fixture capacity")
        },
      ]
    } else if generated || repeated {
      [
        { stage: "producer", sources, uses: [], },
        { stage: "consumer", sources: consumer_sources, uses: [], },
      ]
    } else {
      []
    },
    { input: input_limits, compilation: public_source_limits(2), },
  )
}

///|
test "external consumer reads formal Program decisions without private construction" {
  let program = public_program_fixture()
  assert_eq(@program_check.unit_count(program), 2)
  let identity = @program_check.source_identity(program)
  assert_eq(@context.program_identity_stage_count(identity), 2)
  let stage_values = @context.stage_identity_parameter_values(
    @context.program_identity_stage_at(identity, 0).unwrap(),
  )
  assert_eq(@parameter_refs.used_value_count(stage_values), 1)
  let parameter = @parameter_refs.used_value_at(stage_values, 0).unwrap()
  assert_eq(parameter.name, "n")
  assert_true(parameter.value.value is Number(1.0))
  assert_true(@parameter_refs.used_value_at(stage_values, 1) is None)
  let producer_cid = @program_check.unit_definition_cid(program, 0).unwrap()
  assert_true(
    producer_cid != @program_check.unit_definition_cid(program, 1).unwrap(),
  )
  let imported = @program_check.unit_result_import_at(program, 1, 0).unwrap()
  assert_eq(imported.input_name, "rows")
  assert_eq(imported.producer_program_id, "public-reader")
  assert_eq(imported.producer_node_id, "producer")
  assert_eq(imported.result_name, "out")
  assert_eq(imported.producer_unit_definition_cid, producer_cid)
  assert_eq(
    @program_check.unit_import_cid_at(program, 1, 0),
    Some(imported.cid),
  )
  assert_true(@program_check.unit_result_import_at(program, 1, 1) is None)
  let requirements = @program_check.requirements(program)
  let inputs = @context.stage_requirement_inputs(requirements)
  assert_eq(@context.local_input_closure_count(inputs), 3)
  for index in 0..<3 {
    let check = @context.local_input_closure_at(inputs, index).unwrap()
    assert_eq(check.subject.stage, 0)
    assert_eq(check.subject.name, "rows")
    assert_eq(@context.local_input_execution_phase(check), BeforeLocalInputUse)
    assert_eq(@context.local_input_execution_failure(check), RejectLocalInput)
  }
  for stage in 0..<2 {
    let pipeline = @program_check.unit_pipeline(program, stage).unwrap()
    assert_eq(@pipeline.step_count(pipeline), 1)
    let count = @program_check.unit_contract_count(program, stage).unwrap()
    assert_true(count > 0)
    for index in 0..<count {
      let (cid, body) = @program_check.unit_contract_at(program, stage, index).unwrap()
      assert_eq(cid, @context.core_contract_cid(body))
    }
    assert_true(@program_check.unit_contract_at(program, stage, count) is None)
    assert_eq(@program_check.unit_publication_count(program, stage), Some(1))
    let publication = @program_check.unit_publication_at(program, stage, 0).unwrap()
    let selected = @program_check.publication_selection(publication)
    assert_eq(
      @context.publication_row_limit_maximum(selected),
      if stage == 0 {
        1000L
      } else {
        1L
      },
    )
    let result = @context.publication_row_limit_result(selected)
    assert_eq(result.stage, stage)
    assert_true(
      physical_equal(
        @pipeline.publication_pipeline(
          @publication.port_publication(result.port),
        ),
        pipeline,
      ),
    )
    let order = @publication.port_order(result.port)
    assert_eq(
      @publication.publication_strategy(order),
      if stage == 0 {
        CandidateKey
      } else {
        Inherited
      },
    )
    if stage == 1 {
      let retained = @publication.publication_inherited_order(order).unwrap()
      let producer = @pipeline.order_input_producer(retained).unwrap()
      assert_true(
        physical_equal(
          @pipeline.producer_pipeline(producer),
          @program_check.unit_pipeline(program, 0).unwrap(),
        ),
      )
    }
  }
  assert_true(@program_check.unit_pipeline(program, 2) is None)
  assert_true(@program_check.unit_publication_at(program, 2, 0) is None)
}

///|
test "external consumer receives the exact checked Result owner" {
  let program = public_program_fixture()
  let results = @program_check.checked_stage_results(program)
  let source = @stages.operations_source(@results.operations(results))
  assert_eq(@stages.stage_count(source), 2)
  for index in 0..<2 {
    let stage = @results.stage_at(results, index).unwrap()
    assert_true(@publication.lookup(stage, "out") is Some(_))
  }
  assert_true(@results.stage_at(results, 2) is None)
  let identity = @program_check.source_identity(program)
  let sources = @context.program_identity_sources(identity)
  let operations = @context.program_sources_operations(sources)
  let preparation = @context.operation_profiles_preparation(operations)
  let producers = @context.preparation_sources(preparation)
  let capacity = @context.source_producer_capacity(producers)
  let policy = @context.source_capacity_context(capacity)
  let selected = @context.source_policy_selected(policy)
  let reconciled = @context.policy_context(selected)
  let wired = @context.reconciled_wiring(reconciled)
  assert_true(
    physical_equal(
      results,
      @context.stage_results(@context.wired_stage_contexts(wired)),
    ),
  )
  let other = public_program_fixture()
  assert_false(
    physical_equal(results, @program_check.checked_stage_results(other)),
  )
}

///|
fn public_source_limits(stage_count : Int) -> @program_check.CompileLimits {
  {
    work: 10000000,
    artifacts: { bytes: 1000000, nodes: 100000, depth: 100, },
    structure: {
      stages: stage_count,
      steps: 5,
      results: stage_count,
      parameters: 1,
      bindings: 100,
      slots: 1000,
      references: 1000,
      requirements: 1000,
      tokens: 10000,
    },
    traversal: {
      nodes: 100000,
      depth: 100,
      text_bytes: 10000000,
      string_bytes: 100000,
      name_bytes: 1000000,
      pointer_units: 1000000,
      comparison_pairs: 1000000,
    },
    values: { nodes: 1000000, depth: 100, text_bytes: 100000, },
    policy: { bytes: 10000, nodes: 1000000, depth: 100, },
    patterns: { bytes: 1000000, nodes: 1000000, depth: 100, },
  }
}
