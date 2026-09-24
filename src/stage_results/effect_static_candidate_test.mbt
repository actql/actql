///|
fn effect_static_candidate_limits(
  members? : Int = 4,
  work? : Int = 1000,
) -> EffectStaticCandidateLimits {
  {
    max_members: members,
    max_work: work,
    max_admission_nodes: 20,
    max_admission_depth: 10,
    max_admission_text_bytes: 100,
  }
}

///|
fn effect_static_candidate_environment_limits() -> @environment.Limits {
  { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, }
}

///|
fn effect_static_candidate_catalogs(
  mappings : @environment.MappingContractShapes,
) -> @environment.CatalogContents {
  let registry = @environment.check_contract_registry(
    @environment.mapping_shape_environment(mappings),
    effect_static_candidate_environment_limits(),
  ).unwrap()
  @environment.check_catalog_contents(
    registry,
    effect_static_candidate_environment_limits(),
  ).unwrap()
}

///|
test "static Effect candidate closes one Mapping inventory and shared work" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{\"Name\":7}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let mappings = effect_mapping_shape_fixture()
  let catalogs = effect_static_candidate_catalogs(mappings)
  let candidate = prepare_effect_static_candidate(
    headers,
    checked,
    @environment.mapping_shape_environment(mappings),
    mappings,
    catalogs,
    effect_static_candidate_limits(),
  ).unwrap()
  assert_eq(
    effect_result_binding_count(effect_static_candidate_results(candidate)),
    2,
  )
  assert_eq(
    effect_mapping_rule_count(effect_static_candidate_mapping_rules(candidate)),
    2,
  )
  assert_eq(
    effect_mapping_literal_count(
      effect_static_candidate_mapping_literals(candidate),
    ),
    2,
  )
  assert_eq(
    effect_command_target_count(
      effect_static_candidate_command_targets(candidate),
    ),
    0,
  )
  assert_eq(
    effect_command_input_count(
      effect_static_candidate_command_inputs(candidate),
    ),
    0,
  )
  let used = effect_static_candidate_work(candidate)
  assert_true(used > 0)
  assert_true(
    prepare_effect_static_candidate(
      headers,
      checked,
      @environment.mapping_shape_environment(mappings),
      mappings,
      catalogs,
      effect_static_candidate_limits(work=used),
    )
    is Ok(_),
  )
  assert_true(
    prepare_effect_static_candidate(
      headers,
      checked,
      @environment.mapping_shape_environment(mappings),
      mappings,
      catalogs,
      effect_static_candidate_limits(work=used - 1),
    )
    is Err(_),
  )
  assert_true(
    prepare_effect_static_candidate(
      headers,
      checked,
      @environment.mapping_shape_environment(mappings),
      mappings,
      catalogs,
      effect_static_candidate_limits(members=1),
    )
    is Err(MemberLimit),
  )
}

///|
test "static Effect candidate rejects foreign Environment and Program" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"r\"}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let mappings = effect_mapping_shape_fixture()
  let catalogs = effect_static_candidate_catalogs(mappings)
  let foreign_environment = @environment.contract_registry_environment(
    @environment.catalog_registry(command_target_catalog("crm/account")),
  )
  assert_true(
    prepare_effect_static_candidate(
      headers,
      checked,
      foreign_environment,
      mappings,
      catalogs,
      effect_static_candidate_limits(),
    )
    is Err(ForeignEnvironment),
  )
  assert_true(
    prepare_effect_static_candidate(
      headers,
      checked,
      @environment.mapping_shape_environment(mappings),
      mappings,
      command_target_catalog("crm/account"),
      effect_static_candidate_limits(),
    )
    is Err(ForeignEnvironment),
  )
  let (foreign_checked, _) = effect_binding_inputs(effects)
  let issue = prepare_effect_static_candidate(
    headers,
    foreign_checked,
    @environment.mapping_shape_environment(mappings),
    mappings,
    catalogs,
    effect_static_candidate_limits(),
  ).unwrap_err()
  match issue {
    Results(inner) =>
      assert_eq(effect_result_binding_issue_kind(inner), ForeignProgram)
    _ => assert_true(false)
  }
}

///|
test "static Effect candidate covers Command without Mapping members" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let catalogs = command_target_catalog("crm/account")
  let mappings = @environment.check_mapping_contract_shapes(
    @environment.contract_registry_environment(
      @environment.catalog_registry(catalogs),
    ),
    effect_static_candidate_environment_limits(),
    100,
  ).unwrap()
  let candidate = prepare_effect_static_candidate(
    headers,
    checked,
    @environment.mapping_shape_environment(mappings),
    mappings,
    catalogs,
    effect_static_candidate_limits(),
  ).unwrap()
  assert_eq(
    effect_mapping_rule_count(effect_static_candidate_mapping_rules(candidate)),
    0,
  )
  assert_eq(
    effect_command_target_count(
      effect_static_candidate_command_targets(candidate),
    ),
    2,
  )
  assert_eq(
    effect_command_input_count(
      effect_static_candidate_command_inputs(candidate),
    ),
    2,
  )
}

///|
test "static Effect candidate includes Command input admission" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{\"value\":{\"field\":\"amount\"}}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let catalogs = command_target_catalog(
    "crm/account",
    input_fields="{\"value\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  let mappings = @environment.check_mapping_contract_shapes(
    @environment.contract_registry_environment(
      @environment.catalog_registry(catalogs),
    ),
    effect_static_candidate_environment_limits(),
    100,
  ).unwrap()
  let candidate = prepare_effect_static_candidate(
    headers,
    checked,
    @environment.mapping_shape_environment(mappings),
    mappings,
    catalogs,
    effect_static_candidate_limits(),
  ).unwrap()
  assert_eq(
    effect_command_input_count(
      effect_static_candidate_command_inputs(candidate),
    ),
    2,
  )
  let invalid = effects.replace(old="\"amount\"", new="\"ref\"")
  let (checked, headers) = effect_binding_inputs(
    invalid,
    reference_nullable=Some(false),
  )
  let issue = prepare_effect_static_candidate(
    headers,
    checked,
    @environment.mapping_shape_environment(mappings),
    mappings,
    catalogs,
    effect_static_candidate_limits(),
  ).unwrap_err()
  match issue {
    CommandInputs(inner) =>
      assert_eq(
        effect_command_input_issue_kind(inner),
        IncompatibleField("value"),
      )
    _ => assert_true(false)
  }
}
