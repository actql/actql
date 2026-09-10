///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn limits() -> @event_typing.Limits {
  { max_work: 1000, max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }
}

///|
fn events(collision? : String = "", open? : Bool = false) -> @carrier.Carrier {
  let fields : Array[(@row.FieldName, @contract.Contract?)] = [
    (
      Unqualified("event"),
      Some(@contract.decimal_contract(38, 9, nullable=false).unwrap()),
    ),
    (Unqualified("at"), Some(@contract.primitive(NumberType, nullable=false))),
    (Unqualified("payload"), None),
  ]
  if !collision.is_empty() {
    fields.push((Unqualified(collision), None))
  }
  @carrier.events(
    @carrier.rows(
      fields,
      field_set=if open { Open } else { Closed },
      max_fields=4,
      max_name_bytes=100,
    ).unwrap(),
    id=Unqualified("event"),
    time=Unqualified("at"),
  ).unwrap()
}

///|
test "both policies add typed labels while retaining event roles and unknown payload types" {
  for policy in ["drop", "mark"] {
    let checked = @event_typing.check_watermark(
      cursor("{\"watermark_ms\":-0.5,\"policy\":\"" + policy + "\"}"),
      events(),
      limits(),
    ).unwrap()
    assert_eq(@event_typing.watermark(checked), Some(-0.5))
    guard @event_typing.output(checked) is @carrier.EventValue(e) else {
      abort("events")
    }
    assert_eq(e.identity.name, @row.Unqualified("event"))
    assert_eq(e.time.name, @row.Unqualified("at"))
    assert_true(
      e.identity.contract.unwrap().shape is Decimal(precision=38, scale=9),
    )
    assert_eq(@carrier.field_count(e.records), 6)
    assert_true(
      @carrier.lookup(e.records, Unqualified("payload"))
      is Present({ contract: None, .. }),
    )
    assert_true(
      @carrier.lookup(e.records, Unqualified("late"))
      is Present({ contract: Some({ shape: Boolean, nullable: false, }), .. }),
    )
    assert_true(
      @carrier.lookup(e.records, Unqualified("watermark_ms"))
      is Present({ contract: Some({ shape: Number, nullable: false, }), .. }),
    )
    assert_true(
      @carrier.lookup(e.records, Unqualified("watermark_decision"))
      is Present({ contract: Some({ shape: Text(_), nullable: false, }), .. }),
    )
    let pending = @event_typing.pending_validations(checked)
    pending.clear()
    assert_true(
      @event_typing.pending_validations(checked).contains(
        WatermarkClassification,
      ),
    )
  }
}

///|
test "watermark source is closed and generated columns must be fresh" {
  let body = cursor("{\"watermark_ms\":0,\"policy\":\"mark\"}")
  for name in ["watermark_ms", "late", "watermark_decision"] {
    assert_eq(
      @event_typing.check_watermark(body, events(collision=name), limits()).unwrap_err().kind,
      @event_typing.OutputCollision(name),
    )
  }
  assert_eq(
    @event_typing.check_watermark(body, events(open=true), limits()).unwrap_err().kind,
    @event_typing.UnknownOutputFields,
  )
  for
    body in [
      "{\"watermark_ms\":0,\"policy\":\"other\"}", "{\"watermark_ms\":null,\"policy\":\"mark\"}",
      "{\"watermark_ms\":0}", "{\"watermark_ms\":0,\"policy\":\"mark\",\"extra\":true}",
    ] {
    assert_true(
      @event_typing.check_watermark(cursor(body), events(), limits()) is Err(_),
    )
  }
  let issue = @event_typing.check_watermark(
    cursor("{\"watermark_ms\":0,\"policy\":\"other\"}"),
    events(),
    limits(),
  ).unwrap_err()
  assert_eq(issue.path, [@source.Key("policy")])
}
