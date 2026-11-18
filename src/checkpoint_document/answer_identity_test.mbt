///|
test "candidate original identity domains refuse normalization while display DATA stays unsigned" {
  let summary = answer_fixture_summary()
  for
    (original, field) in [
      ("checkpoint-a", "checkpointId"),
      ("prepare-a", "prepareAttemptId"),
      ("request-a", "requestId"),
    ] {
    assert_true(
      match
        prepare_answer_fixture(summary.replace(old=original, new="e\u{0301}")) {
        Err(InvalidField(actual)) => actual == field
        _ => false
      },
      msg=field,
    )
  }
  let run = summary
    .replace(old="\"kind\":\"run_scope\"", new="\"kind\":\"read_access\"")
    .replace(
      old="\"type\":\"prepared_invocation\"",
      new="\"type\":\"read_scope\"",
    )
    .replace(
      old="\"kind\":\"prepare_attempt\",\"prepareAttemptId\":\"prepare-a\",\"requestId\":\"request-a\"",
      new="\"kind\":\"run_unit\",\"runId\":\"e\u{0301}\",\"runDefinitionCid\":\"sha256:" +
        "4".repeat(64) +
        "\"",
    )
  assert_true(prepare_answer_fixture(run) is Err(InvalidField("runId")))
  let displayed = prepare_answer_fixture(
    summary.replace(old="Independent fixture", new="e\\u0301\\r\\n"),
  ).unwrap()
  // This independent corpus preimage excludes display text. Neither data
  // preservation nor a representational signature issues a sealed original.
  assert_eq(
    answer_candidate_approval_preimage(displayed),
    Some(
      "sha256:c9e85bacb9f463bc44d5f72817045fa25343e4aa42ae2128f49003d5dd41cb80",
    ),
  )
}
