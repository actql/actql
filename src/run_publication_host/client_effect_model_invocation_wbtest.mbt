///|
// This exercises only semantic projection over explicit whitebox Scope DATA.
// The real compiler/checked owner and an actual completed Values output are
// used; bypassing the private Scope factory here is not Model/Source execution
// or evidence of its physical construction/backing. The normal caller instead
// enters through client_infer_host's original OutputUse/complete-issuer wrapper.
fn model_local_invocation_fixture() -> (
  ClientCompiledRun,
  ClientInferCallScope,
  @publication.CapturedEffectDependencyBody,
) raise {
  let (_, allowed, _, _) = selected_infer_original_fixture()
  let compiled = client_effect_allowed_component_run(allowed, None)
  let (plan, occurrence) = client_effect_compilation_infer_original(
    allowed.compilation,
  ).unwrap()
  model_local_invocation_for(compiled, plan, occurrence)
}

///|
fn model_local_invocation_for(
  compiled : ClientCompiledRun,
  plan : ClientInferPlanGraph,
  occurrence : ClientInferOccurrence,
) -> (
  ClientCompiledRun,
  ClientInferCallScope,
  @publication.CapturedEffectDependencyBody,
) raise {
  guard compiled.compilation is Effects(allowed) else {
    fail("Effect compiler")
  }
  let input = local_distinct_execute(
    local_explicit_cast_original(text="SELECT ABS(-1) AS id"),
  )
  let cid = "sha256:" + "a".repeat(64)
  let unit = @checked.unit_definition_cid(
    @checked.effect_program_static_checked_computation(
      allowed.compilation.owner.candidate,
    ),
    occurrence.stage,
  ).unwrap()
  let artifact = @publication.seal_run_evidence_value(
    "model_input_artifact",
    "{\"version\":\"actql-model-input-artifact/0.1\",\"program_definition_cid\":\"" +
    cid +
    "\",\"unit_definition_cid\":\"" +
    unit +
    "\",\"source_ordinal\":" +
    occurrence.step.to_string() +
    ",\"effective_inputs_cid\":\"" +
    cid +
    "\",\"input_fragment_cid\":\"" +
    cid +
    "\",\"logical_relation_cid\":\"" +
    cid +
    "\",\"relation_schema_cid\":\"" +
    cid +
    "\",\"ordered_rows_cid\":\"" +
    cid +
    "\",\"completeness\":\"complete\"}",
    10000,
    1000,
    20,
  ).unwrap()
  let preimage = "{\"input_logical_relation_cid\":\"" +
    cid +
    "\",\"input_relation_schema_cid\":\"" +
    cid +
    "\",\"outcome_logical_relation_cid\":\"" +
    cid +
    "\",\"outcome_relation_schema_cid\":\"" +
    cid +
    "\",\"source_ordinal\":" +
    occurrence.step.to_string() +
    ",\"unit_definition_cid\":\"" +
    unit +
    "\",\"version\":\"actql-local-model-observation/0.1\"}"
  let hash = "sha256:" + @sha.hex(@utf8.encode(preimage))
  let wire = preimage.replace(
    old=",\"source_ordinal\":",
    new=",\"self_cid\":\"" + hash + "\",\"source_ordinal\":",
  )
  let body = @publication.admit_local_effect_dependency_body(
    "local_model_observation", wire, 10000, 1000, 20,
  ).unwrap()
  let scope : ClientInferCallScope = {
    owner: compiled.owner,
    plan,
    input,
    artifact,
    effective: artifact,
    source: None,
    sources: [],
    result_inputs: [],
    original_result_inputs: [],
    saved_result_scope: None,
    named_sources: [],
    generation: None,
    unit_definition_cid: unit,
    source_ordinal: occurrence.step,
  }
  (compiled, scope, body)
}

