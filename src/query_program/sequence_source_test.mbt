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

///|
fn sequence_checked_text(source : String, context? : Context = {..pair_context(),inputs:[]}) -> @program.Program raise {
  let actual=match @frontend.lower(source,Sql,Some(context)) {
    Ok(frontend) => frontend.program.unwrap()
    Err(QueryLowering(UnknownColumn)) => fail("actual sequence UnknownColumn")
    Err(QueryLowering(UnsupportedOrdering)) => fail("actual sequence UnsupportedOrdering")
    Err(QueryLowering(BindingPreparation(LocalProgram(Pipeline(_,issue))|SourceProgram(Program(Pipeline(_,issue)))))) => fail("actual sequence common pipeline: "+@debug.to_string(issue.kind))
    Err(QueryLowering(Expression(issue))) => fail("actual sequence expression: "+@debug.to_string(issue.issue))
    Err(_) => fail("actual sequence frontend boundary")
  }
  match @check.check_parsed(actual,graph_event_environment(),None,check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("closed sequence fields")
  }
  actual
}

///|
test "sequence Events identity and numeric clock remain with the existing common owner" {
  let text=sequence_source_text().replace(old="matches AS (FROM events AS e",new="prepared AS (FROM events |> to_events(id: id, time: occurred_ms)), matches AS (FROM prepared")
    .replace(old="id: e.id, time: e.occurred_ms",new="id: id, time: occurred_ms")
    .replace(old="e.kind = 1",new="kind = 1").replace(old="e.kind = 2",new="kind = 2")
  let actual=sequence_checked_text(text)
  let body=with_carrier_argument(actual,"sequence")
  assert_true(body.contains("\"time\":\"occurred_ms\""))
  assert_true(body.contains("\"id\":\"id\""))
  assert_eq(semantic(actual).split("\"to_events\":").length(),2)
}

///|
test "sequence CASE and nullable predicates use ordinary expression lowering" {
  let text=sequence_source_text().replace(old="e.kind = 1",new="CASE WHEN e.kind = 1 THEN TRUE ELSE NULL END")
  let actual=sequence_checked_text(text)
  let body=with_carrier_argument(actual,"sequence")
  assert_true(body.contains("\"case\":"))
  assert_true(body.contains("\"literal\":null"))
  assert_true(!body.contains("CASE WHEN"))
}

///|
test "sequence labels do not become input fields for a later predicate" {
  let text=sequence_source_text().replace(old="e.kind = 2",new="first_id = 1")
  assert_true(@frontend.lower(text,Sql,Some({..pair_context(),inputs:[]})) is Err(QueryLowering(Expression({issue: @expression.UnknownReference,..}))))
  let dropped=sequence_source_text().replace(old="matches AS (FROM events AS e",new="kept AS (SELECT id, occurred_ms FROM events), matches AS (FROM kept AS e")
  assert_true(@frontend.lower(dropped,Sql,Some({..pair_context(),inputs:[]})) is Err(QueryLowering(Expression({issue: @expression.UnknownReference,..}))))
}

///|
test "sequence Strings are data expressions rather than reparsed predicates" {
  let text=sequence_source_text().replace(old="e.kind = 1",new="'e.kind = 1'")
  match @frontend.lower(text,Sql,Some({..pair_context(),inputs:[]})) {
    Err(QueryLowering(BindingPreparation(SourceProgram(Program(Pipeline(_,issue)))|LocalProgram(Pipeline(_,issue))))) => assert_true(issue.kind is Operation(ExpectedBoolean))
    _ => fail("a String expression cannot supply a Boolean predicate")
  }
}

///|
test "sequence OutputName labels and common generated collisions stay distinct" {
  let quoted=sequence_source_text().replace(old="as: first",new="as: `SELECT`").replace(old="first_id",new="SELECT_id").replace(old="first_id",new="SELECT_id").replace(old="first_time_ms",new="SELECT_time_ms")
  let actual=sequence_checked_text(quoted)
  assert_true(with_carrier_argument(actual,"sequence").contains("\"as\":\"SELECT\""))
  assert_true(@frontend.lower(sequence_source_text().replace(old="as: first",new="as: SELECT"),Sql,Some({..pair_context(),inputs:[]})) is Err(QuerySyntax(_)))
  match @frontend.lower(sequence_source_text().replace(old="as: second",new="as: first"),Sql,Some({..pair_context(),inputs:[]})) {
    Err(QueryLowering(BindingPreparation(SourceProgram(Program(Pipeline(_,issue)))|LocalProgram(Pipeline(_,issue))))) => assert_true(issue.kind is Operation(DuplicatePatternLabel("first")))
    _ => fail("common owner must reject duplicate labels")
  }
}

