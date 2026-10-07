///|
fn cancellation_test_identity(
  cancel_id? : String = "cancel-a",
  revision? : Int = 19,
) -> ClientCancellationIdentity {
  prepare_client_cancellation_identity(
    "namespace-a",
    start_test_cid("a"),
    cancel_id,
    start_test_definition(),
    revision,
  ).unwrap()
}

///|
test "cancellation identity preserves opaque Unicode keys" {
  let composed = cancellation_test_identity(cancel_id="é")
  let decomposed = cancellation_test_identity(cancel_id="e\u{0301}")
  assert_eq(composed.cancel_id, "é")
  assert_eq(decomposed.cancel_id, "e\u{0301}")
  let multibyte = cancellation_test_identity(cancel_id="é".repeat(256))
  assert_eq(multibyte.cancel_id, "é".repeat(256))
  assert_eq(
    client_cancellation_identity_relation(composed, decomposed),
    DifferentOperation,
  )
}

///|
test "cancellation identity rejects invalid scope key and revision" {
  let definition = start_test_definition()
  assert_eq(
    prepare_client_cancellation_identity(
      "namespace-a",
      start_test_cid("a"),
      "",
      definition,
      0,
    ),
    Err(InvalidOperationId),
  )
  for id in ["cancel\r", "cancel\n", "cancel\r\n", "x".repeat(257)] {
    assert_eq(
      prepare_client_cancellation_identity(
        "namespace-a",
        start_test_cid("a"),
        id,
        definition,
        0,
      ),
      Err(InvalidOperationId),
    )
  }
  assert_eq(
    prepare_client_cancellation_identity(
      "namespace-a", "not-a-cid", "cancel-a", definition, 0,
    ),
    Err(InvalidScope),
  )
  assert_eq(
    prepare_client_cancellation_identity(
      "namespace-a",
      start_test_cid("a"),
      "cancel-a",
      definition,
      -1,
    ),
    Err(InvalidRevision),
  )
}

///|
test "same cancellation key cannot change target or expected revision" {
  let original = cancellation_test_identity()
  assert_eq(
    client_cancellation_identity_relation(
      { ..original, run_definition_cid: start_test_cid("b"), },
      original,
    ),
    ChangedIntent,
  )
  assert_eq(
    client_cancellation_identity_relation(
      cancellation_test_identity(revision=20),
      original,
    ),
    ChangedIntent,
  )
  for
    other in [
      { ..original, namespace_id: "namespace-b", },
      { ..original, authority_scope_cid: start_test_cid("b"), },
      cancellation_test_identity(cancel_id="cancel-b"),
    ] {
    assert_eq(
      client_cancellation_identity_relation(other, original),
      DifferentOperation,
    )
  }
}

///|
test "first cancellation checks its revision before the existing Run decision" {
  let identity = cancellation_test_identity()
  let definition = start_test_definition()
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      None,
      definition,
      19,
      true,
      false,
      false,
    ),
    Ok(RecordCancellation(AcceptCancellation)),
  )
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      None,
      definition,
      19,
      true,
      false,
      true,
    ),
    Ok(RecordCancellation(AlreadyRequested)),
  )
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      None,
      definition,
      19,
      true,
      true,
      true,
    ),
    Ok(RecordCancellation(AlreadyTerminal)),
  )
  for terminal in [false, true] {
    assert_eq(
      prepare_client_cancellation_operation(
        identity,
        None,
        definition,
        20,
        true,
        terminal,
        true,
      ),
      Err(RevisionConflict),
    )
  }
}

///|
test "cancellation replay never recomputes the original outcome from current flags" {
  let original = cancellation_test_identity()
  let definition = start_test_definition()
  for terminal in [false, true] {
    assert_eq(
      prepare_client_cancellation_operation(
        original,
        Some(original),
        definition,
        21,
        true,
        terminal,
        true,
      ),
      Ok(ReplayOriginalCancellation),
    )
  }
  assert_eq(
    prepare_client_cancellation_operation(
      cancellation_test_identity(revision=21),
      Some(original),
      definition,
      21,
      true,
      true,
      true,
    ),
    Err(ChangedIntent),
  )
}

///|
test "cancellation replay retains current authority and exact Run admission" {
  let identity = cancellation_test_identity()
  let definition = start_test_definition()
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      Some(identity),
      definition,
      21,
      false,
      true,
      true,
    ),
    Err(AuthorizationDenied),
  )
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      Some({ ..identity, namespace_id: "other", }),
      definition,
      19,
      true,
      false,
      false,
    ),
    Err(DifferentOperation),
  )
  assert_eq(
    prepare_client_cancellation_operation(
      { ..identity, run_definition_cid: start_test_cid("b"), },
      None,
      definition,
      19,
      true,
      false,
      false,
    ),
    Err(ForeignRunDefinition),
  )
}

///|
test "cancellation revision exhaustion cannot issue a new Run request" {
  let identity = cancellation_test_identity(revision=2147483647)
  let definition = start_test_definition()
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      None,
      definition,
      2147483647,
      true,
      false,
      false,
    ),
    Err(RevisionConflict),
  )
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      None,
      definition,
      2147483647,
      true,
      true,
      false,
    ),
    Ok(RecordCancellation(AlreadyTerminal)),
  )
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      None,
      definition,
      2147483647,
      true,
      false,
      true,
    ),
    Ok(RecordCancellation(AlreadyRequested)),
  )
  assert_eq(
    prepare_client_cancellation_operation(
      identity,
      Some(identity),
      definition,
      2147483647,
      true,
      false,
      false,
    ),
    Ok(ReplayOriginalCancellation),
  )
}
