///|
fn answer_fixture_summary() -> String {
  "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"run_scope\",\"phase\":\"preflight\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"prepared_invocation\"},\"requirements\":[\"invocation_scope_approved\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"prepare_attempt\",\"prepareAttemptId\":\"prepare-a\",\"requestId\":\"request-a\"}}"
}

///|
fn prepare_answer_fixture(
  wire : String,
  decision? : String = "approved",
  at? : String = "2026-11-18T01:02:03.000Z",
  key? : String = "fixture-key",
) -> Result[
  @checkpoint_document.AnswerPreparation,
  @checkpoint_document.CandidateIssue,
] {
  @checkpoint_document.prepare_answer_candidate(
    wire,
    decision,
    key,
    "fixture-reviewer",
    Some("sha256:" + "5".repeat(64)),
    at,
    limits(),
  )
}

///|
test "candidate framing refuses unsupported profiles extra claims and invalid windows before signing" {
  let summary = answer_fixture_summary()
  assert_true(
    prepare_answer_fixture(
      summary.replace(
        old="\"checkpointId\":",
        new="\"preparedInvocationCid\":null,\"checkpointId\":",
      ),
    )
    is Err(UnsupportedProfile),
  )
  assert_true(
    prepare_answer_fixture(
      summary.replace(
        old="[\"invocation_scope_approved\"]",
        new="[\"invocation_scope_approved\",\"invocation_scope_approved\"]",
      ),
    )
    is Err(InvalidRequirements),
  )
  assert_true(
    prepare_answer_fixture(summary, decision="maybe")
    is Err(InvalidField("decision")),
  )
  assert_true(
    prepare_answer_fixture(summary, key="not allowed")
    is Err(InvalidField("signer")),
  )
  assert_true(
    prepare_answer_fixture(summary, at="2026-11-17T23:59:59.999Z")
    is Err(OutsideWindow),
  )
  assert_true(
    prepare_answer_fixture(summary, at="2026-11-19T00:00:00.000Z")
    is Err(OutsideWindow),
  )
  assert_true(
    prepare_answer_fixture(summary, at="2026-11-18T00:00:00.000Z") is Ok(_),
  )
  assert_true(
    prepare_answer_fixture(summary, at="2026-02-29T00:00:00.000Z")
    is Err(InvalidField("time")),
  )
  let model = "{\"checkpointCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"checkpointId\":\"checkpoint-a\",\"createdAt\":\"2026-11-18T00:00:00.000Z\",\"expiresAt\":\"2026-11-19T00:00:00.000Z\",\"humanSummary\":\"Independent fixture\",\"kind\":\"model_invocation\",\"phase\":\"preflight\",\"preparedInvocationCid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"requiredArtifact\":{\"cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"type\":\"model_invocation_scope\"},\"requirements\":[\"invocation_scope_approved\"],\"reviewProjectionCid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"subject\":{\"kind\":\"run_unit\",\"runDefinitionCid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"runId\":\"run-a\"}}"
  assert_true(
    prepare_answer_fixture(
      model.replace(
        old="\"preparedInvocationCid\":\"sha256:" + "6".repeat(64) + "\"",
        new="\"preparedInvocationCid\":null",
      ),
    )
    is Err(InvalidField("preparedInvocationCid")),
  )
}

///|
test "candidate stages preserve missing-versus-extra signature and exact output bounds" {
  let original = prepare_answer_fixture(answer_fixture_summary()).unwrap()
  assert_true(
    @checkpoint_document.prepare_answer_resolution(original, None)
    is Err(InvalidField("approval_signature")),
  )
  let rejected = prepare_answer_fixture(
    answer_fixture_summary(),
    decision="rejected",
  ).unwrap()
  assert_eq(
    @checkpoint_document.answer_candidate_approval_preimage(rejected),
    None,
  )
  assert_true(
    @checkpoint_document.prepare_answer_resolution(
      rejected,
      Some("A".repeat(86) + "=="),
    )
    is Err(InvalidField("approval_signature")),
  )
  let resolution = @checkpoint_document.prepare_answer_resolution(
    rejected,
    None,
  ).unwrap()
  for signature in ["", "AAAA", "A".repeat(85) + "B==", "A".repeat(86) + "==\n"] {
    assert_true(
      @checkpoint_document.finish_answer_candidate(resolution, signature)
      is Err(InvalidField("proof.signature")),
    )
  }
  // A representationally valid signature remains candidate DATA. Cryptographic
  // verification and original Checkpoint/authority/current binding are Host work.
  assert_true(
    @checkpoint_document.finish_answer_candidate(
      resolution,
      "A".repeat(86) + "==",
    )
    is Ok(_),
  )
  {
    let bounded = { ..limits(), max_wire_bytes: 930, }
    let prepared = @checkpoint_document.prepare_answer_candidate(
      answer_fixture_summary(),
      "approved",
      "fixture-key",
      "fixture-reviewer",
      None,
      "2026-11-18T01:02:03.000Z",
      bounded,
    ).unwrap()
    let result = match
      @checkpoint_document.prepare_answer_resolution(
        prepared,
        Some(
          "IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==",
        ),
      ) {
      Ok(value) =>
        @checkpoint_document.finish_answer_candidate(
          value, "DBH/r1IsSbVoJ6s7/4hvGrPdophBqYNN5KnExxpVQOdo3XsMfYHckUFzo7/jXeZPSGwPhTT0Sgoke9rOge0CDQ==",
        )
      Err(issue) => Err(issue)
    }
    assert_true(result is Ok(_))
  }
  let bounded = { ..limits(), max_wire_bytes: 929, }
  let prepared = @checkpoint_document.prepare_answer_candidate(
    answer_fixture_summary(),
    "approved",
    "fixture-key",
    "fixture-reviewer",
    None,
    "2026-11-18T01:02:03.000Z",
    bounded,
  ).unwrap()
  let result = match
    @checkpoint_document.prepare_answer_resolution(
      prepared,
      Some(
        "IH7v4Jm1r2rAfaiYNtsS/Nu4xVd4JYUa6+I478jN+/VnbQKZm3E2qjqfbMUQyCFWTt3GT5o3wBzENhsLe60cDg==",
      ),
    ) {
    Ok(value) =>
      @checkpoint_document.finish_answer_candidate(
        value, "DBH/r1IsSbVoJ6s7/4hvGrPdophBqYNN5KnExxpVQOdo3XsMfYHckUFzo7/jXeZPSGwPhTT0Sgoke9rOge0CDQ==",
      )
    Err(issue) => Err(issue)
  }
  assert_true(result is Err(_))
}
