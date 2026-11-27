///|
test "submitted intent preserves source values and data keys before checking" {
  let original = "{\"kind\":\"aql\",\"input\":{\"text\":\"SELECT 'e\u{0301}\\r\\n'\",\"format\":\"aql-text\"},\"parameters\":{\"e\u{0301}\":\"line\\r\\n\",\"é\":\"line\\n\"}}"
  let admitted = prepare_client_submitted_intent(original, 4096, 128, 16).unwrap()
  assert_eq(
    client_submitted_intent_wire(admitted),
    "{\"input\":{\"format\":\"aql-text\",\"text\":\"SELECT 'e\u{0301}\\r\\n'\"},\"kind\":\"aql\",\"parameters\":{\"e\u{0301}\":\"line\\r\\n\",\"é\":\"line\\n\"}}",
  )
  let composed = prepare_client_submitted_intent(
    original.replace(old="SELECT 'e\u{0301}", new="SELECT 'é"),
    4096,
    128,
    16,
  ).unwrap()
  assert_true(
    client_submitted_intent_cid(admitted) !=
    client_submitted_intent_cid(composed),
  )
  let newline = prepare_client_submitted_intent(
    original.replace(old="line\\r\\n", new="line\\n"),
    4096,
    128,
    16,
  ).unwrap()
  assert_true(
    client_submitted_intent_cid(admitted) !=
    client_submitted_intent_cid(newline),
  )
}

///|
test "submitted intent distinguishes storage admission limits from malformed envelopes" {
  let original = "{\"kind\":\"program\",\"input\":{},\"parameters\":null}"
  assert_true(
    prepare_client_submitted_intent(original, 8, 128, 16) is Err(Limit),
  )
  assert_true(
    prepare_client_submitted_intent(original, 4096, 1, 16) is Err(Limit),
  )
  assert_true(
    prepare_client_submitted_intent(original, 4096, 128, 1) is Err(Limit),
  )
  assert_true(
    prepare_client_submitted_intent(original, 0, 128, 16) is Err(InvalidLimits),
  )
  for
    malformed in [
      "null", "{\"kind\":\"program\",\"input\":{}}", "{\"kind\":\"other\",\"input\":{},\"parameters\":null}",
      "{\"kind\":\"program\",\"input\":{},\"parameters\":[],\"extra\":1}",
    ] {
    assert_true(
      prepare_client_submitted_intent(malformed, 4096, 128, 16)
      is Err(InvalidEnvelope),
    )
  }
}

///|
test "submitted intent identity uses an independent versioned preimage" {
  let original = "{\"kind\":\"program\",\"input\":{},\"parameters\":null}"
  let admitted = prepare_client_submitted_intent(original, 4096, 128, 16).unwrap()
  // Independently hashed canonical preimage, not a product-generated fixture.
  assert_eq(
    client_submitted_intent_cid(admitted),
    "sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44",
  )
}

///|
test "submitted intent binds the optional first Effect stop without changing old identity" {
  let wire = "{\"kind\":\"program\",\"input\":{},\"parameters\":null,\"stopBefore\":\"commit\"}"
  let admitted = prepare_client_submitted_intent(wire, 4096, 128, 16).unwrap()
  assert_true(client_submitted_intent_requests_commit_stop(admitted))
  assert_false(
    client_submitted_intent_requests_commit_stop(
      prepare_client_submitted_intent(
        "{\"kind\":\"program\",\"input\":{},\"parameters\":null}", 4096, 128, 16,
      ).unwrap(),
    ),
  )
  assert_eq(
    client_submitted_intent_wire(admitted),
    "{\"input\":{},\"kind\":\"program\",\"parameters\":null,\"stopBefore\":\"commit\"}",
  )
  // Independent canonical preimage, including the retained user restriction.
  assert_eq(
    client_submitted_intent_cid(admitted),
    "sha256:4f9c3ae04162c1dba9cdc083c925ac8898e23d8f1b9da298ced13d3d62886d07",
  )
  for invalid in ["null", "false", "1", "\"\"", "\"prepare\"", "{}"] {
    assert_true(
      prepare_client_submitted_intent(
        wire.replace(old="\"commit\"", new=invalid),
        4096,
        128,
        16,
      )
      is Err(InvalidEnvelope),
    )
  }
  assert_true(
    prepare_client_submitted_intent(
      wire.replace(old="\"stopBefore\"", new="\"other\""),
      4096,
      128,
      16,
    )
    is Err(InvalidEnvelope),
  )
}

