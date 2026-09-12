///|
test "fixed steps remain explicit validated options with binding obligations" {
  for n in [1, 2000] {
    let checked = @temporal_window.check(
      cursor(
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1000,\"step\":" +
        n.to_string() +
        "}",
      ),
      @carrier.relation(
        records(Some(@contract.primitive(NumberType, nullable=false))),
      ),
      None,
      limits(),
    ).unwrap()
    let options = @temporal_window.options(checked)
    assert_true(@temporal_window.size(options) is Literal(1000L))
    match @temporal_window.step(options) {
      Some(Literal(value)) => assert_eq(value, n.to_int64())
      _ => fail("step lost")
    }
    assert_eq(
      @decode.finite_number(
        @decode.required(
          @decode.open_object(@temporal_window.source(checked)).unwrap(),
          "step",
        ).unwrap(),
      ).unwrap(),
      n.to_double(),
    )
  }
  let omitted = @temporal_window.read_options(
    cursor("{\"kind\":\"fixed\",\"size\":1000}"),
    relation=false,
    None,
    limits(),
  ).unwrap()
  assert_true(@temporal_window.step(omitted) is None)
  for invalid in ["0", "-1", "1.5", "9007199254740992", "\"0s\""] {
    let issue = @temporal_window.read_options(
      cursor("{\"kind\":\"fixed\",\"size\":1000,\"step\":" + invalid + "}"),
      relation=false,
      None,
      limits(),
    ).unwrap_err()
    assert_eq(issue.kind, InvalidMilliseconds)
    assert_eq(issue.path, [@source.Key("step")])
  }
  let ds = @parameter.read_declarations(
    Some(cursor("{\"stride\":{\"type\":\"number\",\"default\":-1}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let body = cursor(
    "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1000,\"step\":{\"$param\":\"stride\"}}",
  )
  let input = @carrier.relation(
    records(Some(@contract.primitive(NumberType, nullable=false))),
  )
  assert_eq(
    @temporal_window.check(body, input, None, limits()).unwrap_err().kind,
    UnknownParameter("stride"),
  )
  let checked = @temporal_window.check(body, input, Some(ds), limits()).unwrap()
  assert_true(
    indexed_obligation_copy(
      @temporal_window.pending_validations(checked),
      @temporal_window.pending_validation_count(checked),
      i => @temporal_window.pending_validation_at(checked, i),
      (a, b) => a == b,
    ).contains(BindMilliseconds("stride", PositiveMilliseconds)),
  )
  assert_true(
    @temporal_window.step(@temporal_window.options(checked))
    is Some(Parameter("stride", duration=false, domain=PositiveMilliseconds)),
  )
}

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
    let pending = indexed_obligation_copy(
      @temporal_window.pending_validations(checked),
      @temporal_window.pending_validation_count(checked),
      i => @temporal_window.pending_validation_at(checked, i),
      (a, b) => a == b,
    )
    pending.clear()
    assert_eq(
      indexed_obligation_copy(
        @temporal_window.pending_validations(checked),
        @temporal_window.pending_validation_count(checked),
        i => @temporal_window.pending_validation_at(checked, i),
        (a, b) => a == b,
      ).length(),
      4,
    )
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