///|
test "sequence shared input and authored limits are retained" {
  let text="WITH original AS (SELECT x AS id, y AS occurred_ms, 1 AS kind FROM pair), matches AS (FROM original AS e |> sequence(by: [e.kind, kind], id: e.id, time: e.occurred_ms, pattern: [{as: first, where: TRUE}, {as: second, where: TRUE}], within: 20, overlap: 'allow', contiguity: 'subsequence', max_matches_per_key: 2, max_output_rows: 3)) SELECT first_id, second_id FROM matches ORDER BY first_id, second_id"
  let actual=sequence_checked_text(text,context=pair_context())
  let body=with_carrier_argument(actual,"sequence")
  assert_true(body.contains("\"by\":[\"kind\",\"kind\"]"))
  assert_true(body.contains("\"max_matches_per_key\":2"))
  assert_true(body.contains("\"max_output_rows\":3"))
  assert_true(body.contains("\"overlap\":\"allow\""))
  assert_true(body.contains("\"contiguity\":\"subsequence\""))
  assert_eq(semantic(actual).split("\"values\":").length(),2)
}

///|
test "sequence predicate and guard Parameters retain the original binding owner" {
  let declarations=@parameters.read_declarations(Some(from_unpivot_public_cursor("{\"tag\":{\"type\":\"number\",\"nullable\":false},\"span\":{\"type\":\"number\",\"nullable\":false},\"cap\":{\"type\":\"number\",\"nullable\":false}}")),{max_parameters:10,max_nodes:128,max_depth:16,max_text_bytes:4096}).unwrap()
  let text=sequence_source_text().replace(old="e.kind = 1",new="e.kind = @TAG").replace(old="within: 20",new="within: @span").replace(old="max_output_rows: 2",new="max_output_rows: @cap")
  let actual=@frontend.lower(text,Sql,Some({..pair_context(),inputs:[],parameter_declarations:Some(declarations)})).unwrap().program.unwrap()
  let body=with_carrier_argument(actual,"sequence")
  for name in ["tag","span","cap"] { assert_true(body.contains("\"$param\":\""+name+"\"")) }
  assert_true(@check.check_parsed(actual,graph_event_environment(),None,check_limits()) is NeedsInputs(_))
  match @check.check_parsed(actual,graph_event_environment(),Some(from_unpivot_public_cursor("{\"tag\":1,\"span\":20,\"cap\":2}")),check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("supplied predicate and guard parameters")
  }
}

///|
fn sequence_source_schema(program : @program.Program) -> Array[@schema.Field] raise {
  let checked=match @check.check_parsed(program,graph_event_environment(),None,check_limits()) {
    Checked(checked) => checked
    Rejected(issue) => {graph_rows_rejected(issue);fail("sequence schema")}
    NeedsInputs(_) => fail("closed schema")
  }
  let stage=@stage_results.stage_at(@check.checked_stage_results(checked),0).unwrap()
  @schema.fields(@relation_results.output_schema(@relation_results.lookup(stage,"rows").unwrap()))
}

///|
test "empty sequence input retains its independent complete ordered output contract" {
  let text=sequence_source_text().replace(old="matches AS (FROM events AS e",new="empty AS (SELECT id, occurred_ms, kind FROM events WHERE FALSE), matches AS (FROM empty AS e")
  let actual=sequence_checked_text(text)
  let fields=sequence_source_schema(actual)
  let expected=sequence_source_schema(sequence_source_control())
  assert_eq(fields.map(field=>field.name),expected.map(field=>field.name))
  for i in 0..<fields.length() {
    assert_eq(fields[i].presence,expected[i].presence)
    assert_true(@contract.type_equal(fields[i].contract,expected[i].contract,10000))
  }
}
