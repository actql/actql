///|
fn parenthesized_join_expected() -> @program.Program {
  // Authored from the ordinary Values, Stage reference and JOIN contracts.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_join_left","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":1,"y":20},{"x":2,"y":10}]},"as":"t"}],"results":{"aql_join_left":{"from":"t","fields":["x","y"]}}},{"id":"aql_join_right","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":1},{"k":2}]},"as":"r"}],"results":{"aql_join_right":{"from":"r","fields":["k"]}}},{"id":"main","inputs":{"l":{"result":{"stage":"aql_join_left","result":"aql_join_left"}},"r":{"result":{"stage":"aql_join_right","result":"aql_join_right"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"x","right":"k"}],"max_output_rows":10,"select":{"id":"left.x"}},"as":"aql_join_output"}],"results":{"rows":{"from":"aql_join_output","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "parenthesized JOIN keys match a complete independent specialized Program" {
  let expected = parenthesized_join_expected()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  for predicate in ["t.x=r.k", "(t.x)=((r.k))", "((r.k))=(t.x)"] {
    let query = @query.parse_query(
      "SELECT t.x AS id FROM t JOIN r ON " + predicate + " MAX_OUTPUT_ROWS 10",
      syntax_limits(),
    ).unwrap()
    let p = compile(query, join_order_context(), construction_limits()).unwrap()
    assert_eq(semantic(p), semantic(expected), msg=predicate)
  }
}

///|
test "shared Pipe CTE and scalar JOIN keys preserve grouping parentheses" {
  for
    (plain, grouped) in [
      (
        "SELECT l.id FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS id) r ON l.id=r.id MAX_OUTPUT_ROWS 10",
        "SELECT l.id FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS id) r ON (l.id)=((r.id)) MAX_OUTPUT_ROWS 10",
      ),
      (
        "WITH a AS (SELECT 1 AS id),b AS (SELECT 1 AS id) FROM a AS `L` |> JOIN b AS r ON `L`.id=r.id MAX_OUTPUT_ROWS 10 |> SELECT `L`.id",
        "WITH a AS (SELECT 1 AS id),b AS (SELECT 1 AS id) FROM a AS `L` |> JOIN b AS r ON ((`L`.id))=(r.id) MAX_OUTPUT_ROWS 10 |> SELECT `L`.id",
      ),
      (
        "SELECT l AS value FROM (FROM UNNEST([1,2]) old_l) l JOIN (FROM UNNEST([2,3]) old_r) r ON l=r MAX_OUTPUT_ROWS 10",
        "SELECT l AS value FROM (FROM UNNEST([1,2]) old_l) l JOIN (FROM UNNEST([2,3]) old_r) r ON ((l))=(r) MAX_OUTPUT_ROWS 10",
      ),
    ] {
    let a = row_on_query(plain).unwrap()
    let b = row_on_query(grouped).unwrap()
    assert_eq(semantic(b), semantic(a), msg=grouped)
    assert_true(
      @check.check_parsed(
        b,
        check_environment(numeric=true),
        None,
        check_limits(),
      )
      is Checked(_),
    )
  }
}

///|
test "grouped JOIN conjunctions retain both independent key pairs" {
  let query = @query.parse_query(
    "SELECT t.x FROM t JOIN r ON (((t.x)=(r.k)) AND ((r.k)=((t.y)))) MAX_OUTPUT_ROWS 10",
    syntax_limits(),
  ).unwrap()
  let p = compile(query, join_order_context(), construction_limits()).unwrap()
  assert_true(
    semantic(p).contains(
      "\"on\":[{\"left\":\"x\",\"right\":\"k\"},{\"left\":\"y\",\"right\":\"k\"}]",
    ),
  )
}

///|
test "parentheses do not turn arithmetic object or ordinary row keys into columns" {
  for
    source in [
      "SELECT l.id FROM (SELECT 1 AS l,2 AS id) l JOIN (SELECT 1 AS id) r ON (l)=(r.id) MAX_OUTPUT_ROWS 10",
      "SELECT l.id FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS r,2 AS id) r ON (l.id)=((r)) MAX_OUTPUT_ROWS 10",
      "SELECT l.id FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS id) r ON (l.id+1)=(r.id) MAX_OUTPUT_ROWS 10",
      "SELECT l.id FROM (SELECT 1 AS id) l JOIN (SELECT 1 AS id) r ON (+l.id)=(r.id) MAX_OUTPUT_ROWS 10",
    ] {
    assert_true(row_on_query(source) is Err(UnsupportedJoin), msg=source)
  }
}

///|
test "public nullable duplicate JOIN sources reach the ordinary checker" {
  let base = check_limits()
  // This public source lowers to more than the small fixture's 20 steps.
  let limits = {
    ..base,
    compilation: {
      ..base.compilation,
      structure: { ..base.compilation.structure, steps: 100, },
    },
  }
  let left = "SELECT 2 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 1 UNION ALL SELECT 2"
  let right = "SELECT 2 AS key,20 AS tag UNION ALL SELECT CAST(NULL AS FLOAT64),99 UNION ALL SELECT 2,21 UNION ALL SELECT 3,30"
  for
    source in [
      "SELECT l.id,r.tag FROM (" +
      left +
      ") l JOIN (" +
      right +
      ") r ON l.id=r.key MAX_OUTPUT_ROWS 10 ORDER BY tag,id",
      "SELECT l.id,r.tag FROM (" +
      left +
      ") l JOIN (" +
      right +
      ") r ON (l.id)=((r.key)) MAX_OUTPUT_ROWS 10 ORDER BY tag,id",
      "FROM (" +
      left +
      ") l |> JOIN (" +
      right +
      ") r ON (((l.id)=(r.key)) AND ((r.key)=((l.id)))) MAX_OUTPUT_ROWS 10 |> SELECT l.id,r.tag |> ORDER BY tag,id",
    ] {
    let p = row_on_query(source).unwrap()
    match
      @check.check_parsed(p, check_environment(numeric=true), None, limits) {
      Checked(_) => ()
      Rejected(issue) => {
        let cause = @check.diagnostic_cause(issue)
        match cause {
          Source(SourceView(Program(Program(Pipeline(_, error))))) =>
            fail(
              "pipeline refusal: " +
              @debug.to_string(error.kind) +
              "\n" +
              semantic(p),
            )
          _ => raise cause
        }
      }
      _ => fail("closed public source must reach ordinary checking")
    }
  }
}
