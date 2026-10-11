///|
test "Local authoring sidecar keeps original grammar metadata outside semantics" {
  let document = local_normalization_document
    .replace(
      old="\"id\":\"local.normalization\"",
      new="\"id\":\"local.normalization\",\"meta\":{\"note\":\"root\"}",
    )
    .replace(
      old="\"id\":\"source\"",
      new="\"id\":\"source\",\"meta\":{\"note\":\"stage\"}",
    )
    .replace(
      old="\"view\":\"v\"",
      new="\"view\":\"v\",\"meta\":{\"note\":\"input\"}",
    )
    .replace(
      old="\"as\":\"derived\"",
      new="\"as\":\"derived\",\"meta\":{\"note\":\"step\"}",
    )
  let original = local_normalization_fixture()
  let owner = local_normalization_fixture(document~)
  assert_eq(prepared_client_identity(owner), prepared_client_identity(original))
  let value = issue_prepared_client_authoring_context(owner, 65536, 4096, 64).unwrap()
  // Independently assembled grammar targets and canonical preimage; neither
  // the annotations nor their expectation are obtained from the new issuer.
  let annotations =
    #|[{"meta":{"note":"root"},"target":{"kind":"program","name":"local.normalization","source_path":"$"}},{"meta":{"note":"stage"},"target":{"kind":"stage","name":"source","source_path":"$[\"stages\"][0]"}},{"meta":{"note":"input"},"target":{"kind":"input","name":"table","source_path":"$[\"stages\"][0][\"inputs\"][\"table\"]"}},{"meta":{"note":"step"},"target":{"kind":"step","name":"derived","source_path":"$[\"stages\"][2][\"steps\"][0]"}}]
  let cid = prepared_client_identity(original).program_definition_cid
  let preimage = "{\"annotations\":" +
    annotations +
    ",\"program_definition_cid\":\"" +
    cid +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  let identity = "sha256:" + @sha.hex(@utf8.encode(preimage))
  let expected = "{\"annotations\":" +
    annotations +
    ",\"authoring_context_cid\":\"" +
    identity +
    "\",\"program_definition_cid\":\"" +
    cid +
    "\",\"version\":\"actql-authoring-context/0.1\"}"
  assert_eq(@publication.run_evidence_value_json(value), expected)
  assert_eq(@publication.run_evidence_value_identity(value), identity)
  let changed = local_normalization_fixture(
    document=document.replace(old="root", new="changed"),
  )
  assert_eq(prepared_client_identity(owner), prepared_client_identity(changed))
  assert_true(
    @publication.run_evidence_value_identity(
      issue_prepared_client_authoring_context(changed, 65536, 4096, 64).unwrap(),
    ) !=
    identity,
  )
}

///|
test "Local authoring sidecar does not extract business meta or truncate annotations" {
  let document = local_normalization_document
    .replace(old="\"value\":\"id + 1\"", new="\"meta\":\"id + 1\"")
    .replace(old="\"id\",\"value\"", new="\"id\",\"meta\"")
    .replace(old="value * 2 - 1", new="meta * 2 - 1")
  let owner = local_normalization_fixture(document~)
  let value = issue_prepared_client_authoring_context(owner, 65536, 4096, 64).unwrap()
  let wire = @publication.run_evidence_value_json(value)
  assert_true(wire.contains("\"annotations\":[]"))
  assert_true(!wire.contains("\"meta\""))
  assert_true(
    issue_prepared_client_authoring_context(owner, 1, 4096, 64) is Err(_),
  )
  assert_true(
    issue_prepared_client_authoring_context(owner, 65536, 1, 64) is Err(_),
  )
}
