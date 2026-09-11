///|
test "session Carrier-specific roles are closed before downstream consumption" {
  guard event_input() is @carrier.EventValue(e) else {
    abort("Events expected")
  }
  for
    (input, roles) in [
      (event_input(), "\"id\":\"id\","),
      (event_input(), "\"time\":\"at\","),
      (@carrier.relation(e.records), "\"id\":\"id\","),
      (@carrier.relation(e.records), "\"time\":\"at\","),
    ] {
    let body = cursor("[{\"session\":{" + roles + "\"by\":[],\"gap\":1}}]")
    assert_true(
      @pipeline_typing.check_carriers(
        body,
        [("rows", input)],
        None,
        None,
        limits(),
      )
      is Err(_),
    )
  }
}

///|
test "session keeps typed identity and clock roles across both Carrier alternatives" {
  let identities = [
    @contract.primitive(StringType, nullable=false),
    @contract.primitive(NumberType, nullable=false),
    @contract.primitive(BooleanType, nullable=false),
    @contract.primitive(DateType, nullable=false),
    @contract.primitive(TimestampType, nullable=false),
    @contract.decimal_contract(38, 7, nullable=false).unwrap(),
  ]
  for
    body in [
      "{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":false}",
      "{\"type\":\"artifact_ref\",\"nullable\":false}",
    ] {
    identities.push(
      @contract.read_checked(cursor(body), {
        max_nodes: 20,
        max_depth: 5,
        max_text_bytes: 100,
      }).unwrap(),
    )
  }
  for identity in identities {
    for clock in [@contract.NumberType, @contract.TimestampType] {
      let clock_type = @contract.primitive(clock, nullable=false)
      let records = @carrier.typed_rows(
        @schema.from_object(
          @contract.object_contract(
            [
              ("id", identity),
              ("at", clock_type),
              ("group", @contract.primitive(BooleanType, nullable=true)),
            ],
            nullable=false,
            max_fields=3,
            max_name_bytes=9,
          ).unwrap(),
        ).unwrap(),
      )
      for as_events in [false, true] {
        let input = if as_events {
          @carrier.events(records, id=Unqualified("id"), time=Unqualified("at")).unwrap()
        } else {
          @carrier.relation(records)
        }
        let roles = if as_events {
          ""
        } else {
          "\"id\":\"id\",\"time\":\"at\","
        }
        let bridge = if as_events { ",{\"events\":true}" } else { "" }
        let body = cursor(
          "[{\"session\":{" +
          roles +
          "\"by\":[\"group\",\"group\"],\"gap\":\"1s\"}}" +
          bridge +
          ",{\"select\":[\"id\",\"at\",\"session_id\",\"session_start_ms\",\"session_end_ms\"]},{\"take\":1}]",
        )
        let p = @pipeline_typing.check_carriers(
          body,
          [("rows", input)],
          None,
          None,
          limits(),
        ).unwrap()
        let first = @pipeline_typing.step_at(p, 0).unwrap()
        assert_eq(@carrier.kind(first.output), @carrier.kind(input))
        guard first.operation is @pipeline_typing.Event(checked) else {
          abort("session expected")
        }
        guard @event.options(checked) is Session(s) else {
          abort("session expected")
        }
        assert_eq(@event.session_keys(s), [
          @schema.Unqualified("group"),
          @schema.Unqualified("group"),
        ])
        assert_eq(@event.session_timestamp(s), clock == @contract.TimestampType)
        assert_true(
          @event.pending_validations(checked).contains(SessionIdentity),
        )
        assert_true(
          @event.pending_validations(checked).contains(SessionArithmetic),
        )
        let output = @pipeline_typing.output_schema(p).unwrap()
        assert_true(
          @contract.type_equal(
            @schema.lookup(output, Unqualified("id")).unwrap(),
            identity,
            100,
          ),
        )
        assert_true(
          @contract.type_equal(
            @schema.lookup(output, Unqualified("at")).unwrap(),
            clock_type,
            100,
          ),
        )
        assert_true(
          @pipeline_typing.resolve_contextual_orders(
            p,
            max_steps=4,
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
          cap in [
            { ..exact, max_work: u.work - 1, },
            { ..exact, max_nodes: u.nodes - 1, },
            { ..exact, max_text_bytes: u.text_bytes - 1, },
          ] {
          assert_true(
            @pipeline_typing.check_carriers(
              body,
              [("rows", input)],
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