///|
test "submitted intent transitions preserve the acceptance boundary" {
  for next in ["preparing", "held", "ready", "preparation_failed"] {
    assert_true(client_submitted_intent_transition("preparing", next))
  }
  for before in ["preparing", "held", "ready", "preparation_failed"] {
    assert_false(client_submitted_intent_transition(before, "not_accepted"))
  }
  for terminal in ["ready", "not_accepted", "preparation_failed"] {
    assert_true(client_submitted_intent_transition(terminal, terminal))
    assert_false(client_submitted_intent_transition(terminal, "preparing"))
    assert_false(client_submitted_intent_transition(terminal, "held"))
  }
  assert_false(client_submitted_intent_transition("unknown", "ready"))
}

///|
test "submitted read-only choice is true-only original data with absent compatibility" {
  let old = "{\"kind\":\"program\",\"input\":{},\"parameters\":null}"
  let original = prepare_client_submitted_intent(old, 4096, 128, 16).unwrap()
  assert_false(client_submitted_intent_requests_read_only(original))
  assert_eq(
    client_submitted_intent_cid(original),
    "sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44",
  )
  let wire = "{\"kind\":\"program\",\"input\":{},\"parameters\":null,\"readOnly\":true}"
  let admitted = prepare_client_submitted_intent(wire, 4096, 128, 16).unwrap()
  assert_true(client_submitted_intent_requests_read_only(admitted))
  assert_false(client_submitted_intent_requests_commit_stop(admitted))
  assert_eq(
    client_submitted_intent_wire(admitted),
    "{\"input\":{},\"kind\":\"program\",\"parameters\":null,\"readOnly\":true}",
  )
  assert_true(
    client_submitted_intent_cid(original) !=
    client_submitted_intent_cid(admitted),
  )
  // Independently hashed literal canonical preimage; never emitted by the
  // product under test when constructing the expected identity.
  assert_eq(
    client_submitted_intent_cid(admitted),
    "sha256:2b7e2e13949315aa9877b748f60fd0b922f8271d663808af2fabd61c12745719",
  )
  let both = prepare_client_submitted_intent(
    wire.replace(old="true}", new="true,\"stopBefore\":\"commit\"}"),
    4096,
    128,
    16,
  ).unwrap()
  assert_true(client_submitted_intent_requests_read_only(both))
  assert_true(client_submitted_intent_requests_commit_stop(both))
  assert_eq(
    client_submitted_intent_cid(both),
    "sha256:6fc7f2fe17d41a4046ce88ef910a9ecc5882cd2d9a9306a7bffdf2e33a8682e8",
  )
  for invalid in ["false", "null", "0", "\"true\"", "{}", "[]"] {
    assert_true(
      prepare_client_submitted_intent(
        wire.replace(old="true", new=invalid),
        4096,
        128,
        16,
      )
      is Err(InvalidEnvelope),
    )
  }
  for field in ["readonly", "read_only", "queryOnly"] {
    assert_true(
      prepare_client_submitted_intent(
        wire.replace(old="readOnly", new=field),
        4096,
        128,
        16,
      )
      is Err(InvalidEnvelope),
    )
  }
}

