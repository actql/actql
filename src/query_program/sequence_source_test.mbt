///|
fn sequence_source_text() -> String {
  "WITH events AS (SELECT 1 AS id, 0 AS occurred_ms, 1 AS kind UNION ALL SELECT 2, 10, 2), matches AS (FROM events AS e |> sequence(by: [], id: e.id, time: e.occurred_ms, pattern: [{as: first, where: e.kind = 1}, {as: second, where: e.kind = 2}], within: 20, overlap: 'disallow', contiguity: 'adjacent', max_matches_per_key: 2, max_output_rows: 2)) SELECT first_id, first_time_ms, match_end_ms, match_start_ms, second_id, second_time_ms FROM matches ORDER BY first_id"
}

///|
fn sequence_source_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.sequence_source","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"occurred_ms":{"type":"number","nullable":false},"kind":{"type":"number","nullable":false}},"rows":[{"id":1,"occurred_ms":0,"kind":1},{"id":2,"occurred_ms":10,"kind":2}]},"as":"events"},{"from":"events","sequence":{"by":[],"id":"id","time":"occurred_ms","pattern":[{"as":"first","where":{"eq":[{"field":"kind"},{"literal":1}]}},{"as":"second","where":{"eq":[{"field":"kind"},{"literal":2}]}}],"within":20,"overlap":"disallow","contiguity":"adjacent","max_matches_per_key":2,"max_output_rows":2},"as":"matches"},{"from":"matches","sort":[{"field":"first_id","dir":"asc","nulls":"first"}]},{"select":["first_id","first_time_ms","match_end_ms","match_start_ms","second_id","second_time_ms"],"as":"out"}],"results":{"rows":{"from":"out","fields":["first_id","first_time_ms","match_end_ms","match_start_ms","second_id","second_time_ms"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "sequence predicate AST reaches the unchanged common operation body" {
  let control=sequence_source_control()
  match @check.check_parsed(control,graph_event_environment(),None,check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("closed sequence control")
  }
  let actual=@frontend.lower(sequence_source_text(),Sql,Some({..pair_context(),inputs:[]})).unwrap().program.unwrap()
  assert_eq(with_carrier_argument(actual,"sequence"),with_carrier_argument(control,"sequence"))
  match @check.check_parsed(actual,graph_event_environment(),None,check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("closed sequence source")
  }
}
