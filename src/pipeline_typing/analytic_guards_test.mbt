///|
test "analytic aggregate guards retain call indices laws and exact source slots" {
  let d = guard_declarations()
  let p = @pipeline_typing.check(
    cursor(
      (
        #|[{"analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"frame":{"start":"current_row","end":"current_row"},"functions":{
        #|"a_rank":{"fn":"rank"},
        #|"b_items":{"fn":"array_agg","expr":"id","max_items":{"$param":"cap"}},
        #|"c_bytes":{"fn":"string_agg","expr":"id","delimiter":",","max_bytes":7},
        #|"d_lag":{"fn":"lag","expr":"id","offset":7}}}}]
      ),
    ),
    [("rows", schema())],
    Some(d),
    None,
    limits(),
  ).unwrap()
  let occurrences = @pipeline_typing.collect_author_guards(
    p,
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.author_guard_count(occurrences), 2)
  for
    (i, name, field, scope) in [
      (0, "b_items", "max_items", @pipeline_typing.AggregateArrayItems(1)),
      (1, "c_bytes", "max_bytes", @pipeline_typing.AggregateStringBytes(2)),
    ] {
    let occurrence = @pipeline_typing.author_guard_at(occurrences, i).unwrap()
    assert_eq(@pipeline_typing.author_guard_scope(occurrence), scope)
    assert_eq(@pipeline_typing.author_guard_field(occurrence), field)
    assert_eq(
      @decode.cursor_path(@pipeline_typing.author_guard_source(occurrence)),
      [Index(0), Key("analytic"), Key("functions"), Key(name), Key(field)],
    )
  }
  let bounds = @pipeline_typing.bind_author_guards(
    occurrences,
    Some(guard_bindings(d, None)),
    max_work=100,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.bound_guard_value_at(bounds, 0), Some(7L))
  assert_eq(@pipeline_typing.bound_guard_value_at(bounds, 1), Some(7L))
  let error = @pipeline_typing.bind_author_guards(
    occurrences,
    Some(guard_bindings(d, Some("{\"cap\":0}"))),
    max_work=100,
    max_text_bytes=1000,
  ).unwrap_err()
  assert_eq(error.kind, InvalidGuardValue("cap"))
  assert_eq(error.path, [
    Index(0),
    Key("analytic"),
    Key("functions"),
    Key("b_items"),
    Key("max_items"),
  ])
  let (work, text) = @pipeline_typing.author_guards_usage(occurrences)
  assert_eq(work, 7)
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
  guard @pipeline_typing.step_at(p, 0).unwrap().operation is Unary(op) else {
    fail("expected unary")
  }
  let analytic = @relation.analytic(op).unwrap()
  assert_eq(@relation.analytic_call_count(analytic), 4)
  assert_true(@relation.analytic_call_at(analytic, -1) is None)
  assert_true(@relation.analytic_call_at(analytic, 4) is None)
  let copy = @relation.analytic_calls(analytic)
  copy.clear()
  assert_eq(@relation.analytic_call_count(analytic), 4)
}

///|
test "analytic aggregates without authored guards do not acquire frame-size guards" {
  let p = @pipeline_typing.check(
    cursor(
      (
        #|[{"analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"frame":{"start":{"preceding":7},"end":"current_row"},"functions":{"a":{"fn":"array_agg","expr":"id"},"b":{"fn":"string_agg","expr":"id","delimiter":","}}}}]
      ),
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.author_guard_count(
      @pipeline_typing.collect_author_guards(p, max_work=3, max_text_bytes=0).unwrap(),
    ),
    0,
  )
}
