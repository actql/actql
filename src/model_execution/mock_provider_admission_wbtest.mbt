///|
fn mock_provider_admission_fixture() -> (
  ModelMockInstallation,
  @environment.ModelExecutionContract,
  @environment.SingleAttemptModelDependencies,
) {
  let original = mock_installation_test_original()
  let normalized = original.normalized.unwrap()
  let limits : @environment.ModelTaskLimits = {
    bodies: mock_answer_limits().document,
    contracts: { max_nodes: 100, max_depth: 16, max_text_bytes: 1000, },
    max_work: 1000000,
  }
  let (task_wire, _, prompt, _) = @environment.normalized_public_model_task_materials(
    normalized,
  )
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    task_wire +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = @environment.read(
    @utf8.encode(prefix + "\"evidence_bundle_cid\":\"" + cid + "\"," + suffix),
    cid,
    limits.bodies,
  ).unwrap()
  let task = @environment.resolve_model_task(
    @environment.check_model_tasks(environment, limits).unwrap(),
    "model-task:original.v1",
  ).unwrap()
  let materials = @environment.model_mock_execution_materials(
    original.profile.unwrap(),
    normalized,
    limits,
  ).unwrap()
  let execution = @environment.read_model_execution_contract(
    task,
    @utf8.encode(materials.0),
    materials.1,
    limits.bodies,
    limits.max_work,
  ).unwrap()
  let dependencies = @environment.read_single_attempt_model_dependencies(
    execution,
    Some(@utf8.encode(prompt)),
    Some(@utf8.encode(materials.2)),
    Some(@utf8.encode(materials.4)),
    limits.bodies,
    limits.max_work,
  ).unwrap()
  (original, execution, dependencies)
}

///|
test "original Mock admits its owned normalized prompt without a Host callback" {
  let (original, execution, dependencies) = mock_provider_admission_fixture()
  let admitted = admit_original_model_mock_provider(
    original, execution, dependencies,
  ).unwrap()
  assert_true(
    admitted_model_provider_for(admitted, execution) is Some(provider) &&
    physical_equal(provider, original.provider.unwrap()),
  )
  // General physical-provider admission retains its caller-supplied prompt
  // implementation check. The new fixture entrance does not waive that check.
  assert_true(
    admit_model_provider(original.provider.unwrap(), execution, dependencies, (
      _,
      _,
    ) => false)
    is Err(UnsupportedPrompt),
  )
  assert_eq(original.users, 0)
  assert_true(original.task is None)
  retire_original_model_mock(original).unwrap() |> ignore
}

///|
test "original Mock admission refuses copied retired and foreign execution dependencies" {
  let (original, execution, dependencies) = mock_provider_admission_fixture()
  assert_true(
    admit_original_model_mock_provider({ ..original, }, execution, dependencies)
    is Err(ForeignProvider),
  )
  let (other, other_execution, other_dependencies) = mock_provider_admission_fixture()
  assert_true(
    admit_original_model_mock_provider(original, execution, other_dependencies)
    is Err(ForeignDependencies),
  )
  assert_true(
    admitted_model_provider_for(
      admit_original_model_mock_provider(original, execution, dependencies).unwrap(),
      other_execution,
    )
    is None,
  )
  retire_original_model_mock(original).unwrap() |> ignore
  assert_true(
    admit_original_model_mock_provider(original, execution, dependencies)
    is Err(ForeignProvider),
  )
  retire_original_model_mock(other).unwrap() |> ignore
}

///|
test "original Mock admission retains the original profile current fence" {
  let (original, execution, dependencies) = mock_provider_admission_fixture()
  assert_true(@environment.retire_model_mock_profile(original.profile.unwrap()))
  assert_true(
    admit_original_model_mock_provider(original, execution, dependencies)
    is Err(ForeignProvider),
  )
  retire_original_model_mock(original).unwrap() |> ignore
}
