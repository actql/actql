///|
// New facade consumption of the real pure writer, not a repeated C writer
// suite or proof of the Host's no-grant/stopping/current/publication premises.
test "original Checkpoint cancelled DATA projects same stored review within exact bound" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 65536,
    max_depth: 64,
  }
  let original = @checkpoint.seal_checkpoint(body, limits).unwrap()
  let expected = "{\"next_action\":{\"kind\":\"none\"},\"result_availability\":{\"published\":{\"observed_at\":\"2026-10-09T03:00:00.000Z\",\"reason\":\"not_published\",\"state\":\"unavailable\"}},\"result_available\":false,\"run_id\":\"original-run\",\"status\":\"cancelled\",\"updated_at\":\"2026-10-09T03:00:00.000Z\",\"version\":\"actql-run-state/0.1\"}"
  let wire = client_effect_review_checkpoint_cancelled_state(
    original,
    allowed,
    definition,
    original.wire,
    "2026-10-09T03:00:00.000Z",
    ["published"],
    limits,
  ).unwrap()
  assert_eq(wire, expected)
  let bytes = @utf8.encode(expected).length()
  assert_eq(
    client_effect_review_checkpoint_cancelled_state(
      original,
      allowed,
      definition,
      original.wire,
      "2026-10-09T03:00:00.000Z",
      ["published"],
      { ..limits, max_wire_bytes: bytes, },
    ).unwrap(),
    expected,
  )
  assert_true(
    client_effect_review_checkpoint_cancelled_state(
      original,
      allowed,
      definition,
      original.wire,
      "2026-10-09T03:00:00.000Z",
      ["published"],
      { ..limits, max_wire_bytes: bytes - 1, },
    )
    is Err(RunState(@publication.Encoding)),
  )
}

///|
test "original Checkpoint cancelled DATA refuses foreign roots stored wire and invalid writer inputs" {
  let (allowed, definition, body) = checkpoint_binding_fixture()
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 1048576,
    max_nodes: 65536,
    max_depth: 64,
  }
  let original = @checkpoint.seal_checkpoint(body, limits).unwrap()
  assert_true(
    client_effect_review_checkpoint_cancelled_state(
      original,
      allowed,
      definition,
      original.wire + " ",
      "invalid",
      [],
      limits,
    )
    is Err(Checkpoint(@checkpoint.PersistedWireMismatch)),
  )
  let other = issue_client_effect_run_definition(
    allowed, "scope", "other-run", "2026-10-09T00:00:00.000Z", "2026-10-10T00:00:00.000Z",
  ).unwrap()
  assert_true(
    client_effect_review_checkpoint_cancelled_state(
      original,
      allowed,
      other,
      original.wire,
      "2026-10-09T03:00:00.000Z",
      [],
      limits,
    )
    is Err(Binding(ForeignSubject)),
  )
  assert_true(
    client_effect_review_checkpoint_cancelled_state(
      original,
      allowed,
      definition,
      original.wire,
      "invalid",
      [],
      limits,
    )
    is Err(RunState(@publication.InvalidObservationTime("run"))),
  )
  assert_true(
    client_effect_review_checkpoint_cancelled_state(
      original,
      allowed,
      definition,
      original.wire,
      "2026-10-09T03:00:00.000Z",
      ["same", "same"],
      limits,
    )
    is Err(RunState(@publication.DuplicateDeclaredResult("same"))),
  )
}
