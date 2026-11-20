///|
test "whole row output preserves anonymous values with local display keys" {
  for
    (source, key) in [
      ("WITH t AS (SELECT 1, 2 AS n) SELECT t AS row FROM t", "f0_"),
      ("WITH t AS (SELECT 1, 2 AS f0_) SELECT t AS row FROM t", "f0__"),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT IF(TRUE, t, t) AS row FROM t", "f0_",
      ),
    ] {
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["row"])
    assert_true(
      semantic(program).contains("\"" + key + "\":{\"field\":"),
      msg=source,
    )
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("the original Values row is closed")
    }
  }
}

///|
test "row wrappers and projected row values do not turn display keys into SQL members" {
  for
    expression in [
      "t.f0_", "(t).f0_", "IF(TRUE, t, t).f0_", "COALESCE(t, t).f0_", "[t][OFFSET(0)].f0_",
    ] {
    let source = "WITH t AS (SELECT 1, 2 AS n) SELECT " +
      expression +
      " AS value FROM t"
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn) => ()
      Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) =>
        assert_true(
          @origin.belongs_to(@query.script_document(script), origin),
          msg=source,
        )
      Err(_) => fail("wrong anonymous member refusal: " + source)
      Ok(_) => fail("a generated DATA key became a row member: " + source)
    }
  }
  let source = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT row.f0_ AS value FROM r"
  assert_true(
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(_), })
    ),
  )
}

///|
test "authored row fields and authored Object display-looking keys remain accessible" {
  for
    expression in [
      "t.n", "(t).n", "IF(TRUE, t, t).n", "COALESCE(t, t).n", "[t][OFFSET(0)].n",
    ] {
    let source = "WITH t AS (SELECT 1, 2 AS n) SELECT " +
      expression +
      " AS value FROM t"
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["value"])
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
  let program = anonymous_result_program(
    "WITH t AS (SELECT STRUCT(1 AS f0_) AS row) SELECT row.f0_ AS value FROM t",
  )
  assert_true(
    @check.check_parsed(program, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "row namespace survives joins and set type joins without hiding authored collisions" {
  for
    source in [
      "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t), u AS (SELECT 3 AS z) SELECT r.row.f0_ AS value FROM r CROSS JOIN u",
      "WITH a AS (SELECT 1), t AS (SELECT STRUCT(2 AS f0_) AS row UNION ALL SELECT a AS row FROM a) SELECT row.f0_ AS value FROM t",
      "WITH t AS (SELECT 1, 2 AS f0_) SELECT (t).f0__ AS value FROM t",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) =>
        assert_true(
          @origin.belongs_to(@query.script_document(script), origin),
          msg=source,
        )
      Err(_) => fail("wrong retained row namespace refusal: " + source)
      Ok(_) =>
        fail("a type join or JOIN manufactured an anonymous member: " + source)
    }
  }
  let named = anonymous_result_program(
    "WITH t AS (SELECT 1, 2 AS f0_) SELECT t.f0_ AS value FROM t",
  )
  assert_true(
    @check.check_parsed(named, check_environment(), None, check_limits())
    is Checked(_),
  )
  // The same original public row excludes the separately retained exact view.
  let numeric = anonymous_result_program(
    "WITH t AS (SELECT 5 AS v) SELECT MOD(v, 2) AS m, t AS row FROM t",
  )
  assert_true(
    @check.check_parsed(numeric, check_environment(), None, check_limits())
    is Checked(_),
  )
  assert_true(
    semantic(numeric).contains("\"object\":{\"v\":{\"field\":\"v\"}}"),
  )
}

///|
test "row namespace restrictions also apply to predicates ordering and original AS snapshots" {
  for
    source in [
      "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT row FROM r WHERE row.f0_ = 1",
      "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT row FROM r ORDER BY row.f0_",
      "WITH t AS (SELECT 1, 2 AS n) FROM t |> AS saved |> SET n = 3 |> SELECT (saved).f0_ AS value",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) =>
        assert_true(
          @origin.belongs_to(@query.script_document(script), origin),
          msg=source,
        )
      Err(_) => fail("wrong original row namespace refusal: " + source)
      Ok(_) => fail("another clause exposed an anonymous row member: " + source)
    }
  }
  let original = anonymous_result_program(
    "WITH t AS (SELECT 1, 2 AS n) FROM t |> AS saved |> SET n = 3 |> SELECT saved AS old",
  )
  assert_true(
    @check.check_parsed(original, check_environment(), None, check_limits())
    is Checked(_),
  )
  assert_true(semantic(original).contains("\"n\":{\"field\":\"n\"}"))
}

