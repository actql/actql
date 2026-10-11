///|
// Independently authored ordinary Program control, separate from source lowering.
test "multi-column UNPIVOT has an ordinary closed-object control" {
  let program = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.multi_column_unpivot","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"jan_amount":{"type":"number","nullable":true},"jan_note":{"type":"string","nullable":true},"feb_amount":{"type":"number","nullable":true},"feb_note":{"type":"string","nullable":true}},"rows":[{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"},{"id":1,"jan_amount":5,"jan_note":null,"feb_amount":null,"feb_note":"kept"},{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"}]},"as":"wide"},{"from":"wide","derive":{"private_jan":{"object":{"amount":{"field":"jan_amount"},"note":{"field":"jan_note"}}},"private_feb":{"object":{"amount":{"field":"feb_amount"},"note":{"field":"feb_note"}}}}},{"select":["id","private_jan","private_feb"]},{"unpivot":{"columns":["private_jan","private_feb"],"keep":["id"],"name_column":"private_name","value_column":"private_bundle"}},{"derive":{"amount":{"property":{"value":{"field":"private_bundle"},"name":"amount"}},"note":{"property":{"value":{"field":"private_bundle"},"name":"note"}},"month":{"if":[{"eq":[{"field":"private_name"},{"literal":"private_jan"}]},{"literal":"Jan"},{"literal":"Feb"}]}}},{"filter":{"or":[{"not":{"is_null":{"field":"amount"}}},{"not":{"is_null":{"field":"note"}}}]}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"month","dir":"asc","nulls":"first"}]},{"select":["id","amount","note","month"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","amount","note","month"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(
      program,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the authored Values control is closed")
  }
}
