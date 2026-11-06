// Independently authored Owner shape cases; no runtime HEAD/history lookup.

///|
fn owner_observation_fixture() -> String {
  "{\"ref\":{\"namespaceId\":\"original\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"consistency\":\"non_atomic\",\"ordering\":\"owner_local\",\"owners\":[{\"owner\":\"run\",\"ownerRef\":{\"kind\":\"run\",\"scopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"streamCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"kind\":\"observed\",\"snapshot\":{\"value\":{\"version\":\"actql-run-state/0.1\",\"run_id\":\"original\",\"status\":\"needs_reconciliation\",\"revision\":0,\"updated_at\":\"2026-10-09T00:00:00.000Z\",\"next_action\":{\"kind\":\"reconcile\",\"effects\":[\"save\"]},\"result_available\":false,\"result_availability\":{}}},\"history\":{\"kind\":\"not_provided\"}},{\"owner\":\"effect\",\"ownerRef\":{\"kind\":\"effect\",\"scopeCid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"streamCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"},\"kind\":\"observed\",\"snapshot\":{\"revision\":2,\"value\":{\"state\":\"dispatching\"}},\"history\":{\"kind\":\"cursor_expired\"}}],\"revisionVector\":[{\"owner\":{\"kind\":\"run\",\"scopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"streamCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"snapshotCid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\"},{\"owner\":{\"kind\":\"effect\",\"scopeCid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"streamCid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"},\"snapshotCid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"}]}"
}

///|
fn owner_observation_parse(text : String) -> Json raise {
  @json.parse(text) catch {
    _ => fail("InvalidIndependentOwnerFixture")
  }
}

///|
test "Native Owner observation: mixed retained and current-only" {
  assert_true(
    wire_owner_observations_shape(
      owner_observation_parse(owner_observation_fixture()),
    ),
  )
}

///|
test "Native Owner observation: distinct history problems" {
  for
    problem in [
      "not_provided", "retention_expired", "history_unrecoverable", "cursor_mismatch",
      "acquisition_failed", "limit_exceeded",
    ] {
    let text = owner_observation_fixture().replace(
      old="cursor_expired",
      new=problem,
    )
    assert_true(wire_owner_observations_shape(owner_observation_parse(text)))
  }
}

///|
test "Native Owner observation: false atomic and global revision" {
  assert_true(
    !wire_owner_observations_shape(
      owner_observation_parse(
        owner_observation_fixture().replace(old="non_atomic", new="atomic"),
      ),
    ),
  )
  assert_true(
    !wire_owner_observations_shape(
      owner_observation_parse(
        owner_observation_fixture().replace(
          old="\"ordering\":\"owner_local\"",
          new="\"ordering\":\"owner_local\",\"revision\":7",
        ),
      ),
    ),
  )
}

///|
test "Native Owner observation: exact timestamp and empty availability" {
  assert_true(
    !wire_owner_observations_shape(
      owner_observation_parse(
        owner_observation_fixture().replace(
          old="2026-10-09T00:00:00.000Z",
          new="2026/10/09T00:00:00.000Z",
        ),
      ),
    ),
  )
  assert_true(
    !wire_owner_observations_shape(
      owner_observation_parse(
        owner_observation_fixture().replace(
          old="\"result_available\":false",
          new="\"result_available\":true",
        ),
      ),
    ),
  )
}

///|
test "Native Owner observation: error code is a checked contract" {
  let valid = owner_observation_fixture().replace(
    old="\"result_available\":false",
    new="\"terminal_error\":{\"code\":\"ACTQL_E_TEST\",\"message\":\"bounded failure\"},\"result_available\":false",
  )
  assert_true(wire_owner_observations_shape(owner_observation_parse(valid)))
  assert_true(
    !wire_owner_observations_shape(
      owner_observation_parse(
        valid.replace(old="ACTQL_E_TEST", new="ACTQL_E_private"),
      ),
    ),
  )
}
