///|
fn analytic_countif_seed() -> @wire.Cursor {
  @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"flag":{"type":"boolean","nullable":true},"amount":{"type":"number","nullable":true}},"rows":[{"id":3,"flag":true,"amount":20},{"id":1,"flag":null,"amount":null},{"id":2,"flag":false,"amount":10}]},"as":"flags"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
}

///|
fn analytic_countif_context() -> Context {
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "flags", quoted: false, }],
        name: "flags",
        source: GeneratedValues(analytic_countif_seed()),
        visible_fields: ["id", "flag", "amount"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn analytic_countif_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"flag":{"type":"boolean","nullable":true},"amount":{"type":"number","nullable":true}},"rows":[{"id":3,"flag":true,"amount":20},{"id":1,"flag":null,"amount":null},{"id":2,"flag":false,"amount":10}]},"as":"flags"},{"from":"flags","analytic":{"partition_by":[],"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"functions":{"truthy":{"fn":"count_if","field":"flag"},"positive":{"fn":"count_if","expr":{"gt":[{"field":"amount"},{"literal":10}]}}},"frame":{"start":{"preceding":1},"end":{"following":1}}}},{"select":["id","truthy","positive"]},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","truthy","positive"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "analytic COUNTIF source matches the independent checked full Program" {
  let expected = analytic_countif_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent Values control requires no external inputs")
  }
  let frame = "ORDER BY id ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING"
  let projection = "id, COUNTIF(flag) OVER (" +
    frame +
    ") AS truthy, COUNTIF(amount > 10) OVER (" +
    frame +
    ") AS positive"
  for
    text in [
      "SELECT " + projection + " FROM flags ORDER BY id",
      "FROM flags |> SELECT " + projection + " |> ORDER BY id",
    ] {
    let generated = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      analytic_countif_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(generated), semantic(expected))
  }
}

///|
test "analytic COUNTIF retains explicit frame and input snapshot scope" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT COUNTIF(flag) OVER (ORDER BY id) AS n FROM flags",
        syntax_limits(),
      ).unwrap(),
      analytic_countif_context(),
      construction_limits(),
    )
    is Err(UnsupportedAnalytic),
  )
  for
    text in [
      "SELECT flag AS invented, COUNTIF(invented) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n FROM flags",
      "FROM flags AS old |> AS current |> SELECT COUNTIF(old.flag) OVER (ORDER BY id ROWS BETWEEN CURRENT ROW AND CURRENT ROW) AS n",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        analytic_countif_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: @expression.UnknownReference, .. })),
      msg=text,
    )
  }
}
