///|
fn sequence_rows(timestamp : Bool) -> @carrier.Knowledge {
  @carrier.rows(
    [
      (
        Unqualified("id"),
        Some(@contract.decimal_contract(12, 2, nullable=false).unwrap()),
      ),
      (
        Unqualified("clock"),
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
      (
        Unqualified("flag"),
        Some(@contract.primitive(BooleanType, nullable=true)),
      ),
      (
        Unqualified("group"),
        Some(@contract.primitive(StringType, nullable=false)),
      ),
      (Unqualified("unknown"), None),
    ],
    field_set=Open,
    max_fields=5,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "sequence symbolic guards and duration retain binding obligations" {
  let params = @parameter.read_declarations(
    Some(
      cursor(
        "{\"cap\":{\"type\":\"number\",\"default\":3},\"duration\":{\"type\":\"string\",\"format\":\"duration\",\"default\":\"1s\"}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let c = @relation_typing.check_sequence(
    cursor(
      "{\"by\":[],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"a\",\"where\":{\"literal\":true}},{\"as\":\"b\",\"where\":{\"literal\":false}}],\"within\":{\"$param\":\"duration\"},\"overlap\":\"disallow\",\"contiguity\":\"adjacent\",\"max_matches_per_key\":{\"$param\":\"cap\"},\"max_output_rows\":7}",
    ),
    @carrier.relation(sequence_rows(false)),
    Some(params),
    limits(),
  ).unwrap()
  assert_eq(@relation_typing.sequence_per_key_guard(c), Some(Parameter("cap")))
  assert_eq(@relation_typing.sequence_output_guard(c), Some(Literal(7L)))
  assert_true(
    indexed_obligation_copy(
      @relation_typing.sequence_obligations(c),
      @relation_typing.sequence_obligation_count(c),
      i => @relation_typing.sequence_obligation_at(c, i),
      (a, b) => a == b,
    ).contains(BindWithin("duration")),
  )
  assert_eq(
    indexed_obligation_copy(
      @relation_typing.sequence_pending_validations(c),
      @relation_typing.sequence_pending_validation_count(c),
      i => @relation_typing.sequence_pending_validation_at(c, i),
      (a, b) => a.kind == b.kind && physical_equal(a.source, b.source),
    ).map(p => p.kind),
    [BoundInteger(name="cap", minimum=1L)],
  )
}

///|
test "sequence supports Relation and Events without widening timestamp Events clocks" {
  for ts in [false, true] {
    for events in [false, true] {
      let rows = sequence_rows(ts)
      let input = if events {
        @carrier.events(rows, id=Unqualified("id"), time=Unqualified("clock")).unwrap()
      } else {
        @carrier.relation(rows)
      }
      let result = @relation_typing.check_sequence(
        cursor(
          "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
        ),
        input,
        None,
        limits(),
      )
      if ts && events {
        assert_true(result is Err({ kind: IncompatibleColumn("clock"), .. }))
        continue
      }
      let c = result.unwrap()
      assert_eq(@relation_typing.sequence_requires_timestamp_conversion(c), ts)
      assert_eq(@relation_typing.sequence_keys(c).length(), 2)
      let output = @relation_typing.sequence_output(c)
      assert_eq(@schema.field_count(output), 7)
      let id = @schema.lookup(output, Unqualified("opened_id")).unwrap()
      assert_true(
        @contract.type_equal(
          id,
          @contract.decimal_contract(12, 2, nullable=false).unwrap(),
          10,
        ),
      )
      for
        name in [
          "match_start_ms", "match_end_ms", "opened_time_ms", "closed_time_ms",
        ] {
        assert_true(
          @schema.lookup(output, Unqualified(name)).unwrap().shape
          is @contract.Number,
        )
      }
      assert_true(
        @relation_typing.sequence_within(c) is @temporal.Literal(1800000L),
      )
      assert_true(@relation_typing.sequence_per_key_guard(c) is None)
      assert_true(@relation_typing.sequence_output_guard(c) is None)
      assert_true(
        indexed_obligation_copy(
          @relation_typing.sequence_obligations(c),
          @relation_typing.sequence_obligation_count(c),
          i => @relation_typing.sequence_obligation_at(c, i),
          (a, b) => a == b,
        ).contains(AtomicMatchLimits),
      )
      assert_eq(@relation_typing.sequence_overlap(c), Disallow)
      assert_eq(@relation_typing.sequence_contiguity(c), Subsequence)
      let p = @relation_typing.sequence_pattern(c)
      assert_eq(p.map(p => p.label), ["opened", "closed"])
      assert_true(@typing.result_type(p[0].predicate).nullable)
      p.clear()
      assert_eq(@relation_typing.sequence_pattern(c).length(), 2)
    }
  }
}

///|
test "sequence global grouping and all overlap contiguity policies retain complete output" {
  let input = @carrier.relation(sequence_rows(false))
  for
    body in [
      "{\"by\":[],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"allow\",\"contiguity\":\"adjacent\"}",
      "{\"by\":[],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"adjacent\"}",
      "{\"by\":[],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
    ] {
    let c = @relation_typing.check_sequence(cursor(body), input, None, limits()).unwrap()
    assert_eq(@schema.field_count(@relation_typing.sequence_output(c)), 6)
    assert_eq(@relation_typing.sequence_keys(c).length(), 0)
  }
}

///|
test "sequence closes pattern syntax identity labels collisions and Boolean predicates" {
  let input = @carrier.relation(sequence_rows(false))
  for
    body in [
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"x\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"x\",\"where\":{\"literal\":true}},{\"as\":\"x\",\"where\":{\"literal\":false}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"\",\"where\":{\"literal\":true}},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"x.y\",\"where\":{\"literal\":true}},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"x\",\"where\":{\"literal\":1}},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"x\",\"where\":\"NULL\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"flag\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":0,\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\",\"max_matches_per_key\":0}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\",\"max_output_rows\":1.5}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"both\",\"contiguity\":\"subsequence\"}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":null}",
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\",\"extra\":true},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
    ] {
    assert_true(
      @relation_typing.check_sequence(cursor(body), input, None, limits())
      is Err(_),
    )
  }
  let colliding = @carrier.rows(
    [
      (Unqualified("id"), Some(@contract.primitive(NumberType, nullable=false))),
      (
        Unqualified("clock"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
      (
        Unqualified("match_start_ms"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
    ],
    field_set=Closed,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  assert_true(
    @relation_typing.check_sequence(
      cursor(
        "{\"by\":[\"match_start_ms\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"a\",\"where\":{\"literal\":true}},{\"as\":\"b\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
      ),
      @carrier.relation(colliding),
      None,
      limits(),
    )
    is Err({ kind: DuplicateOutput("match_start_ms"), .. }),
  )
}

///|
test "sequence expression source ranges and cumulative token budgets span all pattern slots" {
  let input = @carrier.relation(sequence_rows(false))
  let error = @relation_typing.check_sequence(
    cursor(
      "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"a\",\"where\":\"flag AND missing\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
    ),
    input,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(error.kind, UnknownField("missing"))
  assert_eq(error.path, [Key("pattern"), Index(0), Key("where")])
  assert_true(error.range is Some(_))
  let body = cursor(
    "{\"by\":[\"group\",\"group\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"flag\"},{\"as\":\"closed\",\"where\":{\"literal\":true}}],\"within\":\"30m\",\"overlap\":\"disallow\",\"contiguity\":\"subsequence\"}",
  )
  let c = @relation_typing.check_sequence(body, input, None, limits()).unwrap()
  let u = @relation_typing.sequence_usage(c)
  let exact : @relation_typing.Limits = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
    max_tokens: u.tokens,
  }
  assert_true(
    @relation_typing.check_sequence(body, input, None, exact) is Ok(_),
  )
  for
    small in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_tokens: u.tokens - 1, },
    ] {
    assert_true(
      @relation_typing.check_sequence(body, input, None, small) is Err(_),
    )
  }
}
