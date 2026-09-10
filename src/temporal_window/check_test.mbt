///|
fn records(
  time : @contract.Contract?,
  open? : Bool = false,
) -> @carrier.Knowledge {
  @carrier.rows(
    [
      (Unqualified("at"), time),
      (Unqualified("id"), Some(@contract.primitive(StringType, nullable=false))),
      (Unqualified("payload"), None),
    ],
    field_set=if open { Open } else { Closed },
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "row windows preserve partially typed payload and prove boundary roles" {
  for primitive in [@contract.NumberType, @contract.TimestampType] {
    let original = records(Some(@contract.primitive(primitive, nullable=false)))
    let checked = @temporal_window.check(
      cursor("{\"kind\":\"fixed\",\"time\":\"at\",\"size\":\"1s\"}"),
      @carrier.relation(original),
      None,
      limits(),
    ).unwrap()
    let output = @carrier.relation_rows(@temporal_window.output(checked)).unwrap()
    assert_eq(@carrier.field_count(output), 5)
    match @carrier.lookup(output, Unqualified("payload")) {
      Present(f) => assert_true(f.contract is None)
      _ => fail("payload knowledge was lost")
    }
    assert_eq(
      @temporal_window.boundary_fields(@temporal_window.window_roles(checked)),
      (@row.Unqualified("window_start"), @row.Unqualified("window_end")),
    )
    assert_eq(
      @temporal_window.requires_epoch_milliseconds(checked),
      primitive == TimestampType,
    )
    assert_eq(@carrier.field_count(original), 3)
    let pending = @temporal_window.pending_validations(checked)
    pending.clear()
    assert_eq(@temporal_window.pending_validations(checked).length(), 4)
  }
}

///|
test "event windows retain event identity clock and carrier" {
  let input = @carrier.events(
    records(Some(@contract.primitive(NumberType, nullable=false))),
    id=Unqualified("id"),
    time=Unqualified("at"),
  ).unwrap()
  let checked = @temporal_window.check(
    cursor("{\"kind\":\"sliding\",\"size\":10,\"step\":3,\"offset\":-7}"),
    input,
    None,
    limits(),
  ).unwrap()
  match @temporal_window.output(checked) {
    EventValue(e) => {
      assert_eq(e.identity.name, @row.Unqualified("id"))
      assert_eq(e.time.name, @row.Unqualified("at"))
      assert_eq(@carrier.field_count(e.records), 5)
    }
    _ => fail("expected Events")
  }
  assert_eq(
    @temporal_window.boundary_fields(@temporal_window.window_roles(checked)),
    (@row.Unqualified("window_start_ms"), @row.Unqualified("window_end_ms")),
  )
}

///|
test "window checking rejects missing time evidence and generated collisions" {
  let body = cursor("{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1}")
  for
    ty in [
      None,
      Some(@contract.primitive(NumberType, nullable=true)),
      Some(@contract.primitive(DateType, nullable=false)),
      Some(@contract.primitive(StringType, nullable=false)),
    ] {
    assert_true(
      @temporal_window.check(
        body,
        @carrier.relation(records(ty)),
        None,
        limits(),
      )
      is Err(_),
    )
  }
  assert_true(
    @temporal_window.check(
      body,
      @carrier.relation(
        records(
          Some(@contract.primitive(NumberType, nullable=false)),
          open=true,
        ),
      ),
      None,
      limits(),
    )
    is Err(_),
  )
  let colliding = @carrier.rows(
    [
      (Unqualified("at"), Some(@contract.primitive(NumberType, nullable=false))),
      (Unqualified("window_end"), None),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    @temporal_window.check(body, @carrier.relation(colliding), None, limits())
    is Err(_),
  )
}
