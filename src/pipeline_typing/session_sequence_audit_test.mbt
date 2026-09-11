///|
test "sequence after session retains typed labels and distinct overlap evidence" {
  for
    identity in [
      @contract.primitive(StringType, nullable=false),
      @contract.primitive(NumberType, nullable=false),
      @contract.decimal_contract(38, 7, nullable=false).unwrap(),
    ] {
    for timestamp in [false, true] {
      let records = @carrier.typed_rows(
        @schema.from_object(
          @contract.object_contract(
            [
              ("id", identity),
              (
                "at",
                @contract.primitive(
                  if timestamp {
                    TimestampType
                  } else {
                    NumberType
                  },
                  nullable=false,
                ),
              ),
            ],
            nullable=false,
            max_fields=2,
            max_name_bytes=4,
          ).unwrap(),
        ).unwrap(),
      )
      for events in [false, true] {
        let input = if events {
          @carrier.events(records, id=Unqualified("id"), time=Unqualified("at")).unwrap()
        } else {
          @carrier.relation(records)
        }
        let roles = if events { "" } else { "\"id\":\"id\",\"time\":\"at\"," }
        for overlap in ["allow", "disallow"] {
          for contiguity in ["adjacent", "subsequence"] {
            // Events sequence clocks are explicitly numeric-only. Session's
            // generated numeric boundary is selected, not an implicit cast.
            let time = if events && timestamp {
              "session_start_ms"
            } else {
              "at"
            }
            let body = cursor(
              "[{\"session\":{" +
              roles +
              "\"by\":[],\"gap\":1}},{\"sequence\":{\"by\":[\"session_id\",\"session_id\"],\"id\":\"id\",\"time\":\"" +
              time +
              "\",\"pattern\":[{\"as\":\"begin\",\"where\":\"true\"},{\"as\":\"end\",\"where\":\"true\"}],\"within\":1,\"overlap\":\"" +
              overlap +
              "\",\"contiguity\":\"" +
              contiguity +
              "\"}},{\"take\":1}]",
            )
            let p = @pipeline_typing.check_carriers(
              body,
              [("rows", input)],
              None,
              None,
              limits(),
            ).unwrap()
            guard @pipeline_typing.step_at(p, 1).unwrap().operation
              is @pipeline_typing.Sequence(checked) else {
              abort("sequence expected")
            }
            assert_eq(
              @relation.sequence_requires_timestamp_conversion(checked),
              timestamp && !events,
            )
            let output = @relation.sequence_output(checked)
            assert_eq(@schema.field_count(output), 7)
            for label in ["begin_id", "end_id"] {
              assert_true(
                @contract.type_equal(
                  @schema.lookup(output, Unqualified(label)).unwrap(),
                  identity,
                  100,
                ),
              )
            }
            assert_true(
              @relation.sequence_obligations(checked).contains(
                UniqueEventIdentity,
              ),
            )
            assert_true(
              @relation.sequence_obligations(checked).contains(
                AtomicMatchLimits,
              ),
            )
            let keys = @pipeline_typing.candidate_keys(p, Step(1)).unwrap()
            assert_eq(
              @evidence.key_witness_count(keys),
              if overlap == "disallow" {
                2
              } else {
                0
              },
            )
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
                body,
                [("rows", input)],
                None,
                None,
                exact,
              )
              is Ok(_),
            )
            for
              caps in [
                { ..exact, max_work: u.work - 1, },
                { ..exact, max_nodes: u.nodes - 1, },
                { ..exact, max_text_bytes: u.text_bytes - 1, },
                { ..exact, max_tokens: u.tokens - 1, },
              ] {
              assert_true(
                @pipeline_typing.check_carriers(
                  body,
                  [("rows", input)],
                  None,
                  None,
                  caps,
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
test "session does not silently convert a timestamp Events clock for sequence" {
  let records = @carrier.typed_rows(
    @schema.from_object(
      @contract.object_contract(
        [
          ("id", @contract.primitive(StringType, nullable=false)),
          ("at", @contract.primitive(TimestampType, nullable=false)),
        ],
        nullable=false,
        max_fields=2,
        max_name_bytes=4,
      ).unwrap(),
    ).unwrap(),
  )
  let input = @carrier.events(
    records,
    id=Unqualified("id"),
    time=Unqualified("at"),
  ).unwrap()
  let issue = @pipeline_typing.check_carriers(
    cursor(
      "[{\"session\":{\"by\":[],\"gap\":1}},{\"sequence\":{\"by\":[\"session_id\"],\"id\":\"id\",\"time\":\"at\",\"pattern\":[{\"as\":\"begin\",\"where\":\"true\"},{\"as\":\"end\",\"where\":\"true\"}],\"within\":1,\"overlap\":\"allow\",\"contiguity\":\"adjacent\"}}]",
    ),
    [("rows", input)],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, Operation(IncompatibleColumn("at")))
  assert_eq(issue.path, [Index(1), Key("sequence"), Key("time")])
}
