///|
// Actual existing Model/Scope/Writer/decoder callers; the independent census
// bytes/work oracle is in physical_resources. This is not Store ACK/COMMIT or
// an installed physical profile/public Model acceptance.
test "Model completed current match keeps exact original lifecycle and work domains" {
  let (active, scope, park, wire) = model_current_decode_test_start()
  let (other, foreign, _, _) = model_current_decode_test_start()
  let model_work = active.work
  let value = start_original_model_current_state_decode(
    active,
    scope,
    park,
    wire,
    { max_input_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    model_current_decode_test_limits(),
    20000,
  ).unwrap()
  let document = for _ in 0..<10000 {
    match
      advance_original_model_current_state_decode(
        active, scope, park, value, 10000,
      ) {
      CurrentDecodeContinue(..) => continue
      CurrentDecodeComplete(document, ..) => break document
      _ => abort("actual original Model decode unexpectedly refused")
    }
  } nobreak {
    abort(
      "actual original Model decode did not complete within its finite budget",
    )
  }
  let cursor = start_original_model_current_state_comparison(
    active, scope, park, document, 5,
  ).unwrap()
  assert_true(
    advance_original_model_current_state_comparison_with_match(
      other, foreign, park, cursor, 5,
    )
    is Err(@publication_host.Resource(@resources.ChangedOriginalState)),
  )
  let matched = match
    advance_original_model_current_state_comparison_with_match(
      active, scope, park, cursor, 5,
    ) {
    Ok(@resources.CurrentMatchComplete(value, work=5)) => value
    _ => abort("actual original Model comparison unexpectedly refused")
  }
  assert_true(
    original_model_current_state_match_current(active, scope, park, matched)
    is Some(same) &&
    physical_equal(matched, same),
  )
  assert_true(
    original_model_current_state_match_current(other, foreign, park, matched)
    is None,
  )
  assert_eq(active.work, model_work)
  assert_true(
    original_model_resource_park_current(active, scope, park) is Some(_),
  )
  @resources.retire_original_current_state_document(document)
  assert_true(
    original_model_current_state_match_current(active, scope, park, matched)
    is None,
  )
  @publication_host.retire_client_model_current_state_match(matched)
  assert_true(
    original_model_current_state_match_current(active, scope, park, matched)
    is None,
  )
}
