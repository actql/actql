///|
test "adopted law selection distinguishes profile rules from backend support" {
  for
    (profile, expected) in [
      (@pipeline_typing.RelA, [@pipeline_typing.RelaScalar, RelaPrimitive]),
      (SGA, [SgaStructural, SgaIdentity]),
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
        "sha256:a866ed224e15da7e25b45d4e166b25b6bd6749a31bd7dfacb185391ad3f80122",
      ),
      (
        RelaPrimitive,
        "sha256:78738e358ec26e70304f7cad6b0ac10b063f9939b107b903bebac4c8fc56d5b2",
      ),
      (
        SgaStructural,
        "sha256:7dbf4a4b5830e66867388a34f12751691e9c90594e8e09cab754472144a65b18",
      ),
      (
        SgaIdentity,
        "sha256:ab1ae472462b96ac48e56d3ce0544213cab5d422e6bb198bc9acd5e4d90e0fe4",
      ),
      (
        VecaNumeric,
        "sha256:926c086c2ea57e49102ca5dfb724c851fa7fc148370a0bdf8363457fe5fcd004",
      ),
    ] {
    assert_eq(@pipeline_typing.adopted_operation_law_cid(law), cid)
  }
}
