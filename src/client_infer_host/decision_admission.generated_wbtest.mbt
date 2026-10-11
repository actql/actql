// Generated independent Decision compatibility boundary.

///|
test "Decision synchronous profile refuses before physical start and retains input cleanup" {
  let environment_wire = infer_fixture_environment
    .replace(old="\"generation_config\":{\"max_output_tokens\":32,\"seed_requested\":-7,\"temperature\":0,\"top_p\":1}", new="\"decision_config\":{\"answer_profile\":\"actql.decision_answers/0.1\",\"distribution_policy\":\"required_for_choice_and_score\",\"probability_source\":\"native\"}")
    .replace(old="actql.model_task/0.1", new="actql.model_task/0.2")
    .replace(old="\"task_kind\":\"structured_generate\"", new="\"task_kind\":\"decision\"")
    .replace(old="sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560", new="sha256:1fda0e8923a39f4463df95ef6591fba7932aba23f450a43d64daa18394701ba0")
  assert_true(environment_wire != infer_fixture_environment)
  let prepared = fixture_prepared(environment_wire~)
  let calls = Ref(0)
  let active = fixture_start(prepared, () => calls.val += 1)
  assert_true(fixture_finish(active) is Failed(Model(@model.InvalidProvider), ..))
  assert_eq(calls.val, 0)
  assert_true(active.model is None)
  assert_true(active.rows is Some(_))
  assert_true(acquire_output(active) is None)
  assert_true(cleanup(active).unwrap())
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 0)
}
