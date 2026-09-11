///|
test "normalized parameter occurrences distinguish repeated text references and literal data" {
  let e = admit(text_cursor("$p + $p"), test_limits()).unwrap()
  let refs = collect_parameter_occurrences(e, max_work=100).unwrap()
  assert_eq(parameter_occurrence_count(refs), 2)
  assert_true(physical_equal(parameter_occurrence_expression(refs), e))
  for i in 0..<2 {
    let r = parameter_occurrence_at(refs, i).unwrap()
    assert_eq(r.name, "p")
    assert_eq(@decode.cursor_path(r.cursor), [
      @source.Key("add"),
      @source.Index(i),
    ])
    let at = origin(e, r.cursor).unwrap()
    assert_eq(location_path(at), [])
    assert_true(at.range is Some(_))
  }
  assert_true(parameter_occurrence_at(refs, -1) is None)
  assert_true(parameter_occurrence_at(refs, 2) is None)
  let mixed = admit(
    source_cursor(
      "{\"object\":{\"a/~\":\"$p + $q\",\"data\":{\"literal\":{\"$param\":\"hidden\",\"meta\":{\"$param\":\"also_hidden\"}}},\"member\":{\"in\":[{\"field\":\"x\"},{\"literal\":[null,1,{\"$param\":\"needle\"}]}]}}}",
    ),
    test_limits(),
  ).unwrap()
  let refs = collect_parameter_occurrences(mixed, max_work=100).unwrap()
  assert_eq(parameter_occurrence_count(refs), 3)
  assert_eq(parameter_occurrence_at(refs, 0).unwrap().name, "p")
  assert_eq(parameter_occurrence_at(refs, 1).unwrap().name, "q")
  let r = parameter_occurrence_at(refs, 2).unwrap()
  assert_eq(r.name, "needle")
  assert_eq(@decode.cursor_path(r.cursor), [
    @source.Key("object"),
    @source.Key("member"),
    @source.Key("in"),
    @source.Index(1),
    @source.Key("literal"),
    @source.Index(2),
  ])
  let cost = parameter_occurrence_work(refs)
  assert_true(collect_parameter_occurrences(mixed, max_work=cost) is Ok(_))
  assert_true(
    collect_parameter_occurrences(mixed, max_work=cost - 1)
    is Err({ kind: BudgetExceeded, .. }),
  )
  assert_true(
    collect_parameter_occurrences(mixed, max_work=-1)
    is Err({ kind: InvalidLimits, .. }),
  )
}

///|
test "normalized parameter traversal follows named bodies branches and cast rewrites" {
  for
    text in [
      "to_number($p)", "CASE WHEN $condition THEN $yes ELSE $no END", "regex_extract($input, $pattern, $capture, 'm')",
      "[$a, coalesce($b, $c)]", "x NOT IN ($first, NULL, $last)",
    ] {
    let expression = admit(text_cursor(text), test_limits()).unwrap()
    let refs = collect_parameter_occurrences(expression, max_work=100).unwrap()
    let expected = parameter_references(expression)
    assert_eq(parameter_occurrence_count(refs), expected.length())
    for i in 0..<expected.length() {
      let r = parameter_occurrence_at(refs, i).unwrap()
      assert_eq(r.name, expected[i].name)
      assert_true(origin(expression, r.cursor) is Some(_))
    }
  }
  let expression = admit(text_cursor("to_number($p)"), test_limits()).unwrap()
  let refs = collect_parameter_occurrences(expression, max_work=100).unwrap()
  assert_eq(
    @decode.cursor_path(parameter_occurrence_at(refs, 0).unwrap().cursor),
    [@source.Key("cast"), @source.Key("value")],
  )
  for
    source in [
      (
        #|{"template":"{field}: $hidden"}
      ),
      (
        #|{"empty_array":{"items":{"type":"object","nullable":false,"fields":{"$hidden":{"type":"string","nullable":false}}}}}
      ),
    ] {
    let expression = admit(source_cursor(source), test_limits()).unwrap()
    let refs = collect_parameter_occurrences(expression, max_work=100).unwrap()
    assert_eq(parameter_occurrence_count(refs), 0)
  }
}

///|
test "normalized parameter traversal is nonrecursive and skips opaque literal width" {
  let e = admit(text_cursor("not ".repeat(10000) + "$p"), test_limits()).unwrap()
  let refs = collect_parameter_occurrences(e, max_work=10001).unwrap()
  assert_eq(parameter_occurrence_count(refs), 1)
  assert_eq(parameter_occurrence_work(refs), 10001)
  assert_eq(
    @decode.cursor_path(parameter_occurrence_at(refs, 0).unwrap().cursor).length(),
    10000,
  )
  let data = admit(
    source_cursor(
      "{\"literal\":[" +
      Array::make(10000, "{\"$param\":\"hidden\"}").join(",") +
      "]}",
    ),
    test_limits(),
  ).unwrap()
  let refs = collect_parameter_occurrences(data, max_work=2).unwrap()
  assert_eq(parameter_occurrence_count(refs), 0)
  assert_eq(parameter_occurrence_work(refs), 2)
}
