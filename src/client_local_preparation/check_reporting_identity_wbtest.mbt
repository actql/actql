///|
test "portable Host reporting identity retains independent reason and outcome schema pins" {
  let (reason, outcome) = client_program_check_reporting_schema_cids()
  // Independent current normative pins. This also rejects swapping two valid
  // CID strings, rather than merely checking their syntax or equal copies.
  assert_eq(
    reason, "sha256:a2bf0f2824052a62a9b501094edd89888c8a5b1ce9530c5d28a6dcee33ce816f",
  )
  assert_eq(
    outcome, "sha256:12497b50d1f2a20ef355b6a3a59ae497bd8dd86ebaca33797ed47af4e2f08423",
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
