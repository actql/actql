///|
test "SQL ROLLUP lowers complete prefixes of atomic grouping items" {
  let query = @query.parse_query(
    "SELECT x, y, COUNT(*) AS n FROM t WHERE y > 0 GROUP BY ROLLUP((x, y), x)",
    syntax_limits(),
  ).unwrap()
  let actual = compile(query, join_order_context(), construction_limits()).unwrap()
  match @check.check_parsed(actual, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("expected a checked Program using the existing group and append")
  }
  let body = semantic(actual)
  assert_eq(body.split("\"by\":[\"x\",\"y\"]").count(), 3)
  assert_eq(body.split("\"by\":[]").count(), 2)
  assert_false(body.contains("\"by\":[\"x\"]"))
  assert_eq(body.split("\"append\":").count(), 3)
}

///|
test "SQL ROLLUP retains nullable key contracts and original aggregate contracts" {
  let source = "WITH t AS (SELECT 'a' AS k, CAST(NULL AS STRING) AS s, 10 AS v UNION ALL SELECT 'a' AS k, 'x' AS s, 20 AS v UNION ALL SELECT 'b' AS k, 'x' AS s, 30 AS v) SELECT k, s, SUM(v) AS total, COUNT(*) AS n FROM t GROUP BY ROLLUP(k, s)"
  let actual = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(checked) => {
      let results = @check.checked_stage_results(checked)
      let stage = @stage_results.stage_at(
        results,
        @check.unit_count(checked) - 1,
      ).unwrap()
      let output = @relation_results.result_at(stage, 0).unwrap()
      let schema = @relation_results.output_schema(output)
      assert_eq(@schema.field_count(schema), 4)
      for name in ["k", "s", "total", "n"] {
        let field = @schema.lookup_reference(schema, name).unwrap()
        assert_eq(field.contract.nullable, name != "n", msg=name)
        if name == "k" || name == "s" {
          assert_true(field.contract.shape is @contract.Text(_), msg=name)
        } else {
          assert_true(field.contract.shape is @contract.Number, msg=name)
        }
      }
    }
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("expected the public ROLLUP query to be checked")
  }
}
