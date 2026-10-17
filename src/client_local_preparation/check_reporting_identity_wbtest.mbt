///|
test "portable Host reporting identity retains independent reason and outcome schema pins" {
  let (reason, outcome) = client_program_check_reporting_schema_cids()
  // Independent current normative pins. This also rejects swapping two valid
  // CID strings, rather than merely checking their syntax or equal copies.
  assert_eq(
    reason, "sha256:1aa2b591972a9cd816826b6500f62ea38f8a4f5282e016b0d1153f8bb68e0742",
  )
  assert_eq(
    outcome, "sha256:988a8893ede0e64a351f077f28c7b7c82a9b2988467b8eb8a02755ad3530ca7b",
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
