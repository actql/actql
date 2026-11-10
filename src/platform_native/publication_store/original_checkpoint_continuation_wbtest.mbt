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

///|
test "Native cold Checkpoint restoration observes then bounds the exact encrypted pair" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture("checkpoint-cold-pair", 65536L)
    is Some((store, authority, library, root)) else {
    abort("Native cold Checkpoint test requires physical Crypto and SQLite")
  }
  let crypto = @signature.load_library(path).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let wire = "{\"original\":\"e\u0301\"}\r\n"
  let checkpoint = original_continuation_test_checkpoint(@utf8.encode(wire))
  let saved = store
    .prepare_effect_checkpoint_custody(checkpoint, wire, authority, crypto, key)
    .unwrap()
  saved.persist().unwrap()
  assert_eq(saved.confirm().unwrap().1, wire)
  let original_usage = store.capacity_usage().unwrap()
  store.close().unwrap() |> ignore
  let reopened = open_store(library, root, authority, 65536L, 8L, 65536L).unwrap()
  let (extent, layout) = reopened
    .effect_checkpoint_restore_construction(checkpoint)
    .unwrap()
  assert_eq(extent.revision, 0L)
  assert_true(extent.body_bytes > @utf8.encode(wire).length().to_int64())
  assert_true(
    @execution.preparation_representation_cost(layout.retained).unwrap() > 0L,
  )
  assert_true(
    @execution.preparation_representation_cost(layout.workspace).unwrap() > 0L,
  )
  // A changed extent cannot be used to copy/decrypt under the old quote.
  assert_true(
    reopened.restore_confirmed_effect_checkpoint_custody(
      checkpoint,
      authority,
      crypto,
      key,
      continuation_extent=Some({ ..extent, body_bytes: extent.body_bytes + 1L, }),
    )
    is Err(Database(_)),
  )
  let restored = reopened
    .restore_confirmed_effect_checkpoint_custody(
      checkpoint,
      authority,
      crypto,
      key,
      continuation_extent=Some(extent),
    )
    .unwrap()
  assert_eq(restored.confirm().unwrap().1, wire)
  assert_eq(
    reopened.capacity_usage().unwrap().reserved_bytes,
    original_usage.reserved_bytes,
  )
  assert_eq(
    reopened.capacity_usage().unwrap().reserved_objects,
    original_usage.reserved_objects,
  )
  // These are read aliases: retirement is still the original explicit Store
  // cleanup operation, and the terminal pair cannot be revived by cold read.
  assert_true(restored.retry_cleanup().unwrap())
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(
    reopened.effect_checkpoint_restore_construction(checkpoint)
    is Err(RecoveryRequired),
  )
  assert_true(
    reopened.restore_confirmed_effect_checkpoint_custody(
      checkpoint,
      authority,
      crypto,
      key,
      continuation_extent=Some(extent),
    )
    is Err(_),
  )
  reopened.close().unwrap() |> ignore
}

///|
test "Native cold Checkpoint preserves the admitted one MiB plaintext boundary" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) &&
    native_payload_fixture(
      "checkpoint-cold-envelope-boundary",
      4194304L,
      max_record_bytes=2097152L,
    )
    is Some((store, authority, library, root)) else {
    abort("Native cold Checkpoint boundary requires physical Crypto and SQLite")
  }
  let crypto = @signature.load_library(path).unwrap()
  let key = Bytes::makei(32, i => i.to_byte())
  let wire = "a".repeat(1048576)
  let checkpoint = original_continuation_test_checkpoint(@utf8.encode(wire))
  let saved = store
    .prepare_effect_checkpoint_custody(checkpoint, wire, authority, crypto, key)
    .unwrap()
  saved.persist().unwrap()
  store.close().unwrap() |> ignore
  let reopened = open_store(library, root, authority, 4194304L, 8L, 2097152L).unwrap()
  let (extent, layout) = reopened
    .effect_checkpoint_restore_construction(checkpoint)
    .unwrap()
  assert_eq(extent.body_bytes, 1398232L)
  assert_eq(layout.envelope_bytes, 1398232)
  let restored = reopened
    .restore_confirmed_effect_checkpoint_custody(
      checkpoint,
      authority,
      crypto,
      key,
      continuation_extent=Some(extent),
    )
    .unwrap()
  assert_eq(restored.confirm().unwrap().1, wire)
  assert_true(restored.retry_cleanup().unwrap())
  assert_eq(reopened.capacity_usage().unwrap().reserved_bytes, 0L)
  reopened.close().unwrap() |> ignore
}
