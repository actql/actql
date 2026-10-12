///|
test "checked completed current match rechecks actual Scope Run and park without changing ownership" {
  let (compiled, definition, plan) = client_model_read_test_run("current-match")
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "other-current-match",
  )
  let (scope, consumer) = client_current_write_test_scope(
    compiled, definition, plan, 17,
  )
  let (other, other_consumer) = client_current_write_test_scope(
    compiled, definition, plan, 17,
  )
  let park = park_client_model_read_consumer_for_state_write(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let other_park = park_client_model_read_consumer_for_state_write(
    other, other_consumer, compiled, definition, plan,
  ).unwrap()
  let document = client_current_comparison_test_document()
  let cursor = start_client_model_current_state_comparison(
    park, scope, compiled, definition, plan, document, 3,
  ).unwrap()
  let before = @resources.ledger_usage(scope.ledger)
  assert_true(
    advance_client_model_current_state_comparison_with_match(
      cursor, park, other, compiled, definition, plan, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_true(
    advance_client_model_current_state_comparison_with_match(
      cursor, other_park, scope, compiled, definition, plan, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  let value = match
    advance_client_model_current_state_comparison_with_match(
      cursor, park, scope, compiled, definition, plan, 3,
    ) {
    Ok(@resources.CurrentMatchComplete(value, work=3)) => value
    _ => abort("checked independent completed comparison unexpectedly refused")
  }
  assert_true(
    client_model_current_state_match_current(
      value, park, scope, compiled, definition, plan,
    )
    is Some(same) &&
    physical_equal(value, same),
  )
  assert_true(
    client_model_current_state_match_current(
      value, park, other, compiled, definition, plan,
    )
    is None,
  )
  assert_true(
    client_model_current_state_match_current(
      value, other_park, scope, compiled, definition, plan,
    )
    is None,
  )
  assert_true(
    client_model_current_state_match_current(
      value, park, scope, foreign, foreign_definition, foreign_plan,
    )
    is None,
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.Resource(@resources.ResourceParked))),
  )
  retire_client_model_current_state_match(value)
  assert_true(
    client_model_current_state_match_current(
      value, park, scope, compiled, definition, plan,
    )
    is None,
  )
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is Some(_),
  )
  @resources.retire_original_current_state_document(document)
}
