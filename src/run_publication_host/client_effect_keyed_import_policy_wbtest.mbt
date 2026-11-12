///|
// Actual checked two-Model Program and selected keyed acquisition. This proves
// the original request/response gate correspondence, not a Model call, Run,
// physical capacity, imported Artifact or Store/publication acknowledgement.
test "dependent Model Result policy retains the original keyed response binding" {
  let (first, acquisition, _) = client_keyed_plan_test_inputs(
    plural=true,
    declared=true,
  )
  let second = prepared_client_composed_infer_occurrences(first.owner).unwrap()[1]
  let program = @strategy.graph_program(first.owner.graph)
  let interface = @checked.unit_result_import_at(program, second.stage, 0).unwrap()
  let policy = model_effect_result_port_policy(program, interface).unwrap()
  assert_true(
    @checked.source_execution_kind(acquisition.check)
    is @checked.KeyedRequest(_),
  )
  assert_true(model_effect_keyed_policy_matches(policy, acquisition.check))
}

///|
test "imported keyed policy refuses foreign originals and another gate phase" {
  let (first, acquisition, _) = client_keyed_plan_test_inputs(
    plural=true,
    declared=true,
  )
  let (_, foreign, _) = client_keyed_plan_test_inputs(
    plural=true,
    declared=true,
  )
  let second = prepared_client_composed_infer_occurrences(first.owner).unwrap()[1]
  let program = @strategy.graph_program(first.owner.graph)
  let interface = @checked.unit_result_import_at(program, second.stage, 0).unwrap()
  let policy = model_effect_result_port_policy(program, interface).unwrap()
  assert_false(model_effect_keyed_policy_matches(policy, foreign.check))
  let mut response_count = 0
  for index in 0..<@checked.publication_policy_source_count(policy) {
    let original = @checked.publication_policy_source_at(policy, index).unwrap()
    if @checked.source_execution_kind(original)
      is @checked.KeyedResponse(binding) {
      assert_true(physical_equal(binding, acquisition.binding))
      assert_false(physical_equal(original, acquisition.check))
      response_count += 1
    }
    // Neither the response itself nor another direct Source becomes a request
    // gate merely because its declaration belongs to this same Result policy.
    assert_false(model_effect_keyed_policy_matches(policy, original))
  }
  assert_eq(response_count, 1)
}
