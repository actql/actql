///|
test "structured Provider admission requires support on the resolved model and mode" {
  let (execution, dependencies) = provider_admission_fixture()
  let (foreign_execution, foreign_dependencies) = provider_admission_fixture()
  let provider = install_async_model_provider("models/fixture").unwrap()
  let selected : ResolvedStructuredModel = {
    selector: "fixture-risk-model",
    model_id: "physical-model-a",
    adapter_kind: "fixture-sdk",
    api_mode: "structured-http",
    endpoint: "https://models.example/v1/structured",
  }
  let configuration =
    #|{"adapter_kind":"fixture-sdk","api_mode":"structured-http","endpoint":"https://models.example/v1/structured","model_id":"physical-model-a","provider_id":"models/fixture","selector":"fixture-risk-model"}
  let foreign_configuration =
    #|{"adapter_kind":"fixture-sdk","api_mode":"structured-http","endpoint":"https://models.example/v1/structured","model_id":"physical-model-b","provider_id":"models/fixture","selector":"fixture-risk-model"}
  let issue = wire => {
    @publication_host.issue_client_model_provider_binding(
      "models/fixture", "{}", "{}", wire,
    ).unwrap()
  }
  let binding = issue(configuration)
  let foreign_binding = issue(foreign_configuration)
  // Same connector, selector and declared route. The installed original
  // actually resolves a different model. A substituted wire fails too.
  assert_true(
    register_structured_model_capability(
      provider, foreign_binding, foreign_configuration, selected, true, true,
    )
    is Err(ForeignConfiguration),
  )
  assert_true(
    register_structured_model_capability(
      provider, foreign_binding, configuration, selected, true, true,
    )
    is Err(ForeignConfiguration),
  )
  let supported = register_structured_model_capability(
    provider, binding, configuration, selected, true, true,
  ).unwrap()
  let unsupported = register_structured_model_capability(
    provider, binding, configuration, selected, true, false,
  ).unwrap()
  let unsupported_adapter = register_structured_model_capability(
    provider, binding, configuration, selected, false, true,
  ).unwrap()
  let mut validations = 0
  let validate = (_, _) => {
    validations += 1
    true
  }
  assert_true(
    admit_structured_model_provider(
      unsupported, selected, execution, dependencies, validate,
    )
    is Err(UnsupportedModel),
  )
  assert_true(
    admit_structured_model_provider(
      unsupported_adapter, selected, execution, dependencies, validate,
    )
    is Err(UnsupportedAdapter),
  )
  let changed_model = { ..selected, model_id: "physical-model-b", }
  let changed_mode = { ..selected, api_mode: "streaming-http", }
  for changed in [changed_model, changed_mode] {
    assert_true(
      admit_structured_model_provider(
        supported, changed, execution, dependencies, validate,
      )
      is Err(ChangedSelection),
    )
  }
  assert_true(
    admit_structured_model_provider(
      supported, selected, execution, foreign_dependencies, validate,
    )
    is Err(ProviderAdmission(ForeignDependencies)),
  )
  assert_eq(validations, 0)
  let admitted = admit_structured_model_provider(
    supported, selected, execution, dependencies, validate,
  ).unwrap()
  assert_eq(validations, 1)
  let replacement = register_structured_model_capability(
    provider, binding, configuration, selected, true, true,
  ).unwrap()
  assert_true(
    admitted_structured_model_provider_for(
      admitted, replacement, binding, selected, execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted, supported, binding, changed_model, execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted, supported, binding, selected, foreign_execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted,
      supported,
      issue(configuration),
      selected,
      execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted, supported, binding, selected, execution,
    )
    is Some(actual) &&
    physical_equal(actual, provider),
  )
}
