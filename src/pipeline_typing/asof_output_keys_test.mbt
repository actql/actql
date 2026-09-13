///|
test "as-of retains every left identity alias but never infers a right-only key" {
  for events in [false, true] {
    for kind in ["left", "inner"] {
      for keep_left in [false, true] {
        let prefix = if events {
          "{\"from\":\"l\",\"to_events\":{\"id\":\"id\",\"time\":\"amount\"}},"
        } else {
          ""
        }
        let from = if events { "" } else { "\"from\":\"l\"," }
        let identity = if events { "" } else { "\"left_id\":\"id\"," }
        let selected = if keep_left {
          "\"a\":\"left.id\",\"b\":\"left.id\","
        } else {
          ""
        }
        let suffix = if keep_left {
          ",{\"drop\":[\"a\"]},{\"sort\":[{\"b\":\"asc\"}]},{\"take\":1}"
        } else {
          ""
        }
        let p = @pipeline_typing.check(
          cursor(
            "[" +
            prefix +
            "{" +
            from +
            "\"asof_join\":{\"with\":\"r\",\"kind\":\"" +
            kind +
            "\",\"by\":[]," +
            identity +
            "\"left_time\":\"amount\",\"right_time\":\"amount\",\"direction\":\"backward\",\"tolerance\":100,\"select\":{" +
            selected +
            "\"right_id\":\"right.id\"}}}" +
            suffix +
            "]",
          ),
          [("l", schema()), ("r", schema())],
          None,
          None,
          limits(),
        ).unwrap()
        let index = if events { 1 } else { 0 }
        let target : @pipeline_typing.Target = Step(
          if keep_left {
            index + 1
          } else {
            index
          },
        )
        let keys = @pipeline_typing.candidate_keys(p, target).unwrap()
        assert_eq(
          @evidence.key_witness_count(keys),
          if keep_left {
            1
          } else {
            0
          },
        )
        if keep_left {
          let key = @evidence.key_witness_at(keys, 0).unwrap()
          assert_eq(@evidence.key_origin(key), AsOfResult)
          assert_eq(
            @evidence.key_field_at(key, 0).unwrap().name,
            Unqualified("b"),
          )
          assert_eq(@evidence.key_asof_parent(key) is Some(_), events)
          if events {
            assert_eq(
              @evidence.key_origin(@evidence.key_asof_parent(key).unwrap()),
              EventIdentityResult,
            )
          }
          let op = @evidence.key_asof_producer(key).unwrap()
          assert_true(
            @join.asof_pending_validations(op).contains(StableIdentity(Left)),
          )
          assert_true(
            @join.asof_pending_validations(op).contains(RejectAsOfTies),
          )
          assert_true(@evidence.key_pending(key).contains(ValidateKeyProducer))
          assert_true(@pipeline_typing.take_order(p, index + 3) is Some(_))
        }
      }
    }
  }
}
