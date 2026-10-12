///|
fn client_preparation_read_test_start(
  read : ClientModelReadPreparation,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  document : @publication.ModelOriginalResourceDocument,
  layout : ClientNodeModelPreparationLayout,
  max_bytes? : Int = 4000,
  max_work? : Int = 3,
) -> Result[
  @resources.OriginalStateDocumentRead,
  ClientModelOriginalPreparationReadIssue,
] {
  let storage = @publication.seal_run_evidence_value(
    "model_original_storage_binding",
    client_original_storage_test_body(),
    2048,
    32,
    2,
  ).unwrap()
  read_client_model_original_preparation_base(
    read,
    scope,
    compiled,
    definition,
    plan,
    document,
    Some(layout),
    client_node_layout_test_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    storage,
    max_bytes,
    400,
    10,
    1,
    0,
    0,
    max_work,
  )
}

///|
test "original preparation read connects actual Writer envelope to existing Reader and original census" {
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
  let wire = client_preparation_base_test_finish(
    value, scope, compiled, definition, plan, layout,
  ).unwrap()
  assert_eq(
    wire,
    client_preparation_base_test_expected(compiled, definition, plan, layout),
  )
  let outer = @publication.read_model_original_resource_document(
    wire, 10000, 1000, 16,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let reader = client_preparation_read_test_start(
    read,
    scope,
    compiled,
    definition,
    plan,
    outer,
    layout,
    max_bytes=378,
  ).unwrap()
  assert_true(
    @resources.advance_original_state_document_read(reader, 1)
    is @resources.DocumentContinue(work=1),
  )
  assert_true(
    @resources.advance_original_state_document_read(reader, 1)
    is @resources.DocumentContinue(work=1),
  )
  let document = match
    @resources.advance_original_state_document_read(reader, 1) {
    @resources.DocumentComplete(document, work=1) => document
    _ => abort("expected original resource Reader completion")
  }
  for block in [0, 1] {
    assert_eq(
      client_model_read_state_block_matches(
        read, compiled, definition, plan, document, block,
      ),
      Ok(true),
    )
  }
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.retire_original_state_document(document)
  assert_eq(
    client_model_read_state_block_matches(
      read, compiled, definition, plan, document, 0,
    ),
    Err(@resources.ChangedOriginalState),
  )
  // Retiring parsed data is not the physical original read's cleanup proof.
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
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "original preparation read rejects foreign Scope and finite limits without consuming original read" {
  let (compiled, definition, plan, ledger, scope, layout) = client_node_state_test_scope(
    17,
  )
  let value = client_node_state_test_prepare(
    scope, compiled, definition, plan, layout,
  ).unwrap()
  let read = client_node_model_state_read(value).unwrap()
  let outer = @publication.read_model_original_resource_document(
    client_preparation_base_test_expected(compiled, definition, plan, layout),
    10000,
    1000,
    16,
  ).unwrap()
  assert_true(
    client_preparation_read_test_start(
      read, scope, compiled, definition, plan, outer, layout,
    )
    is Err(Origin(Unavailable)),
  )
  assert_true(
    advance_client_node_model_read_state(value, compiled, definition, plan, 17)
    is @resources.StateWriteComplete(work=17),
  )
  let (
    other_compiled,
    other_definition,
    other_plan,
    other_ledger,
    other_scope,
    _,
  ) = client_node_state_test_scope(17)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    client_preparation_read_test_start(
      read, other_scope, compiled, definition, plan, outer, layout,
    )
    is Err(Origin(ForeignRun)),
  )
  for limit in [-1, 0, 377] {
    assert_true(
      client_preparation_read_test_start(
        read,
        scope,
        compiled,
        definition,
        plan,
        outer,
        layout,
        max_bytes=limit,
      )
      is Err(_),
    )
  }
  assert_true(
    client_preparation_read_test_start(
      read,
      scope,
      compiled,
      definition,
      plan,
      outer,
      layout,
      max_work=2,
    )
    is Err(State(@resources.WorkLimit)),
  )
  let changed = @publication.read_model_original_resource_document(
    client_preparation_base_test_expected(compiled, definition, plan, layout).replace(
      old="\"run_id\":\"node-state\"",
      new="\"run_id\":\"foreign\"",
    ),
    10000,
    1000,
    16,
  ).unwrap()
  assert_true(
    client_preparation_read_test_start(
      read, scope, compiled, definition, plan, changed, layout,
    )
    is Err(Origin(OriginMismatch("run_id"))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(client_model_read_available(read, compiled, definition, plan))
  let reader = client_preparation_read_test_start(
    read, scope, compiled, definition, plan, outer, layout,
  ).unwrap()
  @resources.cancel_original_state_document_read(reader)
  assert_true(
    @resources.advance_original_state_document_read(reader, 3)
    is @resources.DocumentFailed(@resources.Terminal, work=0),
  )
  assert_true(client_model_read_available(read, compiled, definition, plan))
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    client_preparation_read_test_start(
      read, scope, compiled, definition, plan, outer, layout,
    )
    is Err(Origin(Unavailable)),
  )
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
  assert_true(
    finish_client_model_read_scope(
      other_scope, other_compiled, other_definition, other_plan, true,
    ).unwrap(),
  )
  assert_eq(@resources.ledger_usage(other_ledger).reserved_execution_bytes, 0L)
}

///|
test "original preparation read uses the saved inner body rather than a substituted matching census" {
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
  let changed_body = client_preparation_base_test_resource_wire().replace(
    old="[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"7003\"",
    new="[\"16\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"7003\"",
  )
  // Independent changed vector: original planning usage 16 instead of 17;
  // SHA256 calculated independently of either product Reader or Writer.
  let changed_wire = client_preparation_base_test_expected(
      compiled, definition, plan, layout,
    )
    .replace(old=client_preparation_base_test_resource_wire(), new=changed_body)
    .replace(
      old="e6c6b87dc82a5b9e10b90e5546e57cf6d805587584df7cd796f8a61608350967",
      new="2ea6ab530a39be1d81964613cc8cc432847159c400a3e81f89e22bb34ab3b7d7",
    )
  let document = @publication.read_model_original_resource_document(
    changed_wire, 10000, 1000, 16,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let reader = client_preparation_read_test_start(
    read, scope, compiled, definition, plan, document, layout,
  ).unwrap()
  let saved = match @resources.advance_original_state_document_read(reader, 3) {
    @resources.DocumentComplete(document, work=3) => document
    _ => abort("well-formed changed resource body must reach data comparison")
  }
  for block in [0, 1] {
    assert_eq(
      client_model_read_state_block_matches(
        read, compiled, definition, plan, saved, block,
      ),
      Ok(false),
    )
  }
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(client_model_read_available(read, compiled, definition, plan))
  @resources.retire_original_state_document(saved)
  settle_client_node_model_read_state(value, compiled, definition, plan, true).unwrap()
  assert_true(
    finish_client_model_read_scope(scope, compiled, definition, plan, true).unwrap(),
  )
}