///|
test "pipeline edit targets require original SQL names rather than anonymous storage slots" {
  for
    operation in [
      "SET aql_set_anonymous_0 = 2", "RENAME aql_set_anonymous_0 AS visible",
    ] {
    let source = "WITH t AS (SELECT 1) FROM t |> " + operation
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn) => ()
      Err(_) => fail("expected the original unknown edit target: " + source)
      Ok(_) =>
        fail("an anonymous storage slot became an edit target: " + source)
    }
  }
  let authored = anonymous_result_program(
    "WITH t AS (SELECT 1, 2 AS aql_set_anonymous_0) FROM t |> SET aql_set_anonymous_0 = 3 |> RENAME aql_set_anonymous_0 AS named |> SELECT *",
  )
  assert_eq(anonymous_result_fields(authored), ["f0_", "named"])
  assert_true(
    @check.check_parsed(authored, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "row value namespace follows new SET EXTEND and RENAME slots while AS keeps its original" {
  let prefix = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) FROM r |> "
  for
    tail in [
      "EXTEND row AS carried |> SELECT carried.f0_ AS value", "SET row = COALESCE(row, row) |> SELECT row.f0_ AS value",
      "RENAME row AS renamed |> SELECT renamed.f0_ AS value", "RENAME row AS renamed |> SELECT r AS whole |> SELECT whole.renamed.f0_ AS value",
    ] {
    let source = prefix + tail
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(
        Expression(
          { issue: @expression.UnknownReference, origin: Some(origin), }
        )
      ) =>
        assert_true(
          @origin.belongs_to(@query.script_document(script), origin),
          msg=source,
        )
      Err(_) => fail("wrong derived row namespace refusal: " + source)
      Ok(_) => fail("a new slot lost its original row namespace: " + source)
    }
  }
  // The new object has an authored key; the saved row keeps its old value/role.
  let replaced = anonymous_result_program(
    prefix +
    "AS old |> SET row = STRUCT(3 AS f0_) |> SELECT row.f0_ AS named, old.row AS original",
  )
  assert_eq(anonymous_result_fields(replaced), ["named", "original"])
  assert_true(
    @check.check_parsed(replaced, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "a fresh AS row preserves a renamed value namespace through whole-row reentry" {
  let prefix = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) FROM r |> RENAME row AS renamed |> AS snapshot |> SELECT snapshot AS whole |> SELECT "
  let script = @query.parse_query_script(
    prefix + "whole.renamed.f0_ AS value",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(_), })
    ),
  )
  let named = anonymous_result_program(prefix + "whole.renamed.n AS named")
  assert_eq(anonymous_result_fields(named), ["named"])
  assert_true(
    @check.check_parsed(named, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "range star exclusions and replacement targets use original optional SQL names" {
  for
    source in [
      "WITH t AS (SELECT 1, 2 AS n) SELECT * EXCEPT (aql_set_anonymous_0) FROM t",
      "WITH t AS (SELECT 1, 2 AS n) SELECT t.* EXCEPT (aql_set_anonymous_0) FROM t",
      "WITH t AS (SELECT 1, 2 AS n) SELECT * REPLACE (3 AS aql_set_anonymous_0) FROM t",
      "WITH t AS (SELECT 1, 2 AS n) SELECT t.* REPLACE (3 AS aql_set_anonymous_0) FROM t",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnknownColumn),
      msg=source,
    )
  }
  for
    source in [
      "WITH t AS (SELECT 1, 2 AS n) SELECT * EXCEPT (n) FROM t", "WITH t AS (SELECT 1, 2 AS n) SELECT t.* EXCEPT (n) FROM t",
      "WITH t AS (SELECT 1, 2 AS aql_set_anonymous_0) SELECT * EXCEPT (aql_set_anonymous_0) FROM t",
    ] {
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["f0_"], msg=source)
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
}

