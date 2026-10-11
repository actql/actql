///|
fn tuple_unpivot_context() -> Context {
  let step = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"jan_amount":{"type":"number","nullable":true},"jan_note":{"type":"string","nullable":true},"feb_amount":{"type":"number","nullable":true},"feb_note":{"type":"string","nullable":true}},"rows":[{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"},{"id":1,"jan_amount":5,"jan_note":null,"feb_amount":null,"feb_note":"kept"},{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"}]},"as":"wide"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [{
      relation: [{ value: "wide", quoted: false, }],
      name: "wide",
      source: GeneratedValues(step),
      visible_fields: ["id", "jan_amount", "jan_note", "feb_amount", "feb_note"],
      graph_bindings: [],
    }],
  }
}

///|
fn independent_tuple_unpivot_program() -> @program.Program {
  // Authored from positional slot correspondence, never captured product output.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"jan_amount":{"type":"number","nullable":true},"jan_note":{"type":"string","nullable":true},"feb_amount":{"type":"number","nullable":true},"feb_note":{"type":"string","nullable":true}},"rows":[{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"},{"id":1,"jan_amount":5,"jan_note":null,"feb_amount":null,"feb_note":"kept"},{"id":2,"jan_amount":null,"jan_note":null,"feb_amount":7,"feb_note":"B"}]},"as":"wide"},{"from":"wide","derive":{"aql_unpivot_input_8":{"object":{"v0":{"field":"jan_amount"},"v1":{"field":"jan_note"}}},"aql_unpivot_input_9":{"object":{"v0":{"field":"feb_amount"},"v1":{"field":"feb_note"}}}}},{"select":["id","aql_unpivot_input_8","aql_unpivot_input_9"]},{"unpivot":{"columns":["aql_unpivot_input_8","aql_unpivot_input_9"],"keep":["id"],"name_column":"aql_unpivot_name_10","value_column":"aql_unpivot_value_11"}},{"derive":{"aql_unpivot_output_13":{"property":{"value":{"field":"aql_unpivot_value_11"},"name":"v0"}},"aql_unpivot_output_14":{"property":{"value":{"field":"aql_unpivot_value_11"},"name":"v1"}},"aql_unpivot_label_12":{"if":[{"eq":[{"field":"aql_unpivot_name_10"},{"literal":"aql_unpivot_input_8"}]},{"literal":"Jan"},{"literal":"Feb"}]}}},{"filter":{"or":[{"not":{"is_null":{"field":"aql_unpivot_output_13"}}},{"not":{"is_null":{"field":"aql_unpivot_output_14"}}}]}},{"sort":[{"field":"id","dir":"asc","nulls":"first"},{"field":"aql_unpivot_label_12","dir":"asc","nulls":"first"}]},{"select":["id",{"amount":"aql_unpivot_output_13"},{"note":"aql_unpivot_output_14"},{"month":"aql_unpivot_label_12"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["id","amount","note","month"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "multi-column source matches an independent complete ordinary Program" {
  let actual = compile(
    @query.parse_query(
      "FROM wide |> UNPIVOT ((amount,note) FOR month IN ((jan_amount,jan_note) AS 'Jan',(feb_amount,feb_note) AS 'Feb')) |> ORDER BY id,month",
      syntax_limits(),
    ).unwrap(),
    tuple_unpivot_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(independent_tuple_unpivot_program()))
  match @check.check_parsed(actual, check_environment(numeric=true), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the independently authored Values input is closed")
  }
}
