///|
test "event bridge and business dedupe generate separate conditional witnesses" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=false)
  let row = @schema.from_fields(
    [
      (Unqualified("id"), number),
      (Unqualified("at"), number),
      (Unqualified("account"), text),
      (Unqualified("maybe"), @contract.with_nullability(text, true)),
    ],
    max_fields=4,
    max_name_bytes=30,
  ).unwrap()
  let carrier = @carrier.relation(@carrier.typed_rows(row))
  for by in ["[]", "[\"account\"]", "[\"account\",\"account\"]", "[\"maybe\"]"] {
    let source = cursor(
      "[{\"to_events\":{\"id\":\"id\",\"time\":\"at\"}}," +
      "{\"session\":{\"by\":[],\"gap\":1}}," +
      "{\"dedupe_events\":{\"by\":" +
      by +
      ",\"order_by\":[{\"at\":\"asc\"}]}},{\"events\":true}]",
    )
    let inputs = [("rows", @pipeline_typing.CarrierInput(carrier))]
    let p = @pipeline_typing.check_with_evidence(
      source,
      inputs,
      None,
      None,
      limits(),
    ).unwrap()
    let keys = @pipeline_typing.candidate_keys(p, Step(3)).unwrap()
    assert_eq(@evidence.key_witness_count(keys), if by == "[]" { 1 } else { 2 })
    let id = @evidence.key_witness_at(keys, 0).unwrap()
    assert_eq(@evidence.key_origin(id), EventIdentityResult)
    assert_eq(@evidence.key_field_at(id, 0).unwrap().name, Unqualified("id"))
    let bridge = @evidence.key_event_producer(id).unwrap()
    guard @pipeline_typing.step_at(p, 0).unwrap().operation is Event(actual) else {
      fail("bridge")
    }
    assert_true(physical_equal(bridge, actual))
    assert_true(
      @event.pending_validations(bridge).contains(ValidateUniqueIdentities),
    )
    assert_eq(@evidence.key_pending(id), [ValidateKeyProducer])
    if by != "[]" {
      let business = @evidence.key_witness_at(keys, 1).unwrap()
      assert_eq(@evidence.key_origin(business), EventDedupeResult)
      assert_eq(@evidence.key_field_count(business), 1)
      assert_eq(
        @evidence.key_field_at(business, 0).unwrap().contract.unwrap().nullable,
        by == "[\"maybe\"]",
      )
      let producer = @evidence.key_event_producer(business).unwrap()
      guard @event.options(producer) is Dedupe(spec) else { fail("dedupe") }
      assert_eq(
        @event.dedupe_key_count(spec),
        if by == "[\"account\",\"account\"]" {
          2
        } else {
          1
        },
      )
      assert_true(@event.dedupe_key_at(spec, -1) is None)
      assert_true(
        @event.dedupe_key_at(spec, @event.dedupe_key_count(spec)) is None,
      )
      assert_true(@event.pending_validations(producer).contains(FailOnTopTie))
      assert_true(
        @event.pending_validations(producer).contains(ValidateUniqueIdentities),
      )
      let selected = @evidence.select_key(
        source,
        @evidence.singleton_key(business),
        CanonicalOrder,
        { max_work: 100, max_name_bytes: 100, },
      ).unwrap()
      assert_eq(selected.key is Some(_), by != "[\"maybe\"]")
    }
    let owned = @pipeline_typing.produced_input(p, Step(3)).unwrap()
    let consumer = @pipeline_typing.check_with_evidence(
      cursor("[{\"take\":1}]"),
      [("rows", @pipeline_typing.ProducedInput(owned))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.take_order(consumer, 0) is Some(_))
    let used = @pipeline_typing.usage(p)
    let exact = {
      ..limits(),
      max_work: used.work,
      max_text_bytes: used.text_bytes,
    }
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
      is Ok(_),
    )
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, {
        ..exact,
        max_work: used.work - 1,
      })
      is Err(_),
    )
    assert_true(
      @pipeline_typing.check_with_evidence(source, inputs, None, None, {
        ..exact,
        max_text_bytes: used.text_bytes - 1,
      })
      is Err(_),
    )
  }
}
