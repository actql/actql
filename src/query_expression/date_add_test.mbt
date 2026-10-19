///|
test "public DATE_ADD preserves ordered original temporal amount and unit children" {
  for name in ["DATE_ADD", "date_add", "DaTe_AdD", "`date_add`"] {
    assert_eq(
      emit(name + "(clock, @amount, ('s'))"),
      "{\"date_add\":[{\"field\":\"clock\"},{\"$param\":\"amount\"},{\"literal\":\"s\"}]}",
    )
    assert_eq(
      emit(name + "(CAST(NULL AS TIMESTAMP), 1, 'ms')"),
      "{\"date_add\":[{\"cast\":{\"target\":{\"type\":\"timestamp\"},\"value\":{\"literal\":null}}},{\"literal\":1},{\"literal\":\"ms\"}]}",
    )
  }
}

///|
test "public DATE_ADD refuses arity dynamic units and foreign namespaces" {
  for
    text in [
      "DATE_ADD(clock, 1)", "DATE_ADD(clock, 1, 's', 'ms')", "DATE_ADD(clock, 1, @unit)",
      "DATE_ADD(clock, 1, 'MS')", "DATE_ADD(clock, 1, 'month')", "DATE_ADD(clock, 1, NULL)",
      "DATE_ADD(clock, 1, 'm' || 's')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  assert_true(
    lower(
      fixture("ACTQL.DATE_ADD(clock, 1, 's')"),
      path => Some(path[0].value),
      limits(),
    )
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("DATE_ADD(clock, 1, 's')"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("DATE_ADD(clock, 1, 's')"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}
