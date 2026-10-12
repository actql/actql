///|
fn client_preparation_comparison_test_document(
  read : ClientModelReadPreparation,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout,
  wire : String,
) -> @resources.OriginalStateDocument {
  let outer = @publication.read_model_original_resource_document(
    wire, 10000, 1000, 16,
  ).unwrap()
  let reader = client_preparation_read_test_start(
    read, scope, compiled, definition, plan, outer, layout,
  ).unwrap()
  match @resources.advance_original_state_document_read(reader, 3) {
    @resources.DocumentComplete(document, work=3) => document
    _ => abort("expected bounded saved preparation Reader completion")
  }
}

///|
test "original preparation comparison connects saved Reader to every block and final fence" {
  for quantum in [1, 3] {
    let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
      17,
    )
    let value = client_node_state_test_prepare(
      scope, compiled, definition, plan, layout,
    ).unwrap()
    let read = client_node_model_state_read(value).unwrap()
    assert_true(
      advance_client_node_model_read_state(
        value, compiled, definition, plan, 17,
      )
      is @resources.StateWriteComplete(work=17),
    )
    let wire = client_preparation_base_test_finish(
      value, scope, compiled, definition, plan, layout,
    ).unwrap()
    assert_eq(
      wire,
      client_preparation_base_test_expected(compiled, definition, plan, layout),
    )
    let document = client_preparation_comparison_test_document(
      read, scope, compiled, definition, plan, layout, wire,
    )
    let before = @resources.ledger_usage(ledger)
    assert_true(
      start_client_model_original_preparation_comparison(
        read, compiled, definition, plan, document, 2,
      )
      is Err(@resources.WorkLimit),
    )
    let comparison = start_client_model_original_preparation_comparison(
      read, compiled, definition, plan, document, 3,
    ).unwrap()
    let spent = for total = 0 {
      match
        advance_client_model_original_preparation_comparison(
          comparison, compiled, definition, plan, quantum,
        ) {
        PreparationComparisonContinue(work=n) => continue total + n
        PreparationComparisonComplete(work=n) => break total + n
        _ => abort("unexpected original data comparison failure")
      }
    }
    // Independent inventory: bootstrap + read token + final live census = 3.
    // These steps do not charge/refund Model or planning work domains.
    assert_eq(spent, 3)
    assert_true(comparison.read is None && comparison.cursor is None)
    assert_true(
      client_model_read_state_block_matches(
        read, compiled, definition, plan, document, 0,
      ).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    @resources.retire_original_state_document(document)
    stop_client_node_model_read_state(value, scope, compiled, definition, plan).unwrap()
    assert_true(
      settle_client_node_model_read_state(
        value, compiled, definition, plan, false,
      )
      is Err(Resource(@resources.CleanupPending)),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 7003L)
    settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
    assert_true(
      finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
    )
  }
}

///|
test "original preparation comparison refuses a later token after a matching first block" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let value = client_node_state_test_prepare(
    scope, compiled, definition, plan, layout,
  ).unwrap()
  let read = client_node_model_state_read(value).unwrap()
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  // Independently changed saved read reservation: execution 2999, not 3000.
  // The aggregate state/bootstrap are unchanged. SHA256 is fixed from this
  // literal fixture, independently of the product Writer/Reader.
  let wire = client_preparation_base_test_expected(
      compiled, definition, plan, layout,
    )
    .replace(
      old="[\"-2\",\"0\",\"7000\",\"3000\"",
      new="[\"-2\",\"0\",\"7000\",\"2999\"",
    )
    .replace(
      old="e6c6b87dc82a5b9e10b90e5546e57cf6d805587584df7cd796f8a61608350967",
      new="30d85edf81aaea2054bce632a2e7665901d94c66872cb47a8877843f1d281cb4",
    )
  let document = client_preparation_comparison_test_document(
    read, scope, compiled, definition, plan, layout, wire,
  )
  assert_true(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, document, 0,
    ).unwrap(),
  )
  let comparison = start_client_model_original_preparation_comparison(
    read, compiled, definition, plan, document, 3,
  ).unwrap()
  assert_true(
    advance_client_model_original_preparation_comparison(
      comparison, compiled, definition, plan, 1,
    )
    is PreparationComparisonContinue(work=1),
  )
  assert_true(
    advance_client_model_original_preparation_comparison(
      comparison, compiled, definition, plan, 1,
    )
    is PreparationComparisonFailed(@resources.RecordMismatch, work=1),
  )
  assert_true(comparison.read is None && comparison.cursor is None)
  assert_true(client_model_read_available(read, compiled, definition, plan))
  assert_eq(@resources.ledger_usage(ledger).planning_work, 17)
  @resources.retire_original_state_document(document)
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}

///|
test "original preparation comparison keeps same cleanup through foreign reentry cancel and stop" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let (_, foreign_definition, _) = client_model_read_test_run(
    "comparison-foreign",
  )
  let value = client_node_state_test_prepare(
    scope, compiled, definition, plan, layout,
  ).unwrap()
  let read = client_node_model_state_read(value).unwrap()
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let document = client_preparation_comparison_test_document(
    read,
    scope,
    compiled,
    definition,
    plan,
    layout,
    client_preparation_base_test_expected(compiled, definition, plan, layout),
  )
  assert_true(
    start_client_model_original_preparation_comparison(
      read, compiled, foreign_definition, plan, document, 3,
    )
    is Err(@resources.Original(@resources.ForeignOrigin)),
  )
  let before = @resources.ledger_usage(ledger)
  let cancelled = start_client_model_original_preparation_comparison(
    read, compiled, definition, plan, document, 3,
  ).unwrap()
  assert_true(
    advance_client_model_original_preparation_comparison(
      cancelled, compiled, definition, plan, 1,
    )
    is PreparationComparisonContinue(work=1),
  )
  cancel_client_model_original_preparation_comparison(cancelled)
  assert_true(cancelled.read is None && cancelled.cursor is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(client_model_read_available(read, compiled, definition, plan))
  let comparison = start_client_model_original_preparation_comparison(
    read, compiled, definition, plan, document, 3,
  ).unwrap()
  assert_true(
    advance_client_model_original_preparation_comparison(
      comparison, compiled, foreign_definition, plan, 1,
    )
    is PreparationComparisonFailed(
      @resources.Original(@resources.ForeignOrigin),
      work=0
    ),
  )
  assert_true(
    advance_client_model_original_preparation_comparison(
      comparison, compiled, definition, plan, 0,
    )
    is PreparationComparisonFailed(@resources.InvalidQuantum, work=0),
  )
  assert_true(
    advance_client_model_original_preparation_comparison(
      comparison, compiled, definition, plan, 2,
    )
    is PreparationComparisonContinue(work=2),
  )
  // Resource stop across an await must prevent final data completion.
  stop_client_node_model_read_state(value, scope, compiled, definition, plan).unwrap()
  assert_true(
    advance_client_model_original_preparation_comparison(
      comparison, compiled, definition, plan, 1,
    )
    is PreparationComparisonFailed(
      @resources.Original(@resources.ChangedOriginalState),
      work=1
    ),
  )
  assert_true(comparison.read is None && comparison.cursor is None)
  assert_true(
    settle_client_node_model_read_state(
      value, compiled, definition, plan, false,
    )
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 7003L)
  cancel_client_model_original_preparation_comparison(comparison)
  assert_true(
    advance_client_model_original_preparation_comparison(
      comparison, compiled, definition, plan, 1,
    )
    is PreparationComparisonFailed(@resources.Terminal, work=0),
  )
  @resources.retire_original_state_document(document)
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}
