///|
fn assert_expired_select_range(source : String) -> Unit raise {
  let result = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  )
  assert_true(
    result is Err(Expression({ issue: @expression.UnknownReference, .. })) ||
    result is Err(UnknownColumn),
    msg=source,
  )
}

///|
fn assert_current_select_output(source : String) -> Unit raise {
  let result = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  )
  assert_true(result is Ok(_), msg=source)
  let program = result.unwrap()
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("Values inputs are closed")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
}

///|
test "SELECT range lifetime expires after an ordinary projection" {
  for projection in ["x", "x AS kept", "DISTINCT x"] {
    assert_expired_select_range(
      "FROM pair AS old |> SELECT " + projection + " |> WHERE old.x = 7",
    )
  }
}

///|
test "SELECT range lifetime expires even when identity star is elided" {
  assert_expired_select_range(
    "FROM pair AS old |> SELECT * |> WHERE old.x = 7 |> SELECT x",
  )
}

///|
test "SELECT range lifetime expires after expanded range stars" {
  for projection in ["old.*", "old.* EXCEPT (y)", "* REPLACE (x + 1 AS x)"] {
    assert_expired_select_range(
      "FROM pair AS old |> SELECT " + projection + " |> WHERE old.x = 7",
    )
  }
}

///|
test "SELECT range lifetime remains expired after its ORDER finishes" {
  for
    selection in [
      "SELECT x |> ORDER BY x", "SELECT x |> ORDER BY old.x", "SELECT x |> ORDER BY old.y",
      "SELECT * |> ORDER BY y", "SELECT old.* |> ORDER BY old.y", "SELECT DISTINCT x |> ORDER BY old.x",
    ] {
    assert_expired_select_range(
      "FROM pair AS old |> " + selection + " |> WHERE old.x = 7",
    )
  }
}

///|
test "SELECT range lifetime does not extend its input snapshot to a second ORDER" {
  for prefix in ["", " |> SET x = x"] {
    for projection in ["x", "*", "DISTINCT x"] {
      assert_expired_select_range(
        "FROM pair AS old" +
        prefix +
        " |> SELECT " +
        projection +
        " |> ORDER BY x |> ORDER BY old.x",
      )
      assert_current_select_output(
        "FROM pair AS old" +
        prefix +
        " |> SELECT " +
        projection +
        " |> ORDER BY x |> ORDER BY x",
      )
    }
  }
}

///|
test "SELECT range lifetime keeps LIMIT and RESULT in the materialized scope" {
  for projection in ["x", "*", "DISTINCT x"] {
    for intermediate in ["LIMIT 1", "RESULT prefix"] {
      assert_expired_select_range(
        "FROM pair AS old |> SELECT " +
        projection +
        " |> " +
        intermediate +
        " |> ORDER BY old.x",
      )
      assert_current_select_output(
        "FROM pair AS old |> SELECT " +
        projection +
        " |> " +
        intermediate +
        " |> ORDER BY x",
      )
    }
  }
}

///|
test "SELECT range lifetime applies to later scalar consumers" {
  for
    tail in [
      "SELECT old.x", "EXTEND old.x AS z |> SELECT z", "WHERE old.x = 7", "AGGREGATE COUNT(*) AS n GROUP BY old.x",
      "SELECT ROW_NUMBER() OVER (ORDER BY old.x) AS n", "LIMIT 1 |> WHERE old.x = 7",
      "RESULT prefix |> WHERE old.x = 7 |> RESULT answer",
    ] {
    assert_expired_select_range("FROM pair AS old |> SELECT x |> " + tail)
  }
}

///|
test "SELECT range lifetime keeps current output aliases and new AS ranges" {
  for
    source in [
      "FROM pair AS old |> SELECT x |> WHERE x = 7 |> SELECT x", "FROM pair AS old |> SELECT x AS kept |> WHERE kept = 7 |> SELECT kept",
      "FROM pair AS old |> SELECT * |> WHERE x = 7 |> SELECT x", "FROM pair AS old |> SELECT old.* |> WHERE x = 7 |> SELECT x",
      "FROM pair AS old |> SELECT x |> ORDER BY x |> WHERE x = 7 |> SELECT x", "FROM pair AS old |> SELECT x |> EXTEND x + 1 AS z |> SELECT z",
      "FROM pair AS old |> SELECT x |> AS old |> WHERE old.x = 7 |> SELECT old.x",
      "FROM pair AS old |> SELECT x |> AS current |> WHERE current.x = 7 |> SELECT current.x",
      "FROM pair AS old |> SELECT x |> RESULT prefix |> WHERE x = 7 |> RESULT answer",
      "FROM pair AS old |> SELECT x |> AGGREGATE COUNT(*) AS n GROUP BY x |> SELECT x, n",
    ] {
    assert_current_select_output(source)
  }
}

///|
test "SELECT range lifetime preserves the immediate query ORDER input snapshot" {
  for
    source in [
      "SELECT x FROM pair AS old ORDER BY old.y", "SELECT x FROM pair AS old ORDER BY old.x",
      "SELECT x AS kept FROM pair AS old ORDER BY old.x", "SELECT * FROM pair AS old ORDER BY y",
      "SELECT old.* FROM pair AS old ORDER BY old.y", "SELECT x FROM pair AS old ORDER BY y + 1",
      "SELECT x, COUNT(*) AS n FROM pair AS old GROUP BY x HAVING n > 0 ORDER BY old.x",
    ] {
    assert_current_select_output(source)
  }
}

///|
test "SELECT range lifetime permits a current Object column with the old range spelling" {
  for
    tail in [
      "WHERE old.score > 0 |> SELECT old", "ORDER BY old.score |> WHERE old.score > 0 |> SELECT old",
    ] {
    let program = compile(
      @query.parse_query(
        "FROM objects AS old |> SELECT payload AS old |> " + tail,
        syntax_limits(),
      ).unwrap(),
      order_property_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("Object Values inputs are closed")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
