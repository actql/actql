///|
fn summary_identity_domains() -> Array[(String, String, String)] {
  let preparation = answer_fixture_summary()
  let run = preparation
    .replace(old="\"kind\":\"run_scope\"", new="\"kind\":\"read_access\"")
    .replace(
      old="\"type\":\"prepared_invocation\"",
      new="\"type\":\"read_scope\"",
    )
    .replace(
      old="\"kind\":\"prepare_attempt\",\"prepareAttemptId\":\"prepare-a\",\"requestId\":\"request-a\"",
      new="\"kind\":\"run_unit\",\"runId\":\"run-a\",\"runDefinitionCid\":\"sha256:" +
        "4".repeat(64) +
        "\"",
    )
  [
    (preparation, "checkpoint-a", "checkpointId"),
    (preparation, "prepare-a", "prepareAttemptId"),
    (preparation, "request-a", "requestId"),
    (run, "run-a", "runId"),
  ]
}

///|
test "Summary identities use the existing 256 scalar boundary without UTF16 narrowing" {
  for (summary, original, field) in summary_identity_domains() {
    for scalar in ["x", "😀"] {
      assert_true(
        prepare_answer_fixture(
          summary.replace(old=original, new=scalar.repeat(256)),
        )
        is Ok(_),
        msg=field,
      )
      assert_true(
        match
          prepare_answer_fixture(
            summary.replace(old=original, new=scalar.repeat(257)),
          ) {
          Err(InvalidField(actual)) => actual == field
          _ => false
        },
        msg=field,
      )
    }
  }
}

///|
test "Summary control identities reject all C0 and DEL without changing other text domains" {
  // These are JSON escapes in the fixture wire, not malformed raw JSON input.
  let controls = [
    "\\u0000", "\\u0001", "\\u0002", "\\u0003", "\\u0004", "\\u0005", "\\u0006",
    "\\u0007", "\\u0008", "\\u0009", "\\u000a", "\\u000b", "\\u000c", "\\u000d",
    "\\u000e", "\\u000f", "\\u0010", "\\u0011", "\\u0012", "\\u0013", "\\u0014",
    "\\u0015", "\\u0016", "\\u0017", "\\u0018", "\\u0019", "\\u001a", "\\u001b",
    "\\u001c", "\\u001d", "\\u001e", "\\u001f", "\\u007f",
  ]
  for (summary, original, field) in summary_identity_domains() {
    for escaped in controls {
      assert_true(
        match
          prepare_answer_fixture(
            summary.replace(old=original, new="a" + escaped + "b"),
          ) {
          Err(InvalidField(actual)) => actual == field
          _ => false
        },
        msg=field + ":" + escaped,
      )
    }
  }
  assert_true(
    prepare_answer_fixture(
      answer_fixture_summary().replace(old="checkpoint-a", new=" id-é "),
    )
    is Ok(_),
  )
}

///|
test "Human Summary keeps its 1024 scalar DATA boundary and unchanged independent preimage" {
  let summary = answer_fixture_summary()
  for
    display in [
      "",
      "x".repeat(1024),
      "😀".repeat(1024),
      "e\u{0301}".repeat(512),
      "\\r\\n".repeat(512),
      "\\u0000",
    ] {
    let prepared = prepare_answer_fixture(
      summary.replace(old="Independent fixture", new=display),
    ).unwrap()
    assert_eq(
      answer_candidate_approval_preimage(prepared),
      Some(
        "sha256:c9e85bacb9f463bc44d5f72817045fa25343e4aa42ae2128f49003d5dd41cb80",
      ),
    )
  }
  for
    display in [
      "x".repeat(1025),
      "😀".repeat(1025),
      "e\u{0301}".repeat(512) + "x",
      "\\r\\n".repeat(512) + "x",
    ] {
    assert_true(
      prepare_answer_fixture(
        summary.replace(old="Independent fixture", new=display),
      )
      is Err(InvalidField("humanSummary")),
    )
  }
}
