///|
fn interval_row(timestamp : Bool, nullable : Bool) -> @schema.Schema {
  let c = @contract.primitive(
    if timestamp {
      TimestampType
    } else {
      NumberType
    },
    nullable~,
  )
  @schema.from_fields(
    [
      (Unqualified("time"), c),
      (Unqualified("start"), c),
      (Unqualified("end"), c),
      (Unqualified("id"), @contract.primitive(StringType, nullable=true)),
    ],
    max_fields=4,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "interval output guard parameters retain binding obligations without defaults" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"cap\":{\"type\":\"number\",\"default\":5},\"bad\":{\"type\":\"string\"}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let row = interval_row(false, false)
  for name in ["cap", "bad", "missing"] {
    let body = cursor(
      "{\"with\":\"r\",\"kind\":\"inner\",\"mode\":\"overlap\",\"on\":[],\"left\":{\"start\":\"start\",\"end\":\"end\"},\"right\":{\"start\":\"start\",\"end\":\"end\"},\"max_output_rows\":{\"$param\":\"" +
      name +
      "\"}}",
    )
    let result = @relation_join.check_interval(
      body,
      row,
      row,
      Some(declarations),
      limits(),
    )
    if name == "cap" {
      let checked = result.unwrap()
      assert_eq(
        @relation_join.interval_output_guard(checked),
        Some(Parameter("cap")),
      )
      assert_true(
        indexed_obligation_copy(
          @relation_join.interval_pending_validations(checked),
          @relation_join.interval_pending_validation_count(checked),
          i => @relation_join.interval_pending_validation_at(checked, i),
          (a, b) => a == b,
        ).contains(BindGuard("cap")),
      )
    } else {
      assert_true(result is Err(_))
    }
  }
}

///|
test "interval input provenance cannot be silently flattened" {
  let row = interval_row(false, false)
  let qualified = @schema.from_fields(
    [(Qualified(Left, "time"), @contract.primitive(NumberType, nullable=false))],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"inner\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
  )
  assert_true(
    @relation_join.check_interval(body, qualified, row, None, limits())
    is Err({ kind: QualifiedInput(Left), .. }),
  )
  assert_true(
    @relation_join.check_interval(body, row, qualified, None, limits())
    is Err({ kind: QualifiedInput(Right), .. }),
  )
}

///|
test "interval join domains and kinds preserve qualified columns and null extension" {
  for timestamp in [false, true] {
    for
      (kind_name, kind) in [
        ("inner", @relation_join.Kind::Inner),
        ("left", Left),
        ("semi", Semi),
        ("anti", Anti),
      ] {
      for overlap in [false, true] {
        let body = if overlap {
          "{\"with\":\"r\",\"kind\":\"" +
          kind_name +
          "\",\"mode\":\"overlap\",\"on\":[],\"left\":{\"start\":\"start\",\"end\":\"end\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}"
        } else {
          "{\"with\":\"r\",\"kind\":\"" +
          kind_name +
          "\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}"
        }
        let row = interval_row(timestamp, false)
        let checked = @relation_join.check_interval(
          cursor(body),
          row,
          row,
          None,
          limits(),
        ).unwrap()
        assert_eq(@relation_join.interval_kind(checked), kind)
        assert_eq(@relation_join.interval_uses_timestamps(checked), timestamp)
        assert_eq(
          @relation_join.interval_mode(checked),
          if overlap {
            Overlap
          } else {
            PointInInterval
          },
        )
        assert_eq(
          @relation_join.interval_operand(checked, Right),
          Interval(Unqualified("start"), Unqualified("end")),
        )
        let output = @relation_join.interval_output_schema(checked)
        assert_eq(
          @schema.field_count(output),
          if kind == Semi || kind == Anti {
            4
          } else {
            8
          },
        )
        assert_eq(
          @schema.lookup(output, Qualified(Left, "time")).unwrap().nullable,
          false,
        )
        if kind == Inner || kind == Left {
          assert_eq(
            @schema.lookup(output, Qualified(Right, "time")).unwrap().nullable,
            kind == Left,
          )
        }
        let pending = indexed_obligation_copy(
          @relation_join.interval_pending_validations(checked),
          @relation_join.interval_pending_validation_count(checked),
          i => @relation_join.interval_pending_validation_at(checked, i),
          (a, b) => a == b,
        )
        for
          required in [
            @relation_join.Obligation::ValidateIntervalEndpoints,
            ResolveProductBound,
            ResolveSearchWork,
            ResolveOutputLimit,
          ] {
          assert_true(pending.contains(required))
        }
        assert_eq(pending.contains(ValidateSafeIntegerClocks), !timestamp)
        pending.clear()
        assert_true(
          !indexed_obligation_copy(
            @relation_join.interval_pending_validations(checked),
            @relation_join.interval_pending_validation_count(checked),
            i => @relation_join.interval_pending_validation_at(checked, i),
            (a, b) => a == b,
          ).is_empty(),
        )
      }
    }
  }
}

///|
test "interval join rejects malformed temporal fields at their source location" {
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
  )
  let number = interval_row(false, false)
  let timestamp = interval_row(true, false)
  let nullable = interval_row(false, true)
  let mixed = @relation_join.check_interval(
    body,
    number,
    timestamp,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(mixed.kind, MixedTimeDomains)
  assert_eq(mixed.path, [Key("right"), Key("start")])
  let bad = @relation_join.check_interval(
    body,
    nullable,
    number,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(bad.kind, InvalidTemporalField(Left, "time"))
  assert_eq(bad.path, [Key("left"), Key("time")])
  let text = cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
  )
  assert_true(
    @relation_join.check_interval(text, number, number, None, limits())
    is Err({ kind: InvalidTemporalField(Left, "id"), .. }),
  )
  let unknown = cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"missing\"}}",
  )
  let error = @relation_join.check_interval(
    unknown,
    number,
    number,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(error.kind, UnknownField(Right, "missing"))
  assert_eq(error.path, [Key("right"), Key("end")])
}

///|
test "interval join retains repeated conditions aliases guards and exact budgets" {
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"},\"select\":{\"a\":\"left.time\",\"b\":\"left.time\",\"c\":\"right.end\"},\"max_output_rows\":7}",
  )
  let row = interval_row(false, false)
  let c = @relation_join.check_interval(body, row, row, None, limits()).unwrap()
  let keys = @relation_join.interval_keys(c)
  assert_eq(keys.length(), 2)
  keys.clear()
  assert_eq(@relation_join.interval_keys(c).length(), 2)
  let projection = @relation_join.interval_projection(c).unwrap()
  assert_eq(projection.map(p => p.output), [
    Unqualified("a"),
    Unqualified("b"),
    Unqualified("c"),
  ])
  projection.clear()
  assert_eq(@relation_join.interval_projection(c).unwrap().length(), 3)
  assert_eq(@relation_join.interval_output_guard(c), Some(Literal(7L)))
  let u = @relation_join.interval_usage(c)
  let exact : @relation_join.Limits = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @relation_join.check_interval(body, row, row, None, exact) is Ok(_),
  )
  for
    small in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      @relation_join.check_interval(body, row, row, None, small)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "interval join accepts only its closed mode specific grammar" {
  let row = interval_row(false, false)
  for
    body in [
      "{\"with\":\"r\",\"kind\":\"full\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"nearest\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":\"id\",\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[\"id\"],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\",\"end\":\"end\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"overlap\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"},\"max_output_rows\":0}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"},\"select\":{}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[{\"left\":\"id\",\"right\":\"time\"}],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"time\"},\"right\":{\"start\":\"start\",\"end\":\"end\"},\"null_key\":\"fail\"}",
    ] {
    assert_true(
      @relation_join.check_interval(cursor(body), row, row, None, limits())
      is Err(_),
    )
  }
}
