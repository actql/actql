///|
test "portable Host reporting identity retains independent reason and outcome schema pins" {
  let (reason, outcome) = client_program_check_reporting_schema_cids()
  // Independent current normative pins. This also rejects swapping two valid
  // CID strings, rather than merely checking their syntax or equal copies.
  assert_eq(
    reason, "sha256:29e062b1b136ffb4da40ca3a38348768759293240d008e7d019d36aa6d3de511",
  )
  assert_eq(
    outcome, "sha256:ce7df95dc9d069472f6dd61273acb6e5d09aba605347cddda5c4a23c6e5e52f6",
  )
  assert_true(reason != outcome)
  let unavailable = client_program_check_unavailable("corr:reporting-identity")
  assert_true(
    unavailable.contains("\"reason_schema_cid\":\"" + reason + "\""),
    msg=unavailable,
  )
  assert_true(
    unavailable.contains("\"outcome_schema_cid\":\"" + outcome + "\""),
    msg=unavailable,
  )
  assert_true(!unavailable.contains("\"report\""), msg=unavailable)
}
