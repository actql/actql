///|
test "empty-schema distinct and set operations retain conditional cardinality" {
  for n in [0, 1, 3] {
    let steps = [
      count_values(1, "initial"),
      "{\"group\":{\"by\":[],\"aggregates\":{}},\"as\":\"unit\"}",
    ]
    if n == 0 {
      steps.push("{\"take\":{\"count\":1,\"offset\":1}}")
    }
    if n == 3 {
      steps.push("{\"append\":{\"with\":\"unit\"}}")
      steps.push("{\"append\":{\"with\":\"unit\"}}")
    }
    steps.push("{\"derive\":{},\"as\":\"seed\"}")
    let i = steps.length() - 1
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        steps.join(",") +
        "," +
        "{\"distinct\":true},{\"intersect\":{\"with\":\"seed\",\"duplicates\":\"distinct\"}}," +
        "{\"except\":{\"with\":\"seed\",\"duplicates\":\"distinct\"}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, i, n.to_int64(), true)
    assert_count(p, i + 1, if n == 0 { 0L } else { 1L }, true)
    assert_count(p, i + 2, if n == 0 { 0L } else { 1L }, true)
    assert_count(p, i + 3, 0L, true)
  }
  let empty = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let p = @pipeline_typing.check(
    cursor(
      "[{\"distinct\":true},{\"intersect\":{\"with\":\"raw\",\"duplicates\":\"distinct\"}}]",
    ),
    [("raw", empty)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_count(p, 0, 1L, false)
  assert_count(p, 1, 1L, false)
}

///|
fn count_values(n : Int, binding : String) -> String {
  let rows = Array::makei(n, i => "{\"id\":" + i.to_string() + "}").join(",")
  "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
  rows +
  "]},\"as\":\"" +
  binding +
  "\"}"
}

///|
fn assert_count(
  p : @pipeline_typing.CheckedPipeline,
  i : Int,
  upper : Int64,
  exact : Bool,
) -> Unit raise {
  let c = @pipeline_typing.row_count(p, Step(i)).unwrap()
  assert_eq(c.upper, upper)
  assert_eq(c.exact, exact)
}

///|
test "row counts distinguish preservation reduction selection and global empty groups" {
  for n in [0, 3] {
    let prefix = count_values(n, "seed")
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        prefix +
        ",{\"derive\":{\"copy\":\"id\"}},{\"select\":[\"id\"]},{\"sort\":[]},{\"filter\":\"id > 0\"},{\"take\":{\"count\":2,\"offset\":1}},{\"group\":{\"by\":[],\"aggregates\":{}}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    for i in 0..<4 {
      assert_count(p, i, n.to_int64(), true)
    }
    assert_count(p, 4, n.to_int64(), n == 0)
    assert_count(p, 5, if n == 0 { 0L } else { 2L }, n == 0)
    assert_count(p, 6, 1L, true)
    assert_true(@pipeline_typing.row_count(p, Input(0)) is None)
    assert_true(@pipeline_typing.row_count(p, Step(-1)) is None)
    assert_true(@pipeline_typing.row_count(p, Step(7)) is None)
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[" +
        prefix +
        ",{\"take\":{\"count\":2,\"offset\":1}},{\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"id\":\"asc\"}]}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    assert_count(p, 1, if n == 0 { 0L } else { 2L }, true)
    assert_count(p, 2, if n == 0 { 0L } else { 1L }, true)
  }
}

///|
test "binary row counts preserve repeated operands and unknown is not zero" {
  let source = cursor(
    "[" +
    count_values(3, "seed") +
    ",{\"append\":{\"with\":\"seed\"}},{\"cross_join\":{\"with\":\"seed\",\"select\":{\"id\":\"left.id\"}}},{\"intersect\":{\"with\":\"seed\",\"duplicates\":\"all\"}}]",
  )
  let p = @pipeline_typing.check_carriers(source, [], None, None, limits()).unwrap()
  assert_count(p, 0, 3L, true)
  assert_count(p, 1, 6L, true)
  assert_count(p, 2, 18L, true)
  assert_count(p, 3, 3L, false)
  let u = @pipeline_typing.usage(p)
  let cap = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(
    @pipeline_typing.check_carriers(source, [], None, None, cap) is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_carriers(source, [], None, None, {
      ..cap,
      max_work: cap.max_work - 1,
    })
    is Err({ kind: BudgetExceeded, .. }),
  )
  let p = @pipeline_typing.check(
    cursor("[{\"filter\":\"amount > 0\"},{\"take\":2}]"),
    [("unknown_count", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.row_count(p, Step(0)) is None)
  assert_count(p, 1, 2L, false)
}

///|
test "row count expansion counts repeated columns and rejects safe integer overflow" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      count_values(3, "seed") +
      ",{\"unpivot\":{\"columns\":[\"id\",\"id\"],\"keep\":[],\"name_column\":\"name\",\"value_column\":\"value\"}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  assert_count(p, 1, 6L, true)
  let seed = "{\"time_series\":{\"start\":\"0000-01-01T00:00:00.000Z\",\"end\":\"9999-12-31T23:59:59.999Z\",\"step\":1},\"as\":\"grid\"}"
  let bad = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      seed +
      ",{\"cross_join\":{\"with\":\"grid\",\"select\":{\"time\":\"left.time\"}}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap_err()
  assert_eq(bad.kind, RowBoundOverflow)
  assert_eq(bad.path, [@source.Index(1)])
  let steps = [seed]
  for i in 0..<5 {
    let previous = if i == 0 { "grid" } else { "double" + (i - 1).to_string() }
    steps.push(
      "{\"append\":{\"with\":\"" +
      previous +
      "\"},\"as\":\"double" +
      i.to_string() +
      "\"}",
    )
  }
  assert_true(
    @pipeline_typing.check_carriers(
      cursor("[" + steps.join(",") + "]"),
      [],
      None,
      None,
      limits(),
    )
    is Err({ kind: RowBoundOverflow, .. }),
  )
}