///|
test "range star replacements preserve anonymous occurrences and their original namespace" {
  for
    (source, expected) in [
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT * REPLACE (3 AS n) FROM t",
        ["f0_", "n"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n, 4) SELECT t.* REPLACE (3 AS n) FROM t",
        ["f0_", "n", "f2_"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n, 4) SELECT 5 AS f1_, t.* REPLACE (3 AS n) FROM t",
        ["f1_", "f1__", "n", "f3_"],
      ),
      (
        "WITH a AS (SELECT 1, 2 AS n), t AS (SELECT a AS row, 3 AS z FROM a) SELECT * REPLACE (4 AS z) FROM t",
        ["row", "z"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT * REPLACE (3 AS n) FROM t GROUP BY 1",
        ["f0_", "n"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT * REPLACE (3 AS n) FROM t GROUP BY ALL",
        ["f0_", "n"],
      ),
    ] {
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), expected, msg=source)
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Checked(_),
      msg=source,
    )
  }
  for tail in ["ORDER BY aql_set_anonymous_0", "ORDER BY f0_"] {
    let source = "WITH t AS (SELECT 1, 2 AS n) SELECT * REPLACE (3 AS n) FROM t " +
      tail
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(
        Expression({ issue: @expression.UnknownReference, origin: Some(_), })
      ) => ()
      _ =>
        fail(
          "a copied anonymous star occurrence must not gain an ORDER alias: " +
          source,
        )
    }
  }
  let nested = "WITH a AS (SELECT 1, 2 AS n), t AS (SELECT a AS row, 3 AS z FROM a), r AS (SELECT * REPLACE (4 AS z) FROM t) SELECT row.f0_ AS value FROM r"
  let script = @query.parse_query_script(nested, syntax_limits()).unwrap()
  assert_true(
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(_), })
    ),
  )
}

///|
test "computed row stars retain anonymous roles order and nested row views" {
  for
    (source, fields) in [
      ("WITH t AS (SELECT 1, 2 AS n) SELECT (t).* FROM t", ["f0_", "n"]),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* FROM t GROUP BY 1, 2",
        ["f0_", "n"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* FROM t GROUP BY ALL",
        ["f0_", "n"],
      ),
      ("WITH t AS (SELECT 1, 2 AS f0_) SELECT (t).* FROM t", ["f0__", "f0_"]),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT IF(TRUE, t, t).* FROM t",
        ["f0_", "n"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT r.row.* FROM r",
        ["f0_", "n"],
      ),
      ("WITH t AS (SELECT 1, 2 AS n) SELECT (t).* EXCEPT(n) FROM t", ["f0_"]),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* REPLACE(3 AS n) FROM t",
        ["f0_", "n"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* FROM t GROUP BY 1, 2 ORDER BY n",
        ["f0_", "n"],
      ),
      (
        "WITH t AS (SELECT 1, 2 AS n) SELECT STRUCT(3 AS f0_) AS t FROM t ORDER BY t.f0_",
        ["t"],
      ),
    ] {
    let program = match
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(Expression({ issue: @expression.UnknownReference, .. })) =>
        fail("private member lost: " + source)
      Err(UnsupportedGrouping) => fail("group correspondence lost: " + source)
      Err(_) => fail("computed star compilation failed: " + source)
    }
    assert_eq(anonymous_result_fields(program), fields, msg=source)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("the original Values rows are closed")
    }
  }
}

///|
test "computed row stars never grant generated keys as SQL aliases" {
  for
    source in [
      "WITH t AS (SELECT 1, 2 AS n) SELECT (t).*, ((t).f0_) AS bad FROM t", "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT (r.row).*, ((r.row).f0_) AS bad FROM r",
      "WITH u AS (SELECT 1, 2 AS n), t AS (SELECT u AS nested, 3 AS z FROM u), s AS (SELECT (t).*, (t).nested AS saved FROM t) SELECT saved.f0_ FROM s",
      "WITH t AS (SELECT 1, 2 AS n) SELECT (t).*, ((t).f0_) AS bad FROM t GROUP BY 1, 2",
      "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* FROM t GROUP BY 1, 2 ORDER BY (t).f0_",
      "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* FROM t ORDER BY (t).f0_", "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* FROM t ORDER BY f0_",
      "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT (t).* FROM t) SELECT r.f0_ FROM r",
      "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* EXCEPT(f0_) FROM t", "WITH t AS (SELECT 1, 2 AS n) SELECT (t).* REPLACE(3 AS f0_) FROM t",
      "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT STRUCT(t AS nested) AS row FROM t), s AS (SELECT r.row.* FROM r) SELECT s.nested.f0_ FROM s",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(_) => fail("wrong generated object-star key refusal: " + source)
      Ok(_) => fail("generated Object key became a SQL name: " + source)
    }
  }
  let positive = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT STRUCT(t AS nested) AS row FROM t), s AS (SELECT r.row.* FROM r) SELECT s.nested.n AS n FROM s"
  assert_eq(anonymous_result_fields(anonymous_result_program(positive)), ["n"])
}

