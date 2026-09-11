///|
fn asof_rows(timestamp : Bool) -> @carrier.Knowledge {
  @carrier.rows(
    [
      (Unqualified("id"), Some(@contract.primitive(NumberType, nullable=false))),
      (
        Unqualified("other"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
      (
        Unqualified("time"),
        Some(
          @contract.primitive(
            if timestamp {
              TimestampType
            } else {
              NumberType
            },
            nullable=false,
          ),
        ),
      ),
      (Unqualified("key"), Some(@contract.primitive(StringType, nullable=true))),
      (Unqualified("unknown"), None),
    ],
    field_set=Open,
    max_fields=5,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "as-of supports Relation and Events with independent UTC representations" {
  for left_ts in [true, false] {
    for right_ts in [true, false] {
      for events in [true, false] {
        let rows = asof_rows(left_ts)
        let left = if events {
          @carrier.events(rows, id=Unqualified("id"), time=Unqualified("time")).unwrap()
        } else {
          @carrier.relation(rows)
        }
        let right = @carrier.relation(asof_rows(right_ts))
        for
          (kind, direction, expected) in [
            ("left", "backward", @relation_join.AsOfDirection::Backward),
            ("inner", "forward", Forward),
            ("left", "nearest", Nearest),
          ] {
          let body = cursor(
            "{\"with\":\"r\",\"kind\":\"" +
            kind +
            "\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"" +
            direction +
            "\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
          )
          let c = @relation_join.check_asof(body, left, right, None, limits()).unwrap()
          let transferred = @evidence.transfer_asof_keys(None, c, {
            max_work: 10000,
            max_name_bytes: 10000,
          }).unwrap()
          let transfer_limits : @evidence.TransferLimits = {
            max_work: transferred.work,
            max_name_bytes: transferred.name_bytes,
          }
          assert_true(
            @evidence.transfer_asof_keys(None, c, transfer_limits) is Ok(_),
          )
          for
            cap in [
              { ..transfer_limits, max_work: transfer_limits.max_work - 1, },
              {
                ..transfer_limits,
                max_name_bytes: transfer_limits.max_name_bytes - 1,
              },
            ] {
            assert_true(@evidence.transfer_asof_keys(None, c, cap) is Err(_))
          }
          let foreign = @evidence.declare_primary_key(
            cursor("[\"id\"]"),
            @carrier.relation(asof_rows(left_ts)),
            { max_fields: 1, max_name_bytes: 2, },
          ).unwrap()
          let mismatch = @evidence.transfer_asof_keys(
            Some(@evidence.singleton_key(foreign)),
            c,
            { max_work: 10000, max_name_bytes: 10000, },
          ).unwrap_err()
          assert_eq(mismatch.kind, InputContractMismatch)
          let original_left = @relation_join.asof_input_records(c, Left)
          assert_true(physical_equal(original_left, rows))
          assert_true(
            physical_equal(
              @relation_join.asof_input_records(c, Right),
              @carrier.relation_rows(right).unwrap(),
            ),
          )
          assert_true(!physical_equal(original_left, asof_rows(left_ts)))
          assert_true(
            @carrier.lookup(original_left, Unqualified("unknown"))
            is Present({ contract: None, .. }),
          )
          assert_true(
            @carrier.lookup(original_left, Unqualified("absent")) is Unknown,
          )
          assert_eq(@relation_join.asof_projection_count(c), 2)
          let projected = @relation_join.asof_projection(c)
          for i, field in projected {
            let indexed = @relation_join.asof_projection_at(c, i).unwrap()
            assert_eq(indexed.input, field.input)
            assert_eq(indexed.output, field.output)
          }
          projected.clear()
          assert_eq(@relation_join.asof_projection_count(c), 2)
          assert_true(@relation_join.asof_projection_at(c, -1) is None)
          assert_true(@relation_join.asof_projection_at(c, 2) is None)
          assert_eq(@relation_join.asof_direction(c), expected)
          assert_eq(@relation_join.asof_uses_timestamp(c, Left), left_ts)
          assert_eq(@relation_join.asof_uses_timestamp(c, Right), right_ts)
          assert_eq(@relation_join.asof_identity(c), [Unqualified("id")])
          assert_true(
            @relation_join.asof_tolerance(c) is @temporal.Literal(1000L),
          )
          let out = @relation_join.asof_output_schema(c)
          assert_eq(
            @schema.lookup(out, Unqualified("value")).unwrap().nullable,
            kind == "left",
          )
          assert_true(
            @relation_join.asof_pending_validations(c).contains(RejectAsOfTies),
          )
          assert_true(
            @relation_join.asof_pending_validations(c).contains(
              ResolveSearchWork,
            ),
          )
          assert_true(
            @relation_join.asof_pending_validations(c).contains(
              ResolveAsOfOrder,
            ),
          )
        }
      }
    }
  }
}

///|
test "as-of preserves intrinsic Events identity and never guesses a Relation key" {
  let rows = asof_rows(false)
  let relation = @carrier.relation(rows)
  let events = @carrier.events(
    rows,
    id=Unqualified("id"),
    time=Unqualified("time"),
  ).unwrap()
  let omitted = cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
  )
  let c = @relation_join.check_asof(omitted, events, relation, None, limits()).unwrap()
  assert_eq(@relation_join.asof_identity(c), [Unqualified("id")])
  assert_true(
    @relation_join.check_asof(omitted, relation, relation, None, limits())
    is Err({ kind: MissingLeftIdentity, .. }),
  )
  assert_true(
    @relation_join.check_asof(
      cursor(
        "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"other\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      ),
      events,
      relation,
      None,
      limits(),
    )
    is Err({ kind: InvalidLeftIdentity, .. }),
  )
  assert_true(
    @relation_join.check_asof(
      cursor(
        "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"key\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      ),
      relation,
      relation,
      None,
      limits(),
    )
    is Err({ kind: InvalidLeftIdentity, .. }),
  )
  // The explicit comparison clock may differ without changing intrinsic identity.
  assert_true(
    @relation_join.check_asof(
      cursor(
        "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"other\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      ),
      events,
      relation,
      None,
      limits(),
    )
    is Ok(_),
  )
}

///|
test "as-of key and tie occurrences are detached and exact budgets remain cumulative" {
  let rows = @carrier.relation(asof_rows(false))
  let body = cursor(
    "{\"with\":\"r\",\"kind\":\"left\",\"by\":[{\"left\":\"key\",\"right\":\"key\"},{\"left\":\"key\",\"right\":\"key\"}],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"a\":\"left.id\",\"b\":\"left.id\"},\"right_tie_break\":[\"key\",\"key\"]}",
  )
  let c = @relation_join.check_asof(body, rows, rows, None, limits()).unwrap()
  let keys = @relation_join.asof_keys(c)
  assert_eq(keys.length(), 2)
  keys.clear()
  assert_eq(@relation_join.asof_keys(c).length(), 2)
  let ties = @relation_join.asof_tie_break(c).unwrap()
  assert_eq(ties, [Unqualified("key"), Unqualified("key")])
  ties.clear()
  assert_eq(@relation_join.asof_tie_break(c).unwrap().length(), 2)
  let ids = @relation_join.asof_identity(c)
  ids.clear()
  assert_eq(@relation_join.asof_identity(c).length(), 1)
  let projection = @relation_join.asof_projection(c)
  projection.clear()
  assert_eq(@relation_join.asof_projection(c).length(), 2)
  let u = @relation_join.asof_usage(c)
  let exact : @relation_join.Limits = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@relation_join.check_asof(body, rows, rows, None, exact) is Ok(_))
  for
    small in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      @relation_join.check_asof(body, rows, rows, None, small) is Err(_),
    )
  }
}

