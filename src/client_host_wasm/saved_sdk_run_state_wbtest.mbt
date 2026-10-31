///|
// Independently canonicalized ASCII fixture bodies and self-CIDs. These are
// metadata-only contracts, not a physical Store, permission or Run execution.
let saved_sdk_status_definition : String = [
  "{\"authorization_context_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"created_at\":\"2026-10-21T00:00:00.000Z\",\"input_artifact_set_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"invocation_template_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"run_definition_cid\":\"sha256:0a872d347ec29b6eb772d3d8421fe4e0daa6f1f1526d3762349461d374335945\",\"run_id\":\"saved-manifest-fixture\",\"scope_id\":\"saved-manifest-fixture\",\"valid_until\":\"2026-10-22T00:00:00.000Z\",\"version\":\"actql-run-definition/0.1\"}",
].join("")

///|
let saved_sdk_status_manifest : String = [
  "{\"invocation_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"result_manifest_cid\":\"sha256:7950da50f0d52d4a5ca2203741bb2af7076083e71797eb13bcbea904edfa0fb0\",\"results\":{\"answer\":{\"actual_completeness\":\"complete\",\"actual_row_count\":1,\"effective_data_policy_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effective_retention_policy_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"invocation_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"logical_result_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"ordering_evidence_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"provenance_evidence_cids\":[],\"result_artifact_cid\":\"sha256:680cfa71f42bb8a8b171e52c068aae35e07b7668d4cc6670cd4d60b78e7a540a\",\"result_definition",
  "_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"result_schema_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"version\":\"actql-result-artifact/0.1\"}},\"run_definition_cid\":\"sha256:0a872d347ec29b6eb772d3d8421fe4e0daa6f1f1526d3762349461d374335945\",\"version\":\"actql-result-manifest/0.1\"}",
].join("")

///|
let saved_sdk_status_state : String = [
  "{\"next_action\":{\"kind\":\"refresh_availability\",\"results\":[\"answer\"]},\"result_availability\":{\"answer\":{\"observed_at\":\"2026-10-21T00:00:01.000Z\",\"reason\":\"verification_pending\",\"state\":\"unknown\"}},\"result_available\":false,\"revision\":4,\"run_id\":\"saved-manifest-fixture\",\"status\":\"succeeded\",\"updated_at\":\"2026-10-21T00:00:01.000Z\",\"version\":\"actql-run-state/0.1\"}",
].join("")

///|
fn saved_sdk_status_original() -> @host.ClientRunStateOriginal {
  let definition = @publication.admit_publication_contract(
    "run_definition", saved_sdk_status_definition, 65536, 8192, 64,
  ).unwrap()
  let manifest = @publication.admit_publication_contract(
    "result_manifest", saved_sdk_status_manifest, 65536, 8192, 64,
  ).unwrap()
  @host.prepare_client_run_state_original(
    definition, manifest, saved_sdk_status_state,
  ).unwrap()
}

///|
test "cold saved SDK status preserves the exact original state and observation revision" {
  let original = saved_sdk_status_original()
  let observation = @publication.prepare_run_state_observation(
    saved_sdk_status_state, "saved-manifest-fixture", 4L, 65536, 8192, 64,
  ).unwrap()
  assert_eq(
    saved_sdk_run_state_observation_wire(
      original, "saved-manifest-fixture", 4L, observation.key(),
    ),
    Ok(@utf8.encode(saved_sdk_status_state)),
  )
  // Reobservation preserves the original clock, Unknown availability and
  // existing public counter. No new clock or payload evidence is supplied.
  assert_eq(original.state_wire(), saved_sdk_status_state)
  assert_true(saved_sdk_run_state_wire(None) is Err(-42))
}

///|
test "cold saved SDK status refuses foreign run counter and observation key" {
  let original = saved_sdk_status_original()
  let observation = @publication.prepare_run_state_observation(
    saved_sdk_status_state, "saved-manifest-fixture", 4L, 65536, 8192, 64,
  ).unwrap()
  for revision in [0L, 3L, 5L, 9007199254740992L] {
    assert_true(
      saved_sdk_run_state_observation_wire(
        original, "saved-manifest-fixture", revision, observation.key(),
      )
      is Err(-32),
    )
  }
  assert_true(
    saved_sdk_run_state_observation_wire(
      original, "foreign-run", 4L, observation.key(),
    )
    is Err(-32),
  )
  assert_true(
    saved_sdk_run_state_observation_wire(
      original, "saved-manifest-fixture", 4L, "foreign-key",
    )
    is Err(-32),
  )
}

