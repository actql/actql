///|
fn client_model_state_match_test_wire() -> String {
  // Saved independent 406-byte vector, not produced by this Run's Writer.
  "[\"actql-original-ledger-state/0.1\",[\"17\",\"2\",\"3\",\"11\",\"10\",\"7\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"1\",\"0\",\"0\",true,true,false,\"reading\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
}

///|
fn client_model_state_match_test_document(
  wire : String,
) -> @resources.OriginalStateDocument {
  let node = @source.parse_json(wire, {
    max_input_bytes: 4000,
    max_nodes: 400,
    max_depth: 10,
  }).unwrap()
  let source = @decode.admit(node, {
    max_nodes: 400,
    max_depth: 10,
    max_string_bytes: 100,
    max_total_string_bytes: 4000,
  }).unwrap()
  let read = @resources.start_original_state_document_read(source, 1, 0, 0, 3).unwrap()
  match @resources.advance_original_state_document_read(read, 3) {
    @resources.DocumentComplete(document, ..) => document
    _ => abort("unexpected document failure")
  }
}

///|
test "checked original state matching binds live Run and never authenticates equal packets" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let (_, foreign_definition, foreign_plan) = client_model_read_test_run(
    "state-match-foreign",
  )
  let writer = @encode.writer(1000, 200, 10)
  let read = prepare_client_model_read_state(scope, writer, 7L, 5L).unwrap()
  assert_true(
    advance_client_model_read_state(read, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let document = client_model_state_match_test_document(
    client_model_state_match_test_wire(),
  )
  let before = @resources.ledger_usage(ledger)
  for block in [0, 1] {
    assert_eq(
      client_model_read_state_block_matches(
        read, compiled, definition, plan, document, block,
      ),
      Ok(true),
    )
  }
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, foreign_definition, plan, document, 0,
    ),
    Err(@resources.ForeignOrigin),
  )
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, foreign_plan, document, 0,
    ),
    Err(@resources.ForeignOrigin),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Value equality does not bind a saved packet to this scope. A separately
  // issued original Run/Ledger with equal quantities also matches the packet;
  // neither result issues Store authentication, restoration or Model grants.
  let (other, other_definition, other_plan) = client_model_read_test_run(
    "state-match-other-run",
  )
  let other_ledger = @resources.create_ledger({
    planning_work: 17,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 10L,
    execution_bytes: 7L,
  }).unwrap()
  let other_bootstrap = @resources.reserve_capacity(other_ledger, 3L, 2L).unwrap()
  let other_scope = begin_client_model_read_scope(
    other, other_definition, other_plan, other_ledger, other_bootstrap, 1, 0, 0,
  ).unwrap()
  assert_false(
    @publication.publication_contract_identity(definition) ==
    @publication.publication_contract_identity(other_definition),
  )
  let other_writer = @encode.writer(1000, 200, 10)
  let other_read = prepare_client_model_read_state(
    other_scope, other_writer, 7L, 5L,
  ).unwrap()
  assert_true(
    advance_client_model_read_state(
      other_read, other, other_definition, other_plan, 17,
    )
    is @resources.StateWriteComplete(work=17),
  )
  assert_false(physical_equal(ledger, other_ledger))
  assert_eq(
    client_model_read_state_block_matches(
      other_read, other, other_definition, other_plan, document, 1,
    ),
    Ok(true),
  )
  @resources.retire_original_state_document(document)
  settle_client_model_read(read, true).unwrap()
  settle_client_model_read(other_read, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    finish_client_model_read_scope(
      other_scope, other, other_definition, other_plan, true,
    ).unwrap(),
  )
}

///|
test "checked original state matching refuses Reading Writing and cleanup pending claims" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let writer = @encode.writer(1000, 200, 10)
  let read = prepare_client_model_read_state(scope, writer, 7L, 5L).unwrap()
  let document = client_model_state_match_test_document(
    client_model_state_match_test_wire(),
  )
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, document, 0,
    ),
    Err(@resources.ChangedOriginalState),
  )
  assert_true(
    advance_client_model_read_state(read, compiled, definition, plan, 1)
    is @resources.StateWriteContinue(work=1),
  )
  assert_true(
    settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, document, 0,
    ),
    Err(@resources.ChangedOriginalState),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(@resources.original_state_document_usage(document) is Some(_))
  // A normal Reading claim with bytewise equal saved contents is still not
  // a completed Writer. Availability for its own ordinary read is separate.
  let (other, other_definition, other_plan, _, other_scope) = client_model_state_test_scope(
    17,
  )
  let other_read = prepare_client_model_read(other_scope, 7L, 5L).unwrap()
  assert_true(
    client_model_read_available(other_read, other, other_definition, other_plan),
  )
  assert_eq(
    client_model_read_state_block_matches(
      other_read, other, other_definition, other_plan, document, 0,
    ),
    Err(@resources.ChangedOriginalState),
  )
  @resources.retire_original_state_document(document)
  settle_client_model_read(read, true).unwrap()
  settle_client_model_read(other_read, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    finish_client_model_read_scope(
      other_scope, other, other_definition, other_plan, true,
    ).unwrap(),
  )
}

///|
test "checked original state matching preserves current serial and retired document fences" {
  let (compiled, definition, plan, ledger, scope) = client_model_state_test_scope(
    17,
  )
  let writer = @encode.writer(1000, 200, 10)
  let read = prepare_client_model_read_state(scope, writer, 7L, 5L).unwrap()
  assert_true(
    advance_client_model_read_state(read, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let wire = client_model_state_match_test_wire()
  let changed = client_model_state_match_test_document(
    wire.replace(old="\"-3\"", new="\"-4\""),
  )
  let before = @resources.ledger_usage(ledger)
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, changed, 1,
    ),
    Ok(false),
  )
  let allocation = client_model_state_match_test_document(
    wire.replace(old="\"7\",\"5\",true", new="\"6\",\"5\",true"),
  )
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, allocation, 1,
    ),
    Ok(false),
  )
  let document = client_model_state_match_test_document(wire)
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, document, -1,
    ),
    Err(@resources.IncompleteInventory),
  )
  @resources.retire_original_state_document(document)
  assert_true(@resources.original_state_document_usage(document) is None)
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, document, 1,
    ),
    Err(@resources.ChangedOriginalState),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Entering the existing one-shot consumer invalidates data comparison too.
  let live_document = client_model_state_match_test_document(wire)
  let consumer = claim_client_model_read_preparation(
    read, compiled, definition, plan, 7L, 5L,
  ).unwrap()
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, live_document, 1,
    ),
    Err(@resources.ChangedOriginalState),
  )
  assert_true(
    @resources.original_state_document_usage(live_document) is Some(_),
  )
  @resources.retire_original_state_document(changed)
  @resources.retire_original_state_document(allocation)
  @resources.retire_original_state_document(live_document)
  stop_client_model_read_consumer(consumer).unwrap()
  settle_client_model_read_consumer(consumer, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}
