///|
// Semantic refusal over the existing explicit Scope fixture. This does not
// establish Source/Model execution, capacity, Store custody or ordinary CLI.
test "Model acquired closure refuses foreign originals and missing acquisition provenance" {
  let (compiled, scope, model) = model_local_invocation_fixture()
  let occurrence = scope.plan.occurrence
  let sources : ClientInferComposedSources = {
    occurrence,
    inputs: [],
    keyed: None,
  }
  let (foreign, foreign_scope, _) = model_local_invocation_fixture()
  assert_true(
    issue_single_model_client_effect_acquired_evidence(
      foreign,
      scope,
      model,
      sources,
      compiled.plan,
      10000,
      1000,
      20,
    )
    is Err(Invocation(ForeignCapturedInput)),
  )
  assert_true(
    issue_single_model_client_effect_acquired_evidence(
      compiled,
      scope,
      model,
      { ..sources, occurrence: foreign_scope.plan.occurrence, },
      compiled.plan,
      10000,
      1000,
      20,
    )
    is Err(Invocation(ForeignCapturedInput)),
  )
  // A Model Invocation alone cannot invent an acquisition scope. This fixture
  // has no original captures; the whole acquired entrance must stay closed.
  assert_true(
    issue_single_model_client_effect_acquired_evidence(
      compiled,
      scope,
      model,
      sources,
      compiled.plan,
      10000,
      1000,
      20,
    )
    is Err(Relation(WrongScope)),
  )
}
