///|
fn original_continuation_test_checkpoint(
  plain : Bytes,
) -> @checkpoint.SealedCheckpoint {
  @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "original-review",
      continuation_state_cid: "sha256:" + @sha.hex(plain),
      subject: @checkpoint.RunUnit(
        run_id="original-run",
        unit_id="original-unit",
        run_definition_cid="sha256:" + "a".repeat(64),
      ),
      phase: @checkpoint.Commit,
      kind: @checkpoint.EffectSet,
      required_artifact_cid: "sha256:" + "b".repeat(64),
      review_projection_cid: "sha256:" + "c".repeat(64),
      requirements: [@checkpoint.EffectScopeApproved],
      reason_code: "effect_review",
      human_summary: "Original review",
      created_at: "2026-10-11T00:00:00.000Z",
      expires_at: "2026-10-11T01:00:00.000Z",
    },
    { max_wire_bytes: 4096, max_nodes: 100, max_depth: 16, },
  ).unwrap()
}

///|
test "original Checkpoint continuation preserves exact values and line endings" {
  let wire = "{\"value\":\"e\u0301\"}\r\n"
  let plain = @utf8.encode(wire)
  let checkpoint = original_continuation_test_checkpoint(plain)
  assert_eq(
    original_effect_checkpoint_continuation(checkpoint, plain, 4096L).unwrap(),
    wire,
  )
  assert_eq(
    checkpoint.checkpoint.subject,
    @checkpoint.RunUnit(
      run_id="original-run",
      unit_id="original-unit",
      run_definition_cid="sha256:" + "a".repeat(64),
    ),
  )
}

///|
test "original Checkpoint continuation rejects substituted or normalized bytes" {
  let plain = @utf8.encode("e\u0301\r\n")
  let checkpoint = original_continuation_test_checkpoint(plain)
  for
    candidate in [
      @utf8.encode("\u00e9\r\n"),
      @utf8.encode("e\u0301\n"),
      @utf8.encode("foreign"),
    ] {
    assert_true(
      original_effect_checkpoint_continuation(checkpoint, candidate, 4096L)
      is Err(DigestMismatch),
    )
  }
}

///|
test "original Checkpoint continuation rejects a foreign original digest" {
  let original = @utf8.encode("original")
  let foreign = original_continuation_test_checkpoint(@utf8.encode("foreign"))
  assert_true(
    original_effect_checkpoint_continuation(foreign, original, 4096L)
    is Err(DigestMismatch),
  )
}

///|
test "original Checkpoint continuation keeps the existing byte bound" {
  let plain = @utf8.encode("original")
  let checkpoint = original_continuation_test_checkpoint(plain)
  for limit in [0L, -1L, plain.length().to_int64() - 1L] {
    assert_true(
      original_effect_checkpoint_continuation(checkpoint, plain, limit)
      is Err(InvalidConfiguration),
    )
  }
  assert_true(
    original_effect_checkpoint_continuation(
      checkpoint,
      plain,
      plain.length().to_int64(),
    )
    is Ok(_),
  )
}

///|
test "original Checkpoint continuation rejects invalid UTF8 even with matching digest" {
  let plain = Bytes::from_array([0xff])
  let checkpoint = original_continuation_test_checkpoint(plain)
  assert_true(
    original_effect_checkpoint_continuation(checkpoint, plain, 4096L)
    is Err(StateCollision),
  )
}