///|
test "computed row star receiver substitution retains authored sibling checks and nested views" {
  let source = "WITH t AS (SELECT 1, 2 AS n) SELECT (t).*, ((t).n) AS good FROM t"
  let program = anonymous_result_program(source)
  assert_eq(anonymous_result_fields(program), ["f0_", "n", "good"])
  assert_eq(
    semantic(program).split("\"derive\":{\"aql_computed_star_").length(),
    2,
  )
  let nested = "WITH u AS (SELECT 1, 2 AS n), t AS (SELECT u AS nested, 3 AS z FROM u), s AS (SELECT (t).*, (t).nested AS saved FROM t) SELECT saved.n AS value FROM s"
  let program = anonymous_result_program(nested)
  assert_eq(anonymous_result_fields(program), ["value"])
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the original Values rows remain closed")
  }
}

///|
test "window argument key and returned row namespaces reject anonymous DATA members" {
  let prefix = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) "
  for
    suffix in [
      "FROM r |> EXTEND LAG(row) OVER (ORDER BY row.n) AS previous |> SELECT previous.f0_",
      "SELECT COALESCE(row, row) AS renamed FROM r ORDER BY LAG(renamed.f0_) OVER (ORDER BY renamed.n)",
      "SELECT LAG(row.f0_) OVER (ORDER BY row.n) AS n FROM r", "SELECT LAG(row.n) OVER (PARTITION BY row.f0_ ORDER BY row.n) AS n FROM r",
      "SELECT LAG(row.n) OVER (ORDER BY row.f0_) AS n FROM r", ", s AS (SELECT LAG(row) OVER (ORDER BY row.n) AS previous FROM r) SELECT previous.f0_ FROM s",
      ", s AS (SELECT FIRST_VALUE(row) OVER (ORDER BY row.n ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS first FROM r) SELECT first.f0_ FROM s",
    ] {
    let source = prefix + suffix
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(_) => fail("wrong original window namespace refusal: " + source)
      Ok(_) => fail("window path promoted an anonymous DATA member: " + source)
    }
  }
}

///|
test "window navigation keeps original named members and row value types" {
  for
    call in [
      "LAG(row) OVER (ORDER BY row.n)", "LEAD(row, 0) OVER (ORDER BY row.n)", "FIRST_VALUE(row) OVER (ORDER BY row.n ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
      "LAST_VALUE(row) OVER (ORDER BY row.n ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)",
    ] {
    let source = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t), s AS (SELECT " +
      call +
      " AS chosen FROM r) SELECT chosen.n AS value FROM s"
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["value"], msg=source)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the authored row and existing window types remain closed")
    }
  }
  for
    source in [
      "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) SELECT COALESCE(row, row) AS renamed FROM r ORDER BY LAG(renamed.n) OVER (ORDER BY renamed.n)",
      "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) FROM r |> EXTEND LAG(row) OVER (ORDER BY row.n) AS previous |> SELECT previous.n AS value",
    ] {
    let program = anonymous_result_program(source)
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("existing ORDER aliases and EXTEND retain the original window row")
    }
  }
  let authored = "WITH t AS (SELECT STRUCT(1 AS f0_) AS row, 2 AS n), s AS (SELECT LAG(row) OVER (ORDER BY n) AS previous FROM t) SELECT previous.f0_ AS value FROM s"
  assert_eq(anonymous_result_fields(anonymous_result_program(authored)), [
    "value",
  ])
}

