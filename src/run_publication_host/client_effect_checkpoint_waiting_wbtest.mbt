///|
test "original Checkpoint stored bytes preserve waiting identity and action" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 65536,
    max_depth: 64,
  }
  let sealed_checkpoint = @checkpoint.seal_checkpoint(body, limits).unwrap()
  let original = admit_client_effect_review_checkpoint_binding(
    allowed,
    definition,
    sealed_checkpoint.wire,
    limits,
  ).unwrap()
  let wire = client_effect_review_checkpoint_waiting_state(
    original,
    original.wire,
    "2026-10-09T03:00:00.000Z",
    [],
    limits,
  ).unwrap()
  assert_eq(
    wire,
    "{\"checkpoint\":{\"checkpoint_cid\":\"" +
    original.checkpoint_cid +
    "\",\"checkpoint_id\":\"original-review\",\"kind\":\"effect_set\"},\"next_action\":{\"checkpoint_id\":\"original-review\",\"kind\":\"resolve_checkpoint\"},\"result_availability\":{},\"result_available\":false,\"run_id\":\"original-run\",\"status\":\"waiting_checkpoint\",\"updated_at\":\"2026-10-09T03:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}",
  )
}

///|
test "original Checkpoint waiting refuses changed stored bytes before projection" {
  let (_, _, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 65536,
    max_depth: 64,
  }
  let original = @checkpoint.seal_checkpoint(body, limits).unwrap()
  assert_true(
    client_effect_review_checkpoint_waiting_state(
      original,
      original.wire + " ",
      "invalid-time",
      [],
      limits,
    )
    is Err(Checkpoint(@checkpoint.PersistedWireMismatch)),
  )
}

///|
test "original Checkpoint waiting retains writer time results and full extent limits" {
  let (_, _, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 65536,
    max_depth: 64,
  }
  let original = @checkpoint.seal_checkpoint(body, limits).unwrap()
  assert_true(
    client_effect_review_checkpoint_waiting_state(
      original,
      original.wire,
      "invalid-time",
      [],
      limits,
    )
    is Err(RunState(@checkpoint.RunStateInvalidField("updated_at"))),
  )
  assert_true(
    client_effect_review_checkpoint_waiting_state(
      original,
      original.wire,
      "2026-10-09T03:00:00.000Z",
      ["same", "same"],
      limits,
    )
    is Err(
      RunState(
        @checkpoint.RunStateRelation(
          @publication.DuplicateDeclaredResult("same")
        )
      )
    ),
  )
  assert_true(
    client_effect_review_checkpoint_waiting_state(
      original,
      original.wire,
      "2026-10-09T03:00:00.000Z",
      [],
      { ..limits, max_wire_bytes: 64, },
    )
    is Err(RunState(@checkpoint.RunStateEncoding)),
  )
}
