///|
test "PIVOT projection identity independent existing Program checks" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pivot_projection_identity","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"value":{"type":"number","nullable":false},"twin":{"type":"number","nullable":false},"axis":{"type":"string","nullable":false}},"rows":[{"value":1,"twin":1,"axis":"A"},{"value":1,"twin":1,"axis":"A"},{"value":2,"twin":2,"axis":"A"}]},"as":"rows"},{"from":"rows","pivot":{"index":["twin"],"column":"axis","value":"value","values":["A"],"aggregate":"sum"}},{"sort":[{"field":"twin","dir":"asc","nulls":"first"}],"as":"out"}],"results":{"rows":{"from":"out","fields":["twin","A"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      expected,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed independent PIVOT")
  }
}

///|
test "PIVOT consumes one selected column without consuming its equal-valued sibling" {
  let query = @query.parse_query(
    "(SELECT 1 AS amount,'A' AS axis UNION ALL SELECT 1,'A' UNION ALL SELECT 2,'A') |> SELECT amount AS value,amount AS twin,axis |> PIVOT(SUM(value) FOR axis IN('A')) |> ORDER BY twin",
    syntax_limits(),
  ).unwrap()
  let actual = match
    compile(query, { ..values_context(), inputs: [], }, construction_limits()) {
    Ok(program) => program
    Err(UnknownColumn) => fail("retained twin was dropped from PIVOT grouping")
    Err(_) => fail("unexpected PIVOT projection-identity refusal")
  }
  match
    @check.check_parsed(
      actual,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed PIVOT projection identity")
  }
}
