///|
test "Native Model HTTP keeps the provider's selected installation originals" {
  let revision = "sha256:" + "1".repeat(64)
  let contract = "sha256:" + "2".repeat(64)
  let profile = "sha256:" + "3".repeat(64)
  let foreign = "sha256:" + "4".repeat(64)
  let body = @utf8.encode(
    "{\"configuration_contract_cid\":\"" +
    contract +
    "\",\"installation_revision_cid\":\"" +
    revision +
    "\",\"response_profile_cid\":\"" +
    profile +
    "\"}",
  )
  let limits : @environment.Limits = {
    max_bytes: 1024,
    max_nodes: 16,
    max_depth: 4,
    max_members: 8,
  }
  assert_true(
    native_model_http_configuration_matches(
      body, revision, contract, profile, limits,
    ),
  )
  for
    (revision, contract, profile) in [
      (foreign, contract, profile),
      (revision, foreign, profile),
      (revision, contract, foreign),
    ] {
    assert_false(
      native_model_http_configuration_matches(
        body, revision, contract, profile, limits,
      ),
    )
  }
  assert_false(
    native_model_http_configuration_matches(body, revision, contract, profile, {
      ..limits,
      max_bytes: body.length() - 1,
    }),
  )
}
