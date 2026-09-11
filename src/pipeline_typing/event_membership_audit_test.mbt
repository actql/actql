///|
test "external Events roles do not create keys through windows or row projection" {
  let input = @carrier.events(
    @carrier.typed_rows(schema()),
    id=Unqualified("id"),
    time=Unqualified("amount"),
  ).unwrap()
  for kind in ["fixed", "sliding"] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"window_events\":{\"kind\":\"" +
        kind +
        "\",\"size\":10,\"step\":3}},{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\"}},{\"events\":true},{\"sort\":[{\"id\":\"asc\"}]}]",
      ),
      [("input", input)],
      None,
      None,
      limits(),
    ).unwrap()
    for i in 0..<4 {
      if @pipeline_typing.candidate_keys(p, Step(i)) is Some(keys) {
        assert_eq(@evidence.key_witness_count(keys), 0)
      }
    }
    assert_true(@pipeline_typing.logical_order(p, Step(3)) is None)
  }
}

///|
test "Event membership keys retain alternate aliases and original validation debt" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let declared = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  for reversed in [false, true] {
    for keep_boundary in [false, true] {
      let aliases = if reversed {
        "{\"b\":\"window_start_ms\"},{\"a\":\"window_start_ms\"}"
      } else {
        "{\"a\":\"window_start_ms\"},{\"b\":\"window_start_ms\"}"
      }
      let drop = if keep_boundary { "[\"a\"]" } else { "[\"a\",\"b\"]" }
      let p = @pipeline_typing.check_with_evidence(
        cursor(
          "[{\"to_events\":{\"id\":\"id\",\"time\":\"amount\"}},{\"window_events\":{\"kind\":\"sliding\",\"size\":10,\"step\":3}},{\"events\":true},{\"select\":[\"id\"," +
          aliases +
          "]},{\"drop\":" +
          drop +
          "},{\"sort\":[{\"id\":\"asc\"}]}]",
        ),
        [("rows", @pipeline_typing.KeyedInput(declared))],
        None,
        None,
        limits(),
      ).unwrap()
      let result = @pipeline_typing.candidate_key(p, Step(4))
      assert_eq(result is Some(_), keep_boundary)
      assert_eq(
        @pipeline_typing.logical_order(p, Step(5)) is Some(_),
        keep_boundary,
      )
      if result is Some(result) {
        assert_eq(@evidence.key_origin(result), WindowMembershipResult)
        assert_eq(@evidence.key_field_count(result), 2)
        assert_eq(
          @evidence.key_field_at(result, 1).unwrap().name,
          Unqualified("b"),
        )
        let parent = @evidence.key_window_input(result).unwrap()
        assert_true(
          physical_equal(
            @evidence.key_source(parent),
            @evidence.key_source(declared),
          ),
        )
        assert_true(
          physical_equal(
            @evidence.declared_records(parent),
            @evidence.declared_records(declared),
          ),
        )
        assert_eq(
          @evidence.key_pending(parent),
          @evidence.key_pending(declared),
        )
        assert_true(@evidence.key_window_producer(result) is Some(_))
      }
    }
  }
}
