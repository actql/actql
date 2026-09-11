///|
test "watermarks preserve roles and keys without inventing order across Carrier and clock alternatives" {
  for clock in [@contract.NumberType, @contract.TimestampType] {
    let clock_type = @contract.primitive(clock, nullable=false)
    let rows = @carrier.typed_rows(
      @schema.from_object(
        @contract.object_contract(
          [
            ("id", @contract.primitive(NumberType, nullable=false)),
            ("at", clock_type),
          ],
          nullable=false,
          max_fields=2,
          max_name_bytes=4,
        ).unwrap(),
      ).unwrap(),
    )
    for event in [false, true] {
      let input = @carrier.relation(rows)
      let prefix = if event {
        "{\"to_events\":{\"id\":\"id\",\"time\":\"at\"}},"
      } else {
        ""
      }
      let key = @evidence.declare_primary_key(cursor("[\"id\"]"), input, {
        max_fields: 1,
        max_name_bytes: 2,
      }).unwrap()
      for keyed in [false, true] {
        let inputs = [
          (
            "rows",
            if keyed {
              @pipeline_typing.KeyedInput(key)
            } else {
              @pipeline_typing.CarrierInput(input)
            },
          ),
        ]
        for policy in ["mark", "drop"] {
          for threshold in ["-0.5", "0", "1", "1e100"] {
            let operation = if event {
              "watermark_events"
            } else {
              "watermark_rows"
            }
            let options = if event {
              "\"policy\":\""
            } else {
              "\"time\":\"at\",\"late_policy\":\""
            }
            let bridge = if event { ",{\"events\":true}" } else { "" }
            let late = if event { "late" } else { "watermark_late" }
            let text = cursor(
              "[" +
              prefix +
              "{\"" +
              operation +
              "\":{" +
              options +
              policy +
              "\",\"watermark_ms\":" +
              threshold +
              "}}" +
              bridge +
              ",{\"select\":[\"id\",\"at\",\"watermark_ms\",\"" +
              late +
              "\",\"watermark_decision\"]}]",
            )
            let p = @pipeline_typing.check_with_evidence(
              text,
              inputs,
              None,
              None,
              limits(),
            ).unwrap()
            assert_eq(
              @carrier.kind(
                @pipeline_typing.carrier_at(p, Step(if event { 1 } else { 0 })).unwrap(),
              ),
              if event {
                @carrier.EventsKind
              } else {
                @carrier.RelationKind
              },
            )
            let end = @pipeline_typing.step_count(p) - 1
            let out = @pipeline_typing.output_schema(p).unwrap()
            assert_eq(@schema.field_count(out), 5)
            assert_true(
              @contract.type_equal(
                @schema.lookup(out, Unqualified("at")).unwrap(),
                clock_type,
                10,
              ),
            )
            for
              (name, ty) in [
                ("watermark_ms", @contract.NumberType),
                (late, @contract.BooleanType),
                ("watermark_decision", @contract.StringType),
              ] {
              assert_true(
                @contract.type_equal(
                  @schema.lookup(out, Unqualified(name)).unwrap(),
                  @contract.primitive(ty, nullable=false),
                  10,
                ),
              )
            }
            assert_eq(
              @pipeline_typing.candidate_key(p, Step(end)) is Some(_),
              keyed,
            )
            assert_true(@pipeline_typing.logical_order(p, Step(end)) is None)
            assert_true(@pipeline_typing.row_count(p, Step(end)) is None)
            assert_true(
              @pipeline_typing.resolve_contextual_orders(
                p,
                max_steps=4,
                max_work=1000,
                max_text_bytes=1000,
              )
              is Ok(_),
            )
            let usage = @pipeline_typing.usage(p)
            let exact = {
              ..limits(),
              max_work: usage.work,
              max_nodes: usage.nodes,
              max_text_bytes: usage.text_bytes,
              max_tokens: usage.tokens,
            }
            assert_true(
              @pipeline_typing.check_with_evidence(
                text,
                inputs,
                None,
                None,
                exact,
              )
              is Ok(_),
            )
            for
              cap in [
                { ..exact, max_work: usage.work - 1, },
                { ..exact, max_nodes: usage.nodes - 1, },
                { ..exact, max_text_bytes: usage.text_bytes - 1, },
              ] {
              assert_true(
                @pipeline_typing.check_with_evidence(
                  text,
                  inputs,
                  None,
                  None,
                  cap,
                )
                is Err(_),
              )
            }
          }
        }
      }
    }
  }
}

///|
test "watermark dispatch preserves distinct closed bodies and Carrier requirements" {
  let relation = @carrier.relation(@carrier.typed_rows(schema()))
  let events = event_input()
  for
    (input, body) in [
      (
        relation, "{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\"}}",
      ),
      (
        events, "{\"watermark_rows\":{\"time\":\"at\",\"watermark_ms\":0,\"late_policy\":\"mark\"}}",
      ),
      (
        events, "{\"watermark_events\":{\"watermark_ms\":0,\"late_policy\":\"mark\"}}",
      ),
      (events, "{\"watermark_events\":{\"max_skew\":1,\"policy\":\"mark\"}}"),
      (
        events, "{\"watermark_events\":{\"watermark_ms\":{\"$param\":\"threshold\"},\"policy\":\"mark\"}}",
      ),
      (
        events, "{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"ignore\"}}",
      ),
      (
        events, "{\"watermark_events\":{\"watermark_ms\":0,\"policy\":\"mark\",\"time\":\"at\"}}",
      ),
      (
        relation, "{\"watermark_rows\":{\"time\":\"amount\",\"watermark_ms\":0,\"policy\":\"mark\"}}",
      ),
      (
        relation, "{\"watermark_rows\":{\"time\":\"amount\",\"late_policy\":\"mark\"}}",
      ),
      (
        relation, "{\"watermark_rows\":{\"time\":\"amount\",\"watermark_ms\":0,\"max_skew\":1,\"late_policy\":\"mark\"}}",
      ),
    ] {
    assert_true(
      @pipeline_typing.check_carriers(
        cursor("[" + body + "]"),
        [("rows", input)],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}
