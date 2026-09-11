///|
test "input-free generators replace absent or unrelated current and preserve their own evidence" {
  let profile = calendar_profile()
  let inputs : Array[Array[(String, @carrier.Carrier)]] = [
    [],
    [("unused", @carrier.relation(@carrier.typed_rows(schema())))],
    [("unused", @carrier.unknown_carrier(GraphKind))],
    [("unused", @carrier.unknown_carrier(EventsKind))],
    [("unused", @carrier.unknown_carrier(VectorsKind))],
    [
      ("a", @carrier.unknown_carrier(GraphKind)),
      ("b", @carrier.unknown_carrier(VectorsKind)),
    ],
  ]
  for empty in [false, true] {
    let start = "2000-01-01T00:00:00.000Z"
    let end = if empty { start } else { "2000-01-01T00:00:00.010Z" }
    let calendar_end = if empty { start } else { "2000-01-02T00:00:00.000Z" }
    let cases = [
      (count_values(if empty { 0 } else { 3 }, "generated"), "id", 3L, true),
      (
        "{\"time_series\":{\"start\":\"" +
        start +
        "\",\"end\":\"" +
        end +
        "\",\"step\":3},\"as\":\"generated\"}",
        "time",
        4L,
        true,
      ),
      (
        "{\"calendar_series\":{\"start\":\"" +
        start +
        "\",\"end\":\"" +
        calendar_end +
        "\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"generated\"}",
        "start",
        1L,
        false,
      ),
    ]
    for (body, field, expected, exact_count) in cases {
      for input in inputs {
        let source = cursor(
          "[" + body + ",{\"select\":[\"" + field + "\"]},{\"take\":1}]",
        )
        let p = @pipeline_typing.check_carriers(
          source,
          input,
          None,
          None,
          limits(),
          calendar_profile=Some(profile),
        ).unwrap()
        let generated = @pipeline_typing.step_at(p, 0).unwrap()
        assert_true(generated.input is None)
        assert_true(@pipeline_typing.input_occurrences(generated).is_empty())
        assert_eq(@pipeline_typing.lookup(p, "generated"), Some(Step(0)))
        assert_eq(
          @pipeline_typing.input_occurrences(
            @pipeline_typing.step_at(p, 1).unwrap(),
          ).map(e => e.target),
          [Step(0)],
        )
        assert_eq(@carrier.kind(generated.output), @carrier.RelationKind)
        let count = @pipeline_typing.row_count(p, Step(0)).unwrap()
        if empty {
          assert_eq(count.upper, 0L)
          assert_true(count.exact)
        } else if exact_count {
          assert_eq(count.upper, expected)
          assert_true(count.exact)
        } else {
          assert_true(count.upper >= expected)
        }
        assert_true(@pipeline_typing.logical_order(p, Step(1)) is Some(_))
        assert_true(
          @pipeline_typing.resolve_contextual_orders(
            p,
            max_steps=3,
            max_work=1000,
            max_text_bytes=1000,
          )
          is Ok(_),
        )
        let u = @pipeline_typing.usage(p)
        let exact = {
          ..limits(),
          max_work: u.work,
          max_nodes: u.nodes,
          max_text_bytes: u.text_bytes,
          max_tokens: u.tokens,
        }
        assert_true(
          @pipeline_typing.check_carriers(
            source,
            input,
            None,
            None,
            exact,
            calendar_profile=Some(profile),
          )
          is Ok(_),
        )
        for
          cap in [
            { ..exact, max_work: u.work - 1, },
            { ..exact, max_nodes: u.nodes - 1, },
            { ..exact, max_text_bytes: u.text_bytes - 1, },
          ] {
          assert_true(
            @pipeline_typing.check_carriers(
              source,
              input,
              None,
              None,
              cap,
              calendar_profile=Some(profile),
            )
            is Err(_),
          )
        }
      }
    }
  }
}