///|
test "submitted Debug profile preserves every original continuation choice and identity" {
  // Independent canonical preimages include the same closed original choices.
  let cases = [
    (
      "{\"input\":{},\"kind\":\"program\",\"parameters\":null}", "sha256:5ad281d9145e26cfb0bf5b7b0fa37c11cb2b065687350ae53a36f714bca0fe44",
    ),
    (
      "{\"input\":{},\"kind\":\"program\",\"parameters\":null,\"stopBefore\":\"commit\"}",
      "sha256:4f9c3ae04162c1dba9cdc083c925ac8898e23d8f1b9da298ced13d3d62886d07",
    ),
    (
      "{\"input\":{},\"kind\":\"program\",\"parameters\":null,\"readOnly\":true}",
      "sha256:2b7e2e13949315aa9877b748f60fd0b922f8271d663808af2fabd61c12745719",
    ),
    (
      "{\"input\":{},\"kind\":\"program\",\"parameters\":null,\"readOnly\":true,\"stopBefore\":\"commit\"}",
      "sha256:6fc7f2fe17d41a4046ce88ef910a9ecc5882cd2d9a9306a7bffdf2e33a8682e8",
    ),
    (
      "{\"executionProfile\":\"debug\",\"input\":{},\"kind\":\"program\",\"parameters\":null}",
      "sha256:ee4ef9588ad0ec98796f9ac103e26564ad13cb1c31a787795b5df14f484bf573",
    ),
    (
      "{\"executionProfile\":\"debug\",\"input\":{},\"kind\":\"program\",\"parameters\":null,\"stopBefore\":\"commit\"}",
      "sha256:92a88cc96424fc036b9b940f34c44896203ddb2e609168af059f552688c452d8",
    ),
    (
      "{\"executionProfile\":\"debug\",\"input\":{},\"kind\":\"program\",\"parameters\":null,\"readOnly\":true}",
      "sha256:536e441bf1aaa6d43e61eedb01a8c044125b1d510112be9870f54a85712f80fc",
    ),
    (
      "{\"executionProfile\":\"debug\",\"input\":{},\"kind\":\"program\",\"parameters\":null,\"readOnly\":true,\"stopBefore\":\"commit\"}",
      "sha256:5870db08d088ad47d0d434982a7ae6f2b7e0724cf3406e8f2dbd125724c2c4d9",
    ),
  ]
  for index in 0..<cases.length() {
    let (wire, cid) = cases[index]
    let original = prepare_client_submitted_intent(wire, 4096, 128, 16).unwrap()
    assert_eq(client_submitted_intent_wire(original), wire)
    assert_eq(client_submitted_intent_cid(original), cid)
    assert_eq(
      client_submitted_intent_requests_commit_stop(original),
      (index & 1) != 0,
    )
    assert_eq(
      client_submitted_intent_requests_read_only(original),
      (index & 2) != 0,
    )
    assert_eq(
      client_submitted_intent_execution_profile(original),
      if (index & 4) != 0 {
        Debug
      } else {
        Normal
      },
    )
    let changed = prepare_client_submitted_intent(
      cases[if index < 4 { index + 4 } else { index - 4 }].0,
      4096,
      128,
      16,
    ).unwrap()
    for phase in ["preparing", "held", "ready", "preparation_failed"] {
      assert_true(
        observe_client_submitted_intent(original, Some((changed, phase)))
        is Ok(SubmissionConflict),
      )
    }
  }
  for choice in ["null", "false", "1", "\"normal\"", "\"\"", "{}", "[]"] {
    let wire = "{\"kind\":\"program\",\"input\":{},\"parameters\":null,\"executionProfile\":" +
      choice +
      "}"
    assert_true(
      prepare_client_submitted_intent(wire, 4096, 128, 16)
      is Err(InvalidEnvelope),
    )
  }
}

///|
test "submitted Debug marks bind the original map and ordered step choices" {
  let a = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let b = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let c = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  fn intent(map : String, first : String, second : String) -> String {
    "{\"breakpointSelection\":{\"before_step_ids\":[\"\{first}\",\"\{second}\"],\"logical_map_cid\":\"\{map}\"},\"executionProfile\":\"debug\",\"input\":{},\"kind\":\"program\",\"parameters\":null}"
  }
  let wire = intent(c, a, b)
  let original = prepare_client_submitted_intent(wire, 4096, 128, 16).unwrap()
  assert_eq(client_submitted_intent_entry_breakpoint_count(original), 2)
  assert_true(client_submitted_intent_breakpoint_map_matches(original, c))
  assert_false(client_submitted_intent_breakpoint_map_matches(original, a))
  assert_eq(client_submitted_intent_breakpoint_step(original, 0), Some(a))
  assert_eq(client_submitted_intent_breakpoint_step(original, 1), Some(b))
  assert_eq(client_submitted_intent_breakpoint_step(original, 2), None)
  let matches = fn(map, steps : Array[String]) {
    client_submitted_intent_breakpoint_selection_matches(
      original, map, ReadOnlyArray::from_array(steps),
    )
  }
  assert_true(matches(c, [a, b]))
  assert_false(matches(c, [b, a]))
  assert_false(matches(c, [a]))
  assert_false(matches(b, [a, b]))
  assert_eq(client_submitted_intent_wire(original), wire)
  assert_eq(
    client_submitted_intent_cid(original),
    "sha256:d56f7bfdc678d4d6c117317b734371ffe2cc10e4f3d7443ec63984c39b09dab2",
  )
  for change in [intent(c, b, a), intent(b, a, b)] {
    let changed = prepare_client_submitted_intent(change, 4096, 128, 16).unwrap()
    assert_true(
      client_submitted_intent_cid(changed) != client_submitted_intent_cid(original),
    )
  }
  for invalid in [
    intent(c, a, a),
    intent(c, a, "short"),
    intent("unbound", a, b),
    wire.replace(old="\"executionProfile\":\"debug\",", new=""),
    wire.replace(old="\"logical_map_cid\"",
      new="\"extra\":true,\"logical_map_cid\""),
  ] {
    assert_true(
      prepare_client_submitted_intent(invalid, 4096, 128, 16)
        is Err(InvalidEnvelope),
    )
  }
}
