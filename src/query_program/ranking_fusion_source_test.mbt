///|
fn ranking_fusion_source(call : String) -> String {
  "WITH l AS (SELECT 1 AS id, 1 AS position UNION ALL SELECT 2, 2), r AS (SELECT 2 AS id, 1 AS position UNION ALL SELECT 3, 2), fused AS (FROM l AS current |> " + call + ") SELECT id, score, rank FROM fused ORDER BY rank"
}

///|
fn ranking_fusion_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.ranking_fusion_source","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"position":{"type":"number","nullable":false}},"rows":[{"id":1,"position":1},{"id":2,"position":2}]},"as":"l"},{"values":{"schema":{"id":{"type":"number","nullable":false},"position":{"type":"number","nullable":false}},"rows":[{"id":2,"position":1},{"id":3,"position":2}]},"as":"r"},{"from":"l","merge_rankings":{"with":["r","r"],"by":[],"candidate":"id","rank":"position","k":3,"score_policy":{"rrf":{"rank_constant":1,"weights":[1,2,3],"rank_window":2}}},"as":"fused"},{"from":"fused","sort":[{"field":"rank","dir":"asc","nulls":"first"}]},{"select":["id","score","rank"],"as":"out"}],"results":{"rows":{"from":"out","fields":["id","score","rank"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn ranking_fusion_checked(program : @program.Program) -> Unit raise {
  match @check.check_parsed(program, check_environment(veca=true,numeric=true), None, check_limits()) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("ranking literals have no input acquisition")
  }
}

///|
test "ranking fusion retains repeated producer occurrences and exact authored RRF options" {
  let control=ranking_fusion_control()
  ranking_fusion_checked(control)
  let source=ranking_fusion_source("merge_rankings(with: [r, r], by: [], candidate: current.id, rank: current.position, k: 3, score_policy: {rrf: {rank_constant: 1, weights: [1, 2, 3], rank_window: 2}})")
  let actual=@frontend.lower(source, Sql, Some({..pair_context(),inputs:[]})).unwrap().program.unwrap()
  ranking_fusion_checked(actual)
  let body=with_carrier_argument(actual,"merge_rankings")
  let physical=body.split("\"with\":[\"").collect()[1].split("\"").collect()[0].to_owned()
  assert_eq(body.replace(old=physical,new="r"),with_carrier_argument(control,"merge_rankings"))
}
