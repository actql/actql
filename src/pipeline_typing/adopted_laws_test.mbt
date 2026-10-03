///|
test "adopted law selection distinguishes profile rules from backend support" {
  for
    (profile, expected) in [
      (@pipeline_typing.RelA, [@pipeline_typing.RelaScalar, RelaPrimitive]),
      (SGA, [SgaStructural, SgaIdentity]),
      (PropertyGraph, [PropertyGraphLaw]),
      (VecA, [VecaNumeric]),
      (TEA, []),
      (CalendarProfile, []),
      (TextRankProfile, []),
    ] {
    assert_eq(
      @pipeline_typing.operation_profile_adopted_law_count(profile),
      expected.length(),
    )
    for i in 0..<expected.length() {
      assert_eq(
        @pipeline_typing.operation_profile_adopted_law_at(profile, i),
        Some(expected[i]),
      )
    }
    for invalid in [-2147483648, -1, expected.length(), 2147483647] {
      assert_true(
        @pipeline_typing.operation_profile_adopted_law_at(profile, invalid)
        is None,
      )
    }
  }
}

///|
test "adopted operation laws retain the existing shared body identities" {
  for
    (law, cid) in [
      (
        @pipeline_typing.RelaScalar,
        "sha256:5afa312c0fa9b1e5620bc3556b17aa8da9e50646097ab84a2c04aa8a24575574",
      ),
      (
        RelaPrimitive,
        "sha256:a4ab8487ef731512c3daefa5bed078703336dc52ca268ef4cb7127145f0f2ade",
      ),
      (
        SgaStructural,
        "sha256:1426ea2ceaffc511c0540eba706a5ece132a3df5ee3948702edce7e833fc60df",
      ),
      (
        SgaIdentity,
        "sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4",
      ),
      (
        VecaNumeric,
        "sha256:926c086c2ea57e49102ca5dfb724c851fa7fc148370a0bdf8363457fe5fcd004",
      ),
      (
        PropertyGraphLaw,
        "sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc",
      ),
    ] {
    assert_eq(@pipeline_typing.adopted_operation_law_cid(law), cid)
  }
}
