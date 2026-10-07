///|
test "STRING_AGG omitted delimiter matches the independent comma Program" {
  let expected = @program.parse(
    "{\"version\":\"actql/0.1\",\"id\":\"fixture.pipe_slots\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[" +
    aggregate_property_order_seed() +
    (
      #|,{"from":"objects","derive":{"aql_aggregate_sort_5":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":[],"aggregates":{"names":{"fn":"string_agg","field":"name","max_bytes":10000,"order_by":[{"field":"aql_aggregate_sort_5","dir":"asc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"delimiter":","}}}},{"select":["names"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["names"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("the independent comma-delimited aggregate is closed")
  }
  for
    text in [
      "SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "SELECT STRING_AGG(name, ',' ORDER BY payload.score NULLS LAST, id) AS names FROM objects",
      "FROM objects |> AGGREGATE STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names",
    ] {
    let actual = checked_aggregate_property_order(text)
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}
