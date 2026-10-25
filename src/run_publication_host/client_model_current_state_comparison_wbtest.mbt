///|
// Independent current vector for the synthetic checked Host fixture, not
// bytes obtained from its Writer. This demonstrates no physical byte grant,
// actual installed Model park, Store authentication or journal COMMIT.
fn client_current_comparison_test_document(
  wire? : String = "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"20\",\"12\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"2\",\"0\",\"0\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]",
) -> @resources.OriginalCurrentStateDocument {
  let node = @source.parse_json(wire, {
    max_input_bytes: 4000,
    max_nodes: 400,
    max_depth: 10,
  }).unwrap()
  let limits : @decode.Limits = {
    max_nodes: 400,
    max_depth: 10,
    max_string_bytes: 100,
    max_total_string_bytes: 4000,
  }
  let source = @decode.admit(node, limits).unwrap()
  let read = @resources.start_original_current_state_document_read(
    source, 2, 0, 0, 3, limits,
  ).unwrap()
  match @resources.advance_original_current_state_document_read(read, 3) {
    @resources.CurrentDocumentComplete(document, work=3) => document
    _ => abort("independent current Host fixture could not be read")
  }
}

///|
test "checked current comparison exact work keeps original Scope and park pending" {
  for quantum in [1, 2, 3] {
    let (compiled, definition, plan) = client_model_read_test_run(
      "current-comparison",
    )
    let (scope, consumer) = client_current_write_test_scope(
      compiled, definition, plan, 17,
    )
    let park = park_client_model_read_consumer_for_state_write(
      scope, consumer, compiled, definition, plan,
    ).unwrap()
    let document = client_current_comparison_test_document()
    let before = @resources.ledger_usage(scope.ledger)
    assert_true(
      start_client_model_current_state_comparison(
        park, scope, compiled, definition, plan, document, 2,
      )
      is Err(@resources.WorkLimit),
    )
    let value = start_client_model_current_state_comparison(
      park, scope, compiled, definition, plan, document, 3,
    ).unwrap()
    let mut work = 0
    for _ in 0..<3 {
      match
        advance_client_model_current_state_comparison(
          value, park, scope, compiled, definition, plan, quantum,
        ) {
        Ok(@resources.ComparisonContinue(work=n)) => work += n
        Ok(@resources.ComparisonComplete(work=n)) => {
          work += n
          break
        }
        _ => abort("checked current comparison unexpectedly refused")
      }
    }
    assert_eq(work, 3)
    assert_true(
      @resources.original_current_state_comparison_current(value, park) is None,
    )
    assert_eq(@resources.ledger_usage(scope.ledger), before)
    assert_true(
      client_model_resource_park_current(
        park, scope, compiled, definition, plan,
      )
      is Some(_),
    )
    assert_true(
      settle_client_model_read_consumer(consumer, false)
      is Err(Resource(@resources.Resource(@resources.ResourceParked))),
    )
    @resources.retire_original_current_state_document(document)
    // No authenticated COMMIT exists. Keep the original custody/park pending.
  }
}

///|
test "checked current comparison refuses foreign Scope Run park and cursor without progress" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "current-comparison-foreign",
  )
  let (foreign, foreign_definition, foreign_plan) = client_model_read_test_run(
    "current-comparison-other-run",
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
  let other_document = client_current_comparison_test_document()
  let before = @resources.ledger_usage(scope.ledger)
  for
    (caller, run, graph, owner) in [
      (foreign, definition, plan, scope),
      (compiled, foreign_definition, plan, scope),
      (compiled, definition, foreign_plan, scope),
      (compiled, definition, plan, other),
    ] {
    assert_true(
      start_client_model_current_state_comparison(
        park, owner, caller, run, graph, document, 3,
      )
      is Err(@resources.Original(@resources.ChangedOriginalState)),
    )
  }
  let value = start_client_model_current_state_comparison(
    park, scope, compiled, definition, plan, document, 3,
  ).unwrap()
  let other_value = start_client_model_current_state_comparison(
    other_park, other, compiled, definition, plan, other_document, 3,
  ).unwrap()
  assert_true(
    advance_client_model_current_state_comparison(
      other_value, park, scope, compiled, definition, plan, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_true(
    advance_client_model_current_state_comparison(
      value, park, other, compiled, definition, plan, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  assert_true(
    advance_client_model_current_state_comparison(
      other_value, other_park, other, compiled, definition, plan, 1,
    )
    is Ok(@resources.ComparisonContinue(work=1)),
  )
  assert_true(
    advance_client_model_current_state_comparison(
      value, park, scope, compiled, definition, plan, 1,
    )
    is Ok(@resources.ComparisonContinue(work=1)),
  )
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  cancel_client_model_current_state_comparison(value)
  cancel_client_model_current_state_comparison(other_value)
  assert_true(
    @resources.original_current_state_comparison_current(value, park) is None,
  )
  @resources.retire_original_current_state_document(document)
  @resources.retire_original_current_state_document(other_document)
}

///|
test "checked current comparison retired data refuses without dropping original custody" {
  let (compiled, definition, plan) = client_model_read_test_run(
    "current-comparison-retired",
  )
  let (scope, consumer) = client_current_write_test_scope(
    compiled, definition, plan, 17,
  )
  let park = park_client_model_read_consumer_for_state_write(
    scope, consumer, compiled, definition, plan,
  ).unwrap()
  let document = client_current_comparison_test_document()
  let value = start_client_model_current_state_comparison(
    park, scope, compiled, definition, plan, document, 3,
  ).unwrap()
  assert_true(
    advance_client_model_current_state_comparison(
      value, park, scope, compiled, definition, plan, 1,
    )
    is Ok(@resources.ComparisonContinue(work=1)),
  )
  let before = @resources.ledger_usage(scope.ledger)
  @resources.retire_original_current_state_document(document)
  assert_true(
    advance_client_model_current_state_comparison(
      value, park, scope, compiled, definition, plan, 1,
    )
    is Err(Resource(@resources.ChangedOriginalState)),
  )
  cancel_client_model_current_state_comparison(value)
  assert_eq(@resources.ledger_usage(scope.ledger), before)
  assert_true(
    client_model_resource_park_current(park, scope, compiled, definition, plan)
    is Some(_),
  )
  assert_true(
    settle_client_model_read_consumer(consumer, false)
    is Err(Resource(@resources.Resource(@resources.ResourceParked))),
  )
}