///|
test "window reused output slots replace retired row namespaces" {
  for
    source in [
      "WITH u AS (SELECT 1, 2 AS n), t AS (SELECT u AS value, 3 AS key FROM u), s AS (FROM t |> DROP value |> SELECT LAG(STRUCT(7 AS f0_)) OVER (ORDER BY key) AS value) SELECT value.f0_ AS result FROM s",
      "WITH a AS (SELECT 1, 2 AS n), b AS (SELECT 3, 4 AS m), t AS (SELECT a AS row, b AS other FROM a CROSS JOIN b), s AS (FROM t |> DROP row |> SELECT LAG(other) OVER (ORDER BY other.m) AS row) SELECT row.m AS result FROM s",
    ] {
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    let program = match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Ok(program) => program
      Err(_) =>
        fail(
          "a retired namespace masked a new original window value: " + source,
        )
    }
    assert_eq(anonymous_result_fields(program), ["result"])
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the replacement window value has a closed original type")
    }
  }
}

///|
test "group aggregate arguments filter ordering and row elements keep original namespaces" {
  let prefix = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) "
  for
    suffix in [
      "SELECT COUNT(row.f0_) AS n FROM r", "SELECT COUNT(* WHERE row.f0_ > 0) AS n FROM r",
      "SELECT ARRAY_AGG(row.n ORDER BY row.f0_) AS items FROM r", ", s AS (SELECT ARRAY_AGG(row ORDER BY row.n) AS items FROM r) SELECT items[OFFSET(0)].f0_ AS value FROM s",
    ] {
    let source = prefix + suffix
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    match
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ) {
      Err(UnknownColumn)
      | Err(Expression({ issue: @expression.UnknownReference, .. })) => ()
      Err(_) => fail("wrong original aggregate namespace refusal: " + source)
      Ok(_) =>
        fail("aggregate path promoted an anonymous DATA member: " + source)
    }
  }
}

///|
test "group aggregate named members and row arrays retain their original types" {
  let prefix = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row FROM t) "
  let counted = anonymous_result_program(
    prefix + "SELECT COUNT(row.n WHERE row.n > 0) AS n FROM r",
  )
  assert_eq(anonymous_result_fields(counted), ["n"])
  match
    @check.check_parsed(
      counted,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) =>
      fail("the existing numeric fixture supplies the named comparison")
  }
  for output in ["items", "row"] {
    let source = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row, n AS sort_key FROM t), keyed AS (FROM r |> ASSERT UNIQUE BY (sort_key)), s AS (SELECT ARRAY_AGG(row ORDER BY sort_key) AS " +
      output +
      " FROM keyed) SELECT " +
      output +
      "[OFFSET(0)].n AS value FROM s"
    let program = anonymous_result_program(source)
    assert_eq(anonymous_result_fields(program), ["value"])
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the explicit original key and bounded row array remain closed")
    }
  }
}

///|
test "Pipe aggregate select projects the actual array namespace to its output name" {
  let prefix = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row, n AS sort_key FROM t), keyed AS (FROM r |> ASSERT UNIQUE BY (sort_key)) FROM keyed |> AGGREGATE ARRAY_AGG(row ORDER BY sort_key) AS row |> SELECT "
  let source = prefix + "row[OFFSET(0)].f0_ AS bad"
  let script = @query.parse_query_script(source, syntax_limits()).unwrap()
  match
    compile_query_script(
      script,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ) {
    Err(UnknownColumn) => ()
    Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(origin), })
    ) => assert_true(@origin.belongs_to(@query.script_document(script), origin))
    Err(_) => fail("wrong original Pipe array member refusal")
    Ok(_) => fail("Pipe select dropped the actual Array row namespace")
  }
  let program = anonymous_result_program(prefix + "row[OFFSET(0)].n AS value")
  assert_eq(anonymous_result_fields(program), ["value"])
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) =>
      fail("same original asserted key and row array remain closed")
  }
}

///|
test "Pipe aggregate namespace projection preserves named keys and scalar siblings" {
  let source = "WITH t AS (SELECT 1, 2 AS n), r AS (SELECT t AS row, n AS sort_key FROM t), keyed AS (FROM r |> ASSERT UNIQUE BY (sort_key)) FROM keyed |> AGGREGATE ARRAY_AGG(row ORDER BY sort_key) AS row, COUNT(*) + 0 AS count GROUP BY sort_key |> SELECT row[OFFSET(0)].n AS value, sort_key, count"
  let program = anonymous_result_program(source)
  assert_eq(anonymous_result_fields(program), ["value", "sort_key", "count"])
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) =>
      fail("the existing key scalar and row array fixtures remain closed")
  }
}
