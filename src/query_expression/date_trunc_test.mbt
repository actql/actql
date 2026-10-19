///|
test "public DATE_TRUNC preserves the existing unit-first Common body" {
  for name in ["DATE_TRUNC", "date_trunc", "DaTe_TrUnC", "`date_trunc`"] {
    assert_eq(
      emit(name + "(clock, 'ms')"),
      "{\"date_trunc\":[{\"literal\":\"ms\"},{\"field\":\"clock\"}]}",
    )
    assert_eq(
      emit(name + "(@clock, ('d'))"),
      "{\"date_trunc\":[{\"literal\":\"d\"},{\"$param\":\"clock\"}]}",
    )
    assert_eq(
      emit(name + "(CAST(NULL AS TIMESTAMP), 's')"),
      "{\"date_trunc\":[{\"literal\":\"s\"},{\"cast\":{\"target\":{\"type\":\"timestamp\"},\"value\":{\"literal\":null}}}]}",
    )
  }
}

///|
test "public DATE_TRUNC refuses guessed order dynamic units and foreign namespaces" {
  for
    text in [
      "DATE_TRUNC(clock)", "DATE_TRUNC(clock, 's', 'ms')", "DATE_TRUNC('s', clock)",
      "DATE_TRUNC(clock, @unit)", "DATE_TRUNC(clock, 'MS')", "DATE_TRUNC(clock, 'month')",
      "DATE_TRUNC(clock, NULL)", "DATE_TRUNC(clock, 'm' || 's')",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
  assert_true(
    lower(
      fixture("ACTQL.DATE_TRUNC(clock, 'ms')"),
      path => Some(path[0].value),
      limits(),
    )
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("DATE_TRUNC(clock, 'ms')"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("DATE_TRUNC(clock, 'ms')"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}
