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

///|
test "policy classification composition is order independent and preserves unknown" {
  let classes = [
    @environment.Public,
    @environment.Internal,
    @environment.Confidential,
    @environment.Restricted,
    @environment.Unknown,
  ]
  for i, a in classes {
    assert_eq(combine_classification(a, a), a)
    for j, b in classes {
      let expected = classes[if i > j { i } else { j }]
      assert_eq(combine_classification(a, b), expected)
      assert_eq(combine_classification(a, b), combine_classification(b, a))
      for c in classes {
        assert_eq(
          combine_classification(combine_classification(a, b), c),
          combine_classification(a, combine_classification(b, c)),
        )
      }
    }
  }
}
