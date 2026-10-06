///|
test "step ranges partition retained occurrences including empty steps" {
  for n in [0, 1, 2, 17, 128] {
    let steps : Array[String] = []
    for i in 0..<n {
      steps.push(
        if i % 3 == 1 {
          "{\"join\":{\"with\":\"r\",\"kind\":\"semi\",\"on\":\"id\",\"max_output_rows\":7},\"from\":\"l\"}"
        } else {
          "{\"filter\":\"TRUE\",\"from\":\"l\"}"
        },
      )
    }
    let p = @pipeline_typing.check(
      cursor("[" + steps.join(",") + "]"),
      [("l", schema()), ("r", schema())],
      None,
      None,
      limits(),
    ).unwrap()
    let guards = @pipeline_typing.collect_author_guards(
      p,
      max_work=1000,
      max_text_bytes=10000,
    ).unwrap()
    let mut expected = 0
    for i in 0..<n {
      let first = expected
      if i % 3 == 1 {
        expected += 1
      }
      assert_eq(
        @pipeline_typing.author_guard_step_range(guards, i),
        Some((first, expected)),
      )
      for index in first..<expected {
        let occurrence = @pipeline_typing.author_guard_at(guards, index).unwrap()
        assert_eq(@pipeline_typing.author_guard_step(occurrence), i)
        assert_true(
          physical_equal(@pipeline_typing.author_guard_pipeline(occurrence), p),
        )
      }
    }
    assert_eq(@pipeline_typing.author_guard_count(guards), expected)
    assert_eq(@pipeline_typing.author_guard_step_range(guards, n), None)
    // One reserved unit for every step and every retained occurrence.
    assert_eq(@pipeline_typing.author_guards_usage(guards).0, n + expected)
  }
}

