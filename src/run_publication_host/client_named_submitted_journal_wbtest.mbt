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

///|
test "closed named census observes the selected physical original before missing or retained" {
  let key = named_original_key()
  let index = "4de7f25f51dc74045566f9b43386850973e3635dae14c43775329d4c43e06ad7"
  let other = "a".repeat(64)
  let body = client_submitted_name_row_body({
    binding: named_original_binding(),
    authenticator: b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  }).unwrap()
  for target_present in [false, true] {
    let scanned = Ref(0)
    let selected_reads : Array[(String, String)] = []
    let controls : Array[(String, String)] = []
    let select : ClientJournalPhysicalRow = { key: index, body, revision: 0L, }
    let issued : ClientJournalPhysicalRow = {
      key: "issued",
      body: if target_present {
        b"2"
      } else {
        b"1"
      },
      revision: if target_present {
        2L
      } else {
        1L
      },
    }
    let result = inspect_client_submitted_name_inventory(
      key,
      2,
      (table, cursor) => {
        controls.push((table, cursor))
        Ok(if cursor == "" { Some(issued) } else { None })
      },
      cursor => {
        scanned.val += 1
        Ok(
          if target_present && cursor == "" {
            Some((index, 0L))
          } else if cursor < other {
            Some((other, 0L))
          } else {
            None
          },
        )
      },
      (table, key) => {
        selected_reads.push((table, key))
        if table == "client_submission_name_custody" {
          Ok(Some(issued))
        } else {
          Ok(if target_present { Some(select) } else { None })
        }
      },
      "lost",
    ).unwrap()
    assert_eq(result.index, index)
    assert_eq(result.issued.to_int64(), issued.revision)
    assert_eq(result.issued_revision, issued.revision)
    assert_eq(
      result.original.map(row => row.body),
      if target_present {
        Some(body)
      } else {
        None
      },
    )
    assert_eq(scanned.val.to_int64(), issued.revision + 1L)
    assert_eq(controls, [
      ("client_submission_name_custody", ""),
      ("client_submission_name_custody", "issued"),
    ])
    assert_eq(selected_reads, [
      ("client_submission_name_custody", "issued"),
      ("client_submission_names", index),
    ])
  }
}

///|
test "closed named census distinguishes torn inventory and first physical refusal" {
  let index = "4de7f25f51dc74045566f9b43386850973e3635dae14c43775329d4c43e06ad7"
  for mode in 0..<7 {
    let issued : ClientJournalPhysicalRow = {
      key: "issued",
      body: b"1",
      revision: if mode == 0 {
        0L
      } else {
        1L
      },
    }
    let selected_reads = Ref(0)
    let result = inspect_client_submitted_name_inventory(
      named_original_key(),
      4,
      (_, cursor) => Ok(if cursor == "" { Some(issued) } else { None }),
      cursor => {
        if mode == 1 {
          Err("original physical failure")
        } else if mode == 2 {
          Ok(None)
        } else if mode == 3 {
          Ok(Some((index, 1L)))
        } else if cursor == "" || mode == 4 {
          Ok(Some((index, 0L)))
        } else {
          Ok(None)
        }
      },
      (table, key) => {
        if table == "client_submission_name_custody" {
          Ok(Some(issued))
        } else {
          selected_reads.val += 1
          if mode == 5 {
            Ok(None)
          } else {
            Ok(Some({ key, body: b"changed", revision: 1L, }))
          }
        }
      },
      "lost",
    )
    assert_true(
      result is Err(error) &&
      error == (if mode == 1 { "original physical failure" } else { "lost" }),
    )
    assert_eq(selected_reads.val, if mode < 5 { 0 } else { 1 })
  }
}

///|
test "authenticated name precedence never borrows the proposed reference" {
  let binding = named_original_binding()
  let tag = b"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let wire = client_submitted_name_row_body({ binding, authenticator: tag, }).unwrap()
  let index = "4de7f25f51dc74045566f9b43386850973e3635dae14c43775329d4c43e06ad7"
  let original : ClientJournalPhysicalRow = {
    key: index,
    body: wire,
    revision: 0L,
  }
  let inventory : ClientSubmittedNameInventory = {
    index,
    issued: 1,
    issued_revision: 1L,
    original: Some(original),
  }
  let reference = named_original_reference()
  let intent = named_original_intent()
  let saved : ClientSubmittedJournalEncoding = {
    reference,
    intent,
    run_admission: None,
    run_state_original: None,
    run_state_observation: None,
    preparation_problem: None,
  }
  for mode in 0..<6 {
    let signed : Array[Bytes] = []
    let reads : Array[(String, String)] = []
    let result = inspect_client_submitted_name_selection(
      named_original_key(),
      inventory,
      if mode == 1 {
        "sha256:" + "a".repeat(64)
      } else {
        "sha256:" + "b".repeat(64)
      },
      intent,
      bytes => {
        signed.push(bytes)
        if mode == 2 {
          Err("key unavailable")
        } else if mode == 3 {
          Ok(b"changed")
        } else {
          Ok(tag)
        }
      },
      (table, key) => {
        reads.push((table, key))
        if mode == 4 {
          Ok(None)
        } else {
          Ok(Some({ key, body: b"original intent", revision: 0L, }))
        }
      },
      _ => if mode == 5 { Err("first decoder refusal") } else { Ok(saved) },
      "lost",
    )
    let expected = client_submitted_name_authentication_input(binding, 8192).unwrap()
    assert_eq(signed, [@utf8.encode(expected)])
    assert_eq(
      reads.length(),
      if mode == 1 || mode == 2 || mode == 3 {
        0
      } else {
        1
      },
    )
    match (mode, result) {
      (0, Ok(NameRetained(actual))) =>
        assert_eq(
          client_submission_reference_record_wire(actual),
          client_submission_reference_record_wire(reference),
        )
      (1, Ok(NameConflict))
      | (2, Err("key unavailable"))
      | (3, Err("lost"))
      | (4, Ok(NameHistoryUnavailable))
      | (5, Err("first decoder refusal")) => ()
      _ => fail("unexpected original name selection")
    }
  }
}