///|
test "as-of closed body and typed field diagnostics reject before execution" {
  let rows = @carrier.relation(asof_rows(false))
  for
    body in [
      "{\"with\":\"r\",\"kind\":\"full\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"},\"null_key\":\"no_match\"}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":0,\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[\"key\"],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[{\"left\":\"key\",\"right\":\"id\"}],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"},\"right_tie_break\":[{\"key\":\"asc\"}]}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"key\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"a\":\"right.unknown\"}}",
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":null,\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
    ] {
    assert_true(
      @relation_join.check_asof(cursor(body), rows, rows, None, limits())
      is Err(_),
    )
  }
  let unknown = @relation_join.check_asof(
    cursor(
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"unknown\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
    ),
    rows,
    rows,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(unknown.kind, UnknownFieldType(Right, "unknown"))
  assert_eq(unknown.path, [Key("right_time")])
  assert_true(
    @relation_join.check_asof(
      cursor(
        "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":\"1s\",\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      ),
      @carrier.unknown_carrier(GraphKind),
      rows,
      None,
      limits(),
    )
    is Err({ kind: WrongCarrier(Left, GraphKind), .. }),
  )
}

///|
test "as-of tolerance bindings remain symbolic and validate their declaration domains" {
  let parameters = @parameter.read_declarations(
    Some(
      cursor(
        "{\"tol\":{\"type\":\"string\",\"format\":\"duration\"},\"bad\":{\"type\":\"boolean\"}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let rows = @carrier.relation(asof_rows(false))
  let c = @relation_join.check_asof(
    cursor(
      "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":{\"$param\":\"tol\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
    ),
    rows,
    rows,
    Some(parameters),
    limits(),
  ).unwrap()
  assert_true(
    @relation_join.asof_pending_validations(c).contains(BindTolerance("tol")),
  )
  assert_true(
    @relation_join.asof_tolerance(c)
    is @temporal.Parameter("tol", duration=true, ..),
  )
  assert_true(
    @relation_join.check_asof(
      cursor(
        "{\"with\":\"r\",\"kind\":\"left\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"time\",\"right_time\":\"time\",\"direction\":\"backward\",\"tolerance\":{\"$param\":\"bad\"},\"select\":{\"id\":\"left.id\",\"value\":\"right.time\"}}",
      ),
      rows,
      rows,
      Some(parameters),
      limits(),
    )
    is Err(_),
  )
}
