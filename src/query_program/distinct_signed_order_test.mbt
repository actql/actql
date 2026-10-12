///|
fn distinct_signed_order_expected(key : String) -> @program.Program {
  @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    ",{\"from\":\"objects\",\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"derive\":{\"aql_aggregate_sort_5\":" +
    key +
    "}},{\"group\":{\"by\":[],\"aggregates\":{\"items\":{\"fn\":\"array_agg\",\"expr\":" +
    key +
    ",\"distinct\":true,\"max_items\":1000,\"order_by\":[{\"field\":\"aql_aggregate_sort_5\",\"dir\":\"desc\",\"nulls\":\"last\"}]}}}},{\"select\":[\"items\"],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"items\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "DISTINCT signed argument qualification preserves independent ordinary Program" {
  let expected = distinct_signed_order_expected(
    "{\"negate\":{\"field\":\"id\"}}",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    text in [
      "FROM objects |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(DISTINCT -id IGNORE NULLS ORDER BY -objects.id DESC) AS items",
      "FROM objects AS o |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(DISTINCT -o.id IGNORE NULLS ORDER BY -(`o`.`ID`) DESC) AS items",
      "FROM objects AS o |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(DISTINCT -id IGNORE NULLS ORDER BY -o.id DESC) AS items",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "DISTINCT signed property receivers retain equivalent static members" {
  let expected = distinct_signed_order_expected(
    "{\"negate\":{\"property\":{\"name\":\"score\",\"value\":{\"field\":\"payload\"}}}}",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for
    (argument, order) in [
      ("-payload.score", "-o.payload.score"),
      ("-(payload).score", "-o.payload.`SCORE`"),
      ("-o.payload.score", "-((payload)).score"),
    ] {
    let actual = compile(
      @query.parse_query(
        "FROM objects AS o |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(DISTINCT " +
        argument +
        " IGNORE NULLS ORDER BY " +
        order +
        " DESC) AS items",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "DISTINCT signed order still refuses different operators and input bindings" {
  for
    text in [
      "SELECT ARRAY_AGG(DISTINCT -id IGNORE NULLS ORDER BY +id) AS items FROM objects",
      "SELECT ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS ORDER BY -other.score) AS items FROM objects",
      "SELECT ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS ORDER BY -(-payload.score)) AS items FROM objects",
      "FROM objects AS old |> SET payload = other |> AGGREGATE ARRAY_AGG(DISTINCT -payload.score IGNORE NULLS ORDER BY -old.payload.score) AS items",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        aggregate_property_order_context(),
        construction_limits(),
      )
      is Err(UnsupportedAggregate),
      msg=text,
    )
  }
}

///|
test "DISTINCT signed order preserves the complete nested sign sequence" {
  for
    (argument, order, key) in [
      ("+id", "+o.id", "{\"negate\":{\"negate\":{\"field\":\"id\"}}}"),
      ("-(-id)", "-(-o.id)", "{\"negate\":{\"negate\":{\"field\":\"id\"}}}"),
    ] {
    let actual = compile(
      @query.parse_query(
        "FROM objects AS o |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(DISTINCT " +
        argument +
        " IGNORE NULLS ORDER BY " +
        order +
        " DESC) AS items",
        syntax_limits(),
      ).unwrap(),
      aggregate_property_order_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(distinct_signed_order_expected(key)))
  }
}

///|
test "DISTINCT signed order distinguishes a range field from an explicit object receiver" {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"score":{"type":"number","nullable":false},"payload":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":1,"score":10,"payload":{"score":20}}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context : Context = {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["id", "score", "payload"],
        graph_bindings: [],
      },
    ],
  }
  assert_true(
    compile(
      @query.parse_query(
        "FROM objects AS payload |> ASSERT UNIQUE BY (id) |> AGGREGATE ARRAY_AGG(DISTINCT -(payload.payload).score IGNORE NULLS ORDER BY -payload.score) AS items",
        syntax_limits(),
      ).unwrap(),
      context,
      construction_limits(),
    )
    is Err(UnsupportedAggregate),
  )
}
