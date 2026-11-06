///|
test "original Run reference preserves the admitted scope and independent identity" {
  let cid = (digit : String) => "sha256:" + digit.repeat(64)
  let definition = @publication.seal_publication_contract(
    "run_definition",
    "{\"version\":\"actql-run-definition/0.1\",\"scope_id\":\"scope\",\"run_id\":\"run\"," +
    "\"compiled_plan_cid\":\"" +
    cid("1") +
    "\",\"invocation_template_cid\":\"" +
    cid("2") +
    "\",\"authorization_context_cid\":\"" +
    cid("3") +
    "\",\"input_artifact_set_cid\":\"" +
    cid("4") +
    "\",\"created_at\":\"2026-09-18T00:00:00.000Z\",\"valid_until\":\"2026-09-18T01:00:00.000Z\"}",
    8192,
    64,
    4,
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(definition),
    "sha256:4a288ff6406340fbcf51438ee9f493b1cb32c8d804be16cab0774cdbdfe3484f",
  )
  let reference = local_original_run_reference(definition, cid("5"))
  assert_eq(
    @json.parse(encode_request_json(reference, 4096)),
    @json.parse(
      "{\"authorityScopeCid\":\"sha256:" +
      "5".repeat(64) +
      "\",\"namespaceId\":\"scope\",\"runDefinitionCid\":\"sha256:4a288ff6406340fbcf51438ee9f493b1cb32c8d804be16cab0774cdbdfe3484f\"}",
    ),
  )
  let invalid_scope = try {
    ignore(local_original_run_reference(definition, "not-a-scope-cid"))
    "unexpected success"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(invalid_scope, "LocalRunReferenceInvalid")
}

///|
test "original Run reference refuses a different admitted contract kind" {
  let invocation = @publication.seal_publication_contract(
    "run_invocation",
    "{\"version\":\"actql-run-invocation/0.1\",\"invocation_template_cid\":\"sha256:" +
    "1".repeat(64) +
    "\",\"observation_set_cid\":\"sha256:" +
    "2".repeat(64) +
    "\"}",
    4096,
    32,
    4,
  ).unwrap()
  let issue = try {
    ignore(local_original_run_reference(invocation, "sha256:" + "5".repeat(64)))
    "unexpected success"
  } catch {
    ClientStop(issue) => issue
  }
  assert_eq(issue, "LocalOriginalRunUnavailable")
}
