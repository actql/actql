///|
fn named_original_intent() -> ClientSubmittedIntent {
  prepare_client_submitted_intent(
    (
      #|{"kind":"program","input":{"original":true},"parameters":null}
    ),
    65536,
    8192,
    64,
  ).unwrap()
}

///|
fn named_original_reference() -> ClientSubmissionReferenceRecord {
  prepare_client_submission_reference_record(
    admit_client_submission_epoch_token(original_submission_token).unwrap(),
    "original-submit",
  ).unwrap()
}

///|
fn named_original_key() -> ClientSubmittedNameKey {
  prepare_client_submitted_name_key(
    "workspace",
    "actor",
    "original-name",
    "sha256:" + "b".repeat(64),
  ).unwrap()
}

///|
fn named_original_binding() -> ClientSubmittedNameBinding {
  prepare_client_submitted_name_binding(
    named_original_key(),
    "sha256:" + "b".repeat(64),
    named_original_reference().request_id,
    named_original_intent().cid,
  ).unwrap()
}

///|
test "named context spelling is original DATA distinct from NFC caller name rules" {
  let scope = "sha256:" + "b".repeat(64)
  let composed = prepare_client_submitted_name_key("é", "actor", "name", scope).unwrap()
  let decomposed = prepare_client_submitted_name_key(
    "e\u{0301}", "actor", "name", scope,
  ).unwrap()
  assert_true(composed != decomposed)
  assert_eq(client_submitted_name_key_fields(decomposed).0, "e\u{0301}")
  let binding = prepare_client_submitted_name_binding(
    decomposed,
    scope,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
  ).unwrap()
  assert_true(
    client_submitted_name_authentication_input(binding, 8192)
    .unwrap()
    .has_prefix("[\"scoped-submission-name\",\"e\u{0301}\",\"actor\",\"name\","),
  )
}

///|
test "named metadata uses the original caller name domain without normalization" {
  let scope = "sha256:" + "b".repeat(64)
  for name in ["original-name", "x".repeat(256), "é".repeat(128)] {
    let key = prepare_client_submitted_name_key(
      "workspace", "actor", name, scope,
    ).unwrap()
    assert_eq(client_submitted_name_key_fields(key).2, name)
  }
  for
    name in [
      "",
      "e\u{0301}",
      "x".repeat(257),
      "é".repeat(129),
      "line\r\n",
      "\u{0085}",
    ] {
    assert_true(
      prepare_client_submitted_name_key("workspace", "actor", name, scope)
      is Err(InvalidName),
    )
  }
  for context in ["", "x".repeat(257), "line\n", "\u{007f}"] {
    assert_true(
      prepare_client_submitted_name_key(context, "actor", "name", scope)
      is Err(InvalidContext),
    )
    assert_true(
      prepare_client_submitted_name_key("workspace", context, "name", scope)
      is Err(InvalidContext),
    )
  }
}

///|
test "named authentication input has the exact existing independent field order" {
  let key = prepare_client_submitted_name_key(
    "workspace",
    "actor\"\\é",
    "original-name",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let binding = prepare_client_submitted_name_binding(
    key,
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
  ).unwrap()
  let expected = "[\"scoped-submission-name\",\"workspace\",\"actor\\\"\\\\é\",\"original-name\",\"sha256:" +
    "b".repeat(64) +
    "\",\"sha256:" +
    "c".repeat(64) +
    "\",\"sha256:" +
    "d".repeat(64) +
    "\"]"
  assert_eq(
    client_submitted_name_authentication_input(binding, 8192).unwrap(),
    expected,
  )
  let bytes = @utf8.encode(expected).length()
  assert_eq(
    client_submitted_name_authentication_input(binding, bytes).unwrap(),
    expected,
  )
  assert_true(
    client_submitted_name_authentication_input(binding, bytes - 1)
    is Err(CapacityExceeded),
  )
}

///|
test "named observation returns the retained original reference not another candidate" {
  let reference = named_original_reference()
  let original = inspect_client_named_submitted_original(
    named_original_key(),
    "sha256:" + "b".repeat(64),
    named_original_intent(),
    named_original_binding(),
    Some(reference),
    Some(named_original_intent()),
  ).unwrap()
  assert_eq(original.wire, reference.wire)
  assert_eq(
    original.request_id,
    "sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267",
  )
}

///|
test "named scope and changed intent conflict before missing original history" {
  let changed = prepare_client_submitted_intent(
    (
      #|{"kind":"program","input":{"original":false},"parameters":null}
    ),
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(
    inspect_client_named_submitted_original(
      named_original_key(),
      "sha256:" + "c".repeat(64),
      named_original_intent(),
      named_original_binding(),
      None,
      None,
    )
    is Err(ChangedIntent),
  )
  assert_true(
    inspect_client_named_submitted_original(
      named_original_key(),
      "sha256:" + "b".repeat(64),
      changed,
      named_original_binding(),
      None,
      None,
    )
    is Err(ChangedIntent),
  )
}

///|
test "named missing or retired originals remain unavailable" {
  for missing in [true, false] {
    assert_true(
      inspect_client_named_submitted_original(
        named_original_key(),
        "sha256:" + "b".repeat(64),
        named_original_intent(),
        named_original_binding(),
        if missing {
          None
        } else {
          Some(named_original_reference())
        },
        if missing {
          Some(named_original_intent())
        } else {
          None
        },
      )
      is Err(OriginalUnavailable),
    )
  }
}

///|
test "named foreign namespace_id actor or exact name is custody loss" {
  for
    (namespace_id, actor, name) in [
      ("foreign", "actor", "original-name"),
      ("workspace", "foreign", "original-name"),
      ("workspace", "actor", "Original-name"),
    ] {
    let foreign = prepare_client_submitted_name_key(
      namespace_id,
      actor,
      name,
      "sha256:" + "b".repeat(64),
    ).unwrap()
    assert_true(
      inspect_client_named_submitted_original(
        foreign,
        "sha256:" + "b".repeat(64),
        named_original_intent(),
        named_original_binding(),
        Some(named_original_reference()),
        Some(named_original_intent()),
      )
      is Err(CustodyLost),
    )
  }
}

///|
test "named foreign submission and corrupt saved intent do not become first binding" {
  let token = admit_client_submission_epoch_token(original_submission_token).unwrap()
  let foreign = prepare_client_submission_reference_record(
    token, "another-nonce",
  ).unwrap()
  assert_true(
    inspect_client_named_submitted_original(
      named_original_key(),
      "sha256:" + "b".repeat(64),
      named_original_intent(),
      named_original_binding(),
      Some(foreign),
      Some(named_original_intent()),
    )
    is Err(CustodyLost),
  )
  let changed = prepare_client_submitted_intent(
    (
      #|{"kind":"program","input":{"original":false},"parameters":null}
    ),
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(
    inspect_client_named_submitted_original(
      named_original_key(),
      "sha256:" + "b".repeat(64),
      named_original_intent(),
      named_original_binding(),
      Some(named_original_reference()),
      Some(changed),
    )
    is Err(CustodyLost),
  )
}
