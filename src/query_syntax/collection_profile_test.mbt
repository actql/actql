///|
test "ordered ARRAY_AGG accepts the documented omitted NULL modifier without changing its argument or order" {
  for
    call in [
      "ARRAY_AGG(id ORDER BY id)", "ARRAY_AGG(id IGNORE NULLS ORDER BY id)",
    ] {
    let parsed = parse_query(
      "SELECT " + call + " AS ids FROM records",
      query_limits(),
    ).unwrap()
    guard operation_at(parsed, 0) is Some(Group(_, projections, _)) else {
      fail("expected original aggregate")
    }
    let aggregate = projections[0].aggregate.unwrap()
    assert_eq(aggregate.function_name, "ARRAY_AGG")
    assert_eq(aggregate.order_by.length(), 1)
    assert_true(aggregate.argument is Some(_))
  }
}

///|
test "ordinary collection calls name their existing explicit order requirement" {
  for
    call in [
      "STRING_AGG(name, ',')", "ARRAY_AGG(id)", "ARRAY_AGG(id IGNORE NULLS)", "ARRAY_AGG(id WHERE amount > 0)",
      "ARRAY_AGG(id IGNORE NULLS WHERE amount > 0)",
    ] {
    assert_true(
      parse_query("SELECT " + call + " AS items FROM records", query_limits())
      is Err({ issue: AggregateOrderRequired, span: Some(span), }) &&
      span.start_byte == 7 &&
      span.end_byte == 7,
    )
  }
}
