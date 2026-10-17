///|
// Exercise the actual portable Owner after its implementation moved out of
// the Node facade. Static lowering is not original installed target custody.
test "record check facade and portable Owner retain the same original-capture limitation" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"salesforce.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"installationOwnerCid\":\"sha256:" +
    "e".repeat(64) +
    "\"}]}"
  for word in ["UPSERT", "DELETE"] {
    let suffix = if word == "UPSERT" { " SET (Name = name)" } else { "" }
    let document = "SELECT 'id' AS id, 'original name' AS name |> EFFECT " +
      word +
      " salesforce.Account ID id" +
      suffix
    let node = client_program_check_source(
      document,
      "sql",
      environment,
      publication,
      None,
      None,
      "ctx:" + "a".repeat(64),
      "rev:" + "b".repeat(64),
      None,
      None,
      "corr:record-original",
      "bound_input",
      None,
    )
    let portable = @local_preparation.client_program_check_source(
      document,
      "sql",
      environment,
      publication,
      None,
      None,
      "ctx:" + "a".repeat(64),
      "rev:" + "b".repeat(64),
      None,
      None,
      "corr:record-original",
      "bound_input",
      None,
    )
    assert_eq(node, portable)
    assert_true(node.contains("\"verdict\":\"undetermined\""), msg=node)
    assert_true(node.contains("\"code\":\"implementation_limit\""), msg=node)
    assert_true(!node.contains("\"verdict\":\"verified\""), msg=node)
  }
}
