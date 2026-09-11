///|
test "sequence identities and author ceilings do not establish static match counts" {
  for events in [false, true] {
    for overlap in ["allow", "disallow"] {
      for guarded in [false, true] {
        let prefix = if events {
          "{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},"
        } else {
          ""
        }
        let p = pipeline(
          "[" +
          prefix +
          "{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"id\",\"pattern\":[{\"as\":\"begin\",\"where\":\"true\"},{\"as\":\"end\",\"where\":\"true\"}],\"within\":1,\"overlap\":\"" +
          overlap +
          "\",\"contiguity\":\"adjacent\"" +
          (if guarded {
            ",\"max_matches_per_key\":1,\"max_output_rows\":1"
          } else {
            ""
          }) +
          "}}]",
        )
        let index = if events { 1 } else { 0 }
        guard @pipeline.step_at(p, index).unwrap().operation is Sequence(op) else {
          fail("sequence expected")
        }
        assert_true(
          @relation.sequence_obligations(op).contains(AtomicMatchLimits),
        )
        assert_true(
          @relation.sequence_obligations(op).contains(UniqueEventIdentity),
        )
        assert_true(@pipeline.row_count(p, Step(index)) is None)
        for count in [0L, 1L, 1000000L] {
          let claim = proof(
            "actql.bound.sequence-output",
            count,
            "{\"op\":\"source\"}",
            reference="checked-step:" + index.to_string(),
          )
          assert_true(
            @capacity_program_step.check(p, index, claim)
            is Err(UnsupportedOperation),
          )
        }
      }
    }
  }
}
