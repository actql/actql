///|
test "grouped implicit property names reuse the independent checked key Program" {
  let expected = independent_group_property_program()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ =>
      fail(
        "the independent property-key Program requires no new execution contract",
      )
  }
  for
    path in [
      "payload.score", "objects.payload.score", "`objects`.`payload`.`score`",
    ] {
    let actual = match
      compile(
        @query.parse_query(
          "SELECT " +
          path +
          ", COUNT(*) AS n FROM objects GROUP BY payload.score",
          syntax_limits(),
        ).unwrap(),
        group_property_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnknownColumn) =>
        fail("implicit naming rejects the evaluated grouping key: " + path)
      Err(_) => fail("grouped property source was rejected: " + path)
    }
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "grouped implicit property names preserve quoted spelling and evaluated keys" {
  let program = checked_group_property(
    "SELECT objects.payload.`SCORE`, COUNT(*) AS n FROM objects GROUP BY objects.payload.score ORDER BY `SCORE` NULLS LAST",
  )
  let body = semantic(program)
  assert_eq(body.split("\"property\":").length() - 1, 1)
  assert_true(body.contains("\"fields\":[\"SCORE\",\"n\"]"))
  assert_true(body.contains("\"field\":\"SCORE\",\"nulls\":\"last\""))
}

///|
test "grouped implicit property names pass the same naming snapshot to QUALIFY" {
  for
    source in [
      "SELECT id, payload.score, COUNT(*) AS n, ROW_NUMBER() OVER (ORDER BY id) AS rank FROM objects GROUP BY id, payload.score QUALIFY score > 10 AND rank > 0 ORDER BY id",
      "SELECT l.id, l.payload.score, COUNT(*) AS n, ROW_NUMBER() OVER (ORDER BY l.id) AS rank FROM objects AS l JOIN objects AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 GROUP BY l.id, l.payload.score QUALIFY score > 10 AND rank > 0 ORDER BY id",
    ] {
    let program = match
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(UnknownColumn) =>
        fail("QUALIFY cannot name the original property path: " + source)
      Err(AmbiguousColumn) =>
        fail("QUALIFY confuses qualified receiver columns: " + source)
      Err(UnsupportedAnalytic) =>
        fail("QUALIFY analytic input is unavailable: " + source)
      Err(_) => fail("QUALIFY source was rejected: " + source)
    }
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ => fail("the grouped analytic control uses ordinary checked inputs")
    }
    let body = semantic(program)
    assert_eq(body.split("\"property\":").length() - 1, 1)
    assert_true(body.contains("\"fields\":[\"id\",\"score\",\"n\",\"rank\"]"))
  }
}

///|
test "grouped implicit property names retain CTE and JOIN input scopes" {
  for
    source in [
      "WITH summary AS (SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score) SELECT score, n FROM summary ORDER BY score",
      "SELECT l.payload.score, COUNT(*) AS n FROM objects AS l JOIN objects AS r ON l.id = r.id MAX_OUTPUT_ROWS 10 GROUP BY l.payload.score ORDER BY score",
    ] {
    let program = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(
        program,
        check_environment(numeric=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      _ =>
        fail("grouped implicit properties retain their existing producer scope")
    }
    assert_eq(semantic(program).split("\"property\":").length() - 1, 1)
  }
}

///|
test "grouped implicit property names cannot restore ungrouped receivers or suffixes" {
  for
    source in [
      "SELECT payload.score, COUNT(*) AS n FROM objects GROUP BY payload.score + 1",
      "SELECT other.score, COUNT(*) AS n FROM objects GROUP BY payload.score", "SELECT payload, COUNT(*) AS n FROM objects GROUP BY payload.score",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=source,
    )
  }
  for
    source in [
      "SELECT missing.score, COUNT(*) AS n FROM objects GROUP BY payload.score",
      "SELECT objects.payload.score, COUNT(*) AS n FROM objects AS `current` GROUP BY current.payload.score",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        group_property_context(),
        construction_limits(),
      )
      is Err(
        Expression({ issue: @expression.UnknownReference, origin: Some(_), })
      ),
      msg=source,
    )
  }
}

///|
test "grouped implicit property names preserve duplicate outputs and common property checking" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT payload.score, other.score, COUNT(*) AS n FROM objects GROUP BY payload.score, other.score",
        syntax_limits(),
      ).unwrap(),
      group_property_context(),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
  for
    source in [
      "SELECT payload.missing, COUNT(*) AS n FROM objects GROUP BY payload.missing",
      "SELECT id.score, COUNT(*) AS n FROM objects GROUP BY id.score",
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      group_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg=source,
    )
  }
}
