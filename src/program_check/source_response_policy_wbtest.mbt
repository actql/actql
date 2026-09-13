///|
test "authored minimum strengthens known classification without replacing unknown" {
  let known = [
    @environment.Public,
    @environment.Internal,
    @environment.Confidential,
    @environment.Restricted,
  ]
  let names = ["public", "internal", "confidential", "restricted"]
  for i in 0..<4 {
    assert_eq(source_classification(known[i], None), known[i])
    for j in 0..<4 {
      assert_eq(
        source_classification(known[i], Some(names[j])),
        known[if i > j { i } else { j }],
      )
    }
    assert_eq(
      source_classification(@environment.Unknown, Some(names[i])),
      @environment.Unknown,
    )
  }
  assert_eq(
    source_classification(@environment.Unknown, None),
    @environment.Unknown,
  )
  try source_classification(@environment.Public, Some("unknown")) catch {
    UnitBuildFailure::ForeignOwner => ()
    error => raise error
  } noraise {
    _ => fail("unadmitted authored classification accepted")
  }
}