///|
test "author guards retain repeated owners exact source slots and shared budgets" {
  let parameters = @parameter.read_declarations(
    Some(cursor("{\"cap\":{\"type\":\"number\"}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let p = @pipeline_typing.check(
    cursor(
      (
        #|[{"join":{"with":"r","kind":"semi","on":"id","max_output_rows":{"$param":"cap"}},"from":"l"},
        #| {"join":{"with":"r","kind":"semi","on":"id","max_output_rows":7},"from":"l"},
        #| {"take":1}]
      ),
    ),
    [("l", schema()), ("r", schema())],
    Some(parameters),
    None,
    limits(),
  ).unwrap()
  let guards = @pipeline_typing.collect_author_guards(
    p,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.author_guard_count(guards), 2)
  assert_eq(@pipeline_typing.author_guard_step_range(guards, 0), Some((0, 1)))
  assert_eq(@pipeline_typing.author_guard_step_range(guards, 1), Some((1, 2)))
  assert_eq(@pipeline_typing.author_guard_step_range(guards, 2), Some((2, 2)))
  assert_eq(@pipeline_typing.author_guard_step_range(guards, -1), None)
  assert_eq(@pipeline_typing.author_guard_step_range(guards, 3), None)
  assert_true(
    physical_equal(@pipeline_typing.author_guards_pipeline(guards), p),
  )
  for i in 0..<2 {
    let occurrence = @pipeline_typing.author_guard_at(guards, i).unwrap()
    assert_eq(@pipeline_typing.author_guard_scope(occurrence), JoinOutputRows)
    assert_eq(
      @pipeline_typing.author_guard_field(occurrence),
      "max_output_rows",
    )
    assert_eq(@pipeline_typing.author_guard_unit(occurrence), @derivation.Rows)
    assert_eq(
      @law.name(@pipeline_typing.author_guard_law(occurrence)),
      "actql.guard.join-output",
    )
    assert_eq(@pipeline_typing.author_guard_step(occurrence), i)
    assert_true(
      physical_equal(@pipeline_typing.author_guard_pipeline(occurrence), p),
    )
    assert_eq(
      @decode.cursor_path(@pipeline_typing.author_guard_source(occurrence)),
      [Index(i), Key("join"), Key("max_output_rows")],
    )
  }
  assert_true(
    @pipeline_typing.author_guard_value(
      @pipeline_typing.author_guard_at(guards, 0).unwrap(),
    )
    is @relation.Parameter("cap"),
  )
  assert_true(
    @pipeline_typing.author_guard_value(
      @pipeline_typing.author_guard_at(guards, 1).unwrap(),
    )
    is @relation.Literal(7L),
  )
  assert_true(@pipeline_typing.author_guard_at(guards, -1) is None)
  assert_true(@pipeline_typing.author_guard_at(guards, 2) is None)
  let (work, text) = @pipeline_typing.author_guards_usage(guards)
  assert_true(
    @pipeline_typing.collect_author_guards(
      p,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.collect_author_guards(
      p,
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.collect_author_guards(
      p,
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.collect_author_guards(p, max_work=-1, max_text_bytes=text)
    is Err({ kind: InvalidLimits, .. }),
  )
}

///|
test "aggregate and sequence guards retain distinct protected quantities" {
  let p = @pipeline_typing.check(
    cursor(
      (
        #|[{"group":{"by":[],"aggregates":{"a":{"fn":"array_agg","field":"id","order_by":[{"id":"asc"}],"max_items":7},"b":{"fn":"string_agg","field":"id","order_by":[{"id":"asc"}],"delimiter":",","max_bytes":7}}}}]
      ),
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let guards = @pipeline_typing.collect_author_guards(
    p,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.author_guard_count(guards), 2)
  assert_eq(@pipeline_typing.author_guard_step_range(guards, 0), Some((0, 2)))
  assert_eq(
    @pipeline_typing.author_guard_scope(
      @pipeline_typing.author_guard_at(guards, 0).unwrap(),
    ),
    AggregateArrayItems(0),
  )
  assert_eq(
    @pipeline_typing.author_guard_scope(
      @pipeline_typing.author_guard_at(guards, 1).unwrap(),
    ),
    AggregateStringBytes(1),
  )
  let sequence = @pipeline_typing.check(
    cursor(
      (
        #|[{"sequence":{"by":[],"id":"id","time":"amount","pattern":[{"as":"a","where":"TRUE"},{"as":"b","where":"TRUE"}],"within":10,"overlap":"allow","contiguity":"adjacent","max_matches_per_key":7,"max_output_rows":7}}]
      ),
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let guards = @pipeline_typing.collect_author_guards(
    sequence,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.author_guard_count(guards), 2)
  assert_eq(
    @pipeline_typing.author_guard_scope(
      @pipeline_typing.author_guard_at(guards, 0).unwrap(),
    ),
    SequenceMatchesPerKey,
  )
  assert_eq(
    @pipeline_typing.author_guard_scope(
      @pipeline_typing.author_guard_at(guards, 1).unwrap(),
    ),
    SequenceOutputRows,
  )
}

///|
test "current TRAIL output guards exclude hop limits without fabricating unsupported guards" {
  let identity = "{\"definition\":\"N\",\"domain\":\"sha256:" +
    "0".repeat(64) +
    "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"traverse\":{\"start\":{\"ids\":[" +
      identity +
      "]},\"direction\":\"both\",\"min_hops\":0,\"max_hops\":3,\"path_mode\":\"trail\",\"emit\":\"paths\",\"max_output_rows\":7}}]",
    ),
    [("g", query_graph())],
    None,
    None,
    limits(),
  ).unwrap()
  let guards = @pipeline_typing.collect_author_guards(
    p,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.author_guard_count(guards), 1)
  assert_eq(@pipeline_typing.author_guard_step_range(guards, 0), Some((0, 1)))
  assert_true(
    physical_equal(@pipeline_typing.author_guards_pipeline(guards), p),
  )
  let occurrence = @pipeline_typing.author_guard_at(guards, 0).unwrap()
  assert_eq(@pipeline_typing.author_guard_scope(occurrence), TraverseOutputRows)
  assert_eq(@pipeline_typing.author_guard_field(occurrence), "max_output_rows")
  assert_true(
    @pipeline_typing.author_guard_value(occurrence) is @relation.Literal(7L),
  )
  assert_eq(
    @decode.cursor_path(@pipeline_typing.author_guard_source(occurrence)),
    [Index(0), Key("traverse"), Key("max_output_rows")],
  )
  let (work, text) = @pipeline_typing.author_guards_usage(guards)
  assert_true(
    @pipeline_typing.collect_author_guards(
      p,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.collect_author_guards(
      p,
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.collect_author_guards(
      p,
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
}

///|
test "binary and nested guards keep their scope instead of selecting a numeric minimum" {
  for
    (body, scope) in [
      (
        "\"cross_join\":{\"with\":\"r\",\"max_output_rows\":7}",
        @pipeline_typing.CrossJoinOutputRows,
      ),
      (
        "\"interval_join\":{\"with\":\"r\",\"kind\":\"inner\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"amount\"},\"right\":{\"start\":\"amount\",\"end\":\"amount\"},\"max_output_rows\":7}",
        @pipeline_typing.IntervalJoinOutputRows,
      ),
      (
        "\"nest\":{\"with\":\"r\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"],\"max_items\":7}",
        @pipeline_typing.NestedArrayItems,
      ),
    ] {
    let result = @pipeline_typing.check(
      cursor("[{" + body + ",\"from\":\"l\"}]"),
      [("l", schema()), ("r", schema())],
      None,
      None,
      limits(),
    )
    let p = match result {
      Ok(p) => p
      Err(e) => fail(@debug.to_string(e.kind))
    }
    let guards = @pipeline_typing.collect_author_guards(
      p,
      max_work=100,
      max_text_bytes=1000,
    ).unwrap()
    assert_eq(@pipeline_typing.author_guard_count(guards), 1)
    assert_eq(
      @pipeline_typing.author_guard_scope(
        @pipeline_typing.author_guard_at(guards, 0).unwrap(),
      ),
      scope,
    )
  }
}

///|
test "absent guards and empty pipelines consume no invented occurrences" {
  let empty = @pipeline_typing.check(
    cursor("[]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.author_guard_count(
      @pipeline_typing.collect_author_guards(
        empty,
        max_work=0,
        max_text_bytes=0,
      ).unwrap(),
    ),
    0,
  )
  let p = join_pipeline(
    "[{\"join\":{\"left\":\"l\",\"with\":\"r\",\"kind\":\"semi\",\"on\":\"id\"}}]",
  ).unwrap()
  assert_eq(
    @pipeline_typing.author_guard_count(
      @pipeline_typing.collect_author_guards(p, max_work=1, max_text_bytes=0).unwrap(),
    ),
    0,
  )
}