///|
test "single Model local Invocation retains exact checked owner and Model input" {
  let (compiled, scope, body) = model_local_invocation_fixture()
  let invocation = issue_single_model_client_effect_local_invocation(
    compiled, scope, body, 10000, 1000, 20,
  ).unwrap()
  guard compiled.compilation is Effects(allowed) else {
    fail("Effect compiler")
  }
  assert_true(
    client_effect_local_invocation_matches(
      invocation,
      allowed.compilation.owner,
      0,
    ),
  )
  assert_true(
    client_effect_local_invocation_json(invocation).contains(
      @publication.captured_effect_dependency_body_cid(body),
    ),
  )
  assert_true(
    @publication.local_model_observation_matches_input(
      body,
      scope.unit_definition_cid,
      scope.source_ordinal,
      scope.artifact,
    ),
  )
  assert_false(
    @publication.local_model_observation_matches_input(
      body,
      "sha256:" + "b".repeat(64),
      scope.source_ordinal,
      scope.artifact,
    ),
  )
  assert_false(
    @publication.local_model_observation_matches_input(
      body,
      scope.unit_definition_cid,
      scope.source_ordinal + 1,
      scope.artifact,
    ),
  )
  let (foreign, _, _) = model_local_invocation_fixture()
  assert_true(
    issue_single_model_client_effect_local_invocation(
      foreign, scope, body, 10000, 1000, 20,
    )
    is Err(ForeignCapturedInput),
  )
}

///|
test "single Model local Invocation refuses a substituted input or codec refusal" {
  let (compiled, scope, body) = model_local_invocation_fixture()
  assert_true(
    issue_single_model_client_effect_local_invocation(
      compiled,
      { ..scope, artifact: compiled.template, },
      body,
      10000,
      1000,
      20,
    )
    is Err(ForeignSourceObservation),
  )
  assert_true(
    issue_single_model_client_effect_local_invocation(
      compiled, scope, body, 1, 1000, 20,
    )
    is Err(Encoding),
  )
}

///|
// The real two-component compiler chooses each original scope. The explicit
// whitebox observation/input setup above remains semantic component evidence,
// not two physical Model executions or their Store/Host completion.
test "each original Model scope issues its own Invocation in a plural Effect compilation" {
  let (owner, allowed, _, _) = plural_effect_infer_fixture(inline_models=true)
  let compiled = client_effect_allowed_component_run(allowed, None)
  let originals = client_effect_compilation_infer_originals(allowed.compilation).unwrap()
  assert_eq(originals.length(), 2)
  for (plan, occurrence) in originals {
    let program = @checked.effect_program_static_checked_computation(
      owner.candidate,
    )
    assert_eq(
      @checked.unit_result_import_count(program, occurrence.stage),
      Some(0),
    )
    let (_, scope, body) = model_local_invocation_for(
      compiled, plan, occurrence,
    )
    let issued = issue_single_model_client_effect_local_invocation(
      compiled, scope, body, 10000, 1000, 20,
    )
    assert_eq(issued.map(_ => true), Ok(true))
    let invocation = issued.unwrap()
    assert_true(
      client_effect_local_invocation_matches(
        invocation,
        owner,
        occurrence.stage,
      ),
    )
    let (foreign, _, _) = model_local_invocation_fixture()
    assert_true(
      issue_single_model_client_effect_local_invocation(
        foreign, scope, body, 10000, 1000, 20,
      )
      is Err(ForeignCapturedInput),
    )
  }
}

///|
test "plural Model scope selection never substitutes for required original imports" {
  let (_, allowed, _, _) = plural_effect_infer_fixture()
  let compiled = client_effect_allowed_component_run(allowed, None)
  let originals = client_effect_compilation_infer_originals(allowed.compilation).unwrap()
  assert_eq(originals.length(), 2)
  for (plan, occurrence) in originals {
    let (_, scope, body) = model_local_invocation_for(
      compiled, plan, occurrence,
    )
    assert_true(
      issue_single_model_client_effect_local_invocation(
        compiled, scope, body, 10000, 1000, 20,
      )
      is Err(IncompleteResultImports),
    )
  }
}
