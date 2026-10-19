///|
test "portable Host reporting identity retains independent reason and outcome schema pins" {
  let (reason, outcome) = client_program_check_reporting_schema_cids()
  // Independent current normative pins. This also rejects swapping two valid
  // CID strings, rather than merely checking their syntax or equal copies.
  assert_eq(
    reason, "sha256:93e2d1285a3136da858996545d957273d70acad3cf180c07d59aa61cfa126ca5",
  )
  assert_eq(
    outcome, "sha256:abc1f9da9c6394f61d780139fe10ce220a25f6579ef80ed043a46c5704cf5f3b",
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
