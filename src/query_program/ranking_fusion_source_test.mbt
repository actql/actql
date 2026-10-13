///|
fn ranking_fusion_source(call : String) -> String {
  "WITH l AS (SELECT 1 AS id, 1 AS position UNION ALL SELECT 2, 2), r AS (SELECT 2 AS id, 1 AS position UNION ALL SELECT 3, 2), fused AS (FROM l AS `current` |> " +
  call +
  ") SELECT id, score, rank FROM fused ORDER BY rank"
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
  match
    @check.check_parsed(
      program,
      check_environment(veca=true, numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => graph_rows_rejected(issue)
    NeedsInputs(_) => fail("ranking literals have no input acquisition")
  }
}

///|
test "ranking fusion retains repeated producer occurrences and exact authored RRF options" {
  let control = ranking_fusion_control()
  ranking_fusion_checked(control)
  let source = ranking_fusion_source(
    "merge_rankings(with: [r, r], by: [], candidate: current.id, rank: current.position, k: 3, score_policy: {rrf: {rank_constant: 1, weights: [1, 2, 3], rank_window: 2}})",
  )
  let actual = @frontend.lower(
    source,
    Sql,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  ranking_fusion_checked(actual)
  let body = with_carrier_argument(actual, "merge_rankings")
  let physical = body.split("\"with\":[\"").collect()[1].split("\"").collect()[0].to_owned()
  let operands = body.split("\"with\":[").collect()[1].split("]").collect()[0]
    .split("\"")
    .collect()
  assert_eq(operands[1], operands[3])
  assert_eq(
    body.replace(old=physical, new="r").replace(old=physical, new="r"),
    with_carrier_argument(control, "merge_rankings"),
  )
}

///|
fn ranking_fusion_program(text : String) -> @program.Program raise {
  let actual = @frontend.lower(
    text,
    Sql,
    Some({ ..pair_context(), inputs: [], }),
  ).unwrap().program.unwrap()
  ranking_fusion_checked(actual)
  actual
}

///|
test "RRF producer list preserves quotation scope and repeated group roles" {
  let text = "WITH l AS (SELECT 1 AS id, 1 AS position, 7 AS group_id), `ranking.right` AS (SELECT 2 AS id, 1 AS position, 7 AS group_id), fused AS (FROM l AS `current` |> merge_rankings(with: [`ranking.right`, `ranking.right`], by: [current.group_id, group_id], candidate: id, rank: position, k: 3, score_policy: {RRF: {RANK_CONSTANT: 1, WEIGHTS: [1, 0, 2], RANK_WINDOW: 2}})) SELECT group_id, id, score, rank FROM fused ORDER BY group_id, rank"
  let actual = ranking_fusion_program(text)
  let body = with_carrier_argument(actual, "merge_rankings")
  assert_true(body.contains("\"by\":[\"group_id\",\"group_id\"]"))
  assert_true(body.contains("\"weights\":[1,0,2]"))
  assert_true(body.contains("\"rank_constant\":1"))
}

///|
test "nested RRF peer resolves its nearest binding without retaining the outer body" {
  let text = "WITH r AS (SELECT 99 AS id, 1 AS position), fused AS (WITH l AS (SELECT 1 AS id, 1 AS position), r AS (SELECT 2 AS id, 1 AS position) FROM l |> merge_rankings(with: [r, r], by: [], candidate: id, rank: position, k: 3, score_policy: {rrf: {rank_constant: 1, weights: [1, 2, 3], rank_window: 2}})) SELECT id, score, rank FROM fused ORDER BY rank"
  let actual = ranking_fusion_program(text)
  assert_true(!semantic(actual).contains("\"literal\":99"))
  assert_eq(semantic(actual).split("\"merge_rankings\":").length(), 2)
}

///|
test "repeated RRF input references share the original installed Values once" {
  let text = "WITH ranking AS (SELECT x AS id, 1 AS position FROM pair), fused AS (FROM ranking |> merge_rankings(with: [ranking, ranking], by: [], candidate: id, rank: position, k: 3, score_policy: {rrf: {rank_constant: 1, weights: [1, 2, 3], rank_window: 2}})) SELECT id, score, rank FROM fused ORDER BY rank"
  let actual = @frontend.lower(text, Sql, Some(pair_context())).unwrap().program.unwrap()
  ranking_fusion_checked(actual)
  assert_eq(semantic(actual).split("\"values\":").length(), 2)
  let body = with_carrier_argument(actual, "merge_rankings")
  let operands = body.split("\"with\":[").collect()[1].split("]").collect()[0]
    .split("\"")
    .collect()
  assert_eq(operands[1], operands[3])
}

///|
test "ranking fields cannot restore a dropped column or old row range" {
  let prefix = "WITH l AS (SELECT 1 AS id, 1 AS position), r AS (SELECT 2 AS id, 1 AS position), kept AS (SELECT id FROM l) FROM kept AS `current` |> "
  for field in ["position", "old.id"] {
    let source = prefix +
      "merge_rankings(with: r, by: [], candidate: current.id, rank: " +
      field +
      ", k: 3, score_policy: {rrf: {rank_constant: 1, weights: [1, 2], rank_window: 2}})"
    assert_true(
      @frontend.lower(source, Text, Some({ ..pair_context(), inputs: [], }))
      is Err(QueryLowering(UnknownColumn)),
    )
  }
}

///|
test "RRF list cannot be replaced by strings or a weight-count-changing default" {
  let valid = "merge_rankings(with: [r, r], by: [], candidate: id, rank: position, k: 3, score_policy: {rrf: {rank_constant: 1, weights: [1, 2, 3], rank_window: 2}})"
  assert_true(
    @frontend.lower(
      ranking_fusion_source(valid.replace(old="[r, r]", new="['r', 'r']")),
      Sql,
      Some({ ..pair_context(), inputs: [], }),
    )
    is Err(QuerySyntax(_)),
  )
  let mismatched = valid.replace(old="[1, 2, 3]", new="[1, 2]")
  match
    @frontend.lower(
      ranking_fusion_source(mismatched),
      Sql,
      Some({ ..pair_context(), inputs: [], }),
    ) {
    Err(
      QueryLowering(
        BindingPreparation(
          SourceProgram(Program(Pipeline(_, issue)))
          | LocalProgram(Pipeline(_, issue))
        )
      )
    ) => assert_true(issue.kind is Vector(InvalidBody))
    _ => fail("common ranking owner must reject a wrong weight count")
  }
}

///|
test "score fusion retains its common missing-declaration refusal" {
  let prefix = "WITH l AS (SELECT 1 AS id, 0.5 AS s), r AS (SELECT 2 AS id, 0.5 AS s) FROM l |> "
  for policy in ["'max'", "{weighted_sum: {left: 0.5, right: 0.5}}"] {
    let source = prefix +
      "merge_rankings(with: r, by: [], candidate: id, score: s, score_policy: " +
      policy +
      ", score_contract: {domain: 'Relevance', range: [0, 1], normalization: 'Identity'}, k: 3)"
    match
      @frontend.lower(source, Text, Some({ ..pair_context(), inputs: [], })) {
      Err(
        QueryLowering(
          BindingPreparation(
            SourceProgram(Program(Pipeline(_, issue)))
            | LocalProgram(Pipeline(_, issue))
          )
        )
      ) => assert_true(issue.kind is Vector(MissingScoreContract))
      _ =>
        fail("raw scores cannot fabricate an authenticated ranking declaration")
    }
  }
}

///|
test "independent raw-score Program and text agree on missing score declarations" {
  for policy in ["\"max\"", "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"] {
    let body = "{\"with\":\"r\",\"by\":[],\"candidate\":\"id\",\"score\":\"s\",\"score_policy\":" +
      policy +
      ",\"score_contract\":{\"domain\":\"Relevance\",\"range\":[0,1],\"normalization\":\"Identity\"},\"k\":3}"
    let program = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.raw_score_refusal\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"s\":0.5}]},\"as\":\"l\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2,\"s\":0.5}]},\"as\":\"r\"},{\"from\":\"l\",\"merge_rankings\":" +
      body +
      ",\"as\":\"fused\"}],\"results\":{\"rows\":{\"from\":\"fused\",\"fields\":[\"id\",\"score\",\"rank\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    let source = @stage_parameters.prepare(program, {
      max_parameters: 100,
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    }).unwrap()
    match
      @stage_results.check_local_program(source, {
        max_stages: 10,
        max_steps: 100,
        max_results: 100,
        max_work: 1000000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
        max_text_bytes: 100000,
      }) {
      Err(Pipeline(_, issue)) =>
        assert_true(issue.kind is Vector(MissingScoreContract))
      _ => fail("independent raw score data has no declaration evidence")
    }
  }
}
