///|
test "ranking execution binds ordered occurrences and keeps static envelope work unresolved" {
  let policy = sequence_limit_policy(false)
  let number = @contract.primitive(NumberType, nullable=false)
  let rows = @carrier.relation(
    @carrier.rows(
      [
        (Unqualified("q"), Some(number)),
        (Unqualified("id"), Some(number)),
        (Unqualified("score"), Some(number)),
        (Unqualified("rank"), Some(number)),
        (
          Unqualified("tie"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
      ],
      field_set=Closed,
      max_fields=5,
      max_name_bytes=30,
    ).unwrap(),
  )
  let contract = "{\"domain\":\"relevance\",\"range\":[1,2],\"normalization\":\"identity\"}"
  let ranking = @vector.declare_ranking_score(
    asof_test_cursor(contract),
    rows,
    Unqualified("score"),
    { max_work: 1000, max_nodes: 1000, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  for fusion in ["max", "weighted_sum", "rrf"] {
    let rrf = fusion == "rrf"
    let body = if rrf {
      "\"with\":[\"r\",\"l\"],\"rank\":\"rank\",\"score_policy\":{\"rrf\":{\"rank_constant\":60,\"rank_window\":10,\"weights\":[1,0,2]}}"
    } else {
      "\"with\":\"r\",\"score\":\"score\",\"tie_break\":[\"tie\"],\"score_contract\":" +
      contract +
      ",\"score_policy\":" +
      (if fusion == "max" {
        "\"max\""
      } else {
        "{\"weighted_sum\":{\"left\":0.5,\"right\":0.5}}"
      })
    }
    let pipeline = @pipeline.check_with_evidence(
      asof_test_cursor(
        "[{\"merge_rankings\":{\"by\":[\"q\",\"q\"],\"candidate\":\"id\",\"k\":2," +
        body +
        "}}]",
      ),
      [
        ("l", @pipeline.RankingInput(ranking)),
        ("r", @pipeline.RankingInput(ranking)),
      ],
      None,
      Some(asof_test_cursor("\"l\"")),
      {
        max_steps: 1,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap()
    let step = @pipeline.step_at(pipeline, 0).unwrap()
    guard step.operation is @pipeline.Ranking(operation) else {
      fail("ranking")
    }
    let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let mut bound = 0
    let mut unresolved = 0
    for index in 0..<@pipeline.operation_obligations_count(group) {
      let site : OperationRequirementSite = {
        stage: 0,
        producer_visit: 0,
        step: 0,
        group: 0,
        index,
        pipeline,
        obligations: group,
        requirement: @pipeline.operation_obligations_at(group, index).unwrap(),
      }
      let result = direct_execution_candidate(site, policy, Ok(None), Ok(None))
      if site.requirement
        is @pipeline.RankingRequirement(
          ResolveRankingResources
          | ResolveRankingProfile
          | DeriveOutputScoreEnvelope
        ) {
        assert_true(result is Ok(None))
        unresolved += 1
        continue
      }
      guard result is Ok(Some(RankingExecution(check))) else {
        fail("missing ranking binding")
      }
      bound += 1
      assert_true(physical_equal(check.site, site))
      assert_true(physical_equal(check.step, step))
      assert_true(physical_equal(check.operation, operation))
      assert_true(physical_equal(check.policy, policy))
      let count = if rrf { 3 } else { 2 }
      assert_eq(ranking_execution_input_count(check), count)
      for i in 0..<count {
        let (edge, shape) = ranking_execution_input_at(check, i).unwrap()
        assert_eq(edge.role, @pipeline.Sample(i))
        assert_eq(edge.target, @pipeline.Input(if i == 1 { 1 } else { 0 }))
        assert_true(
          physical_equal(
            shape,
            @vector.merged_ranking_input_at(operation, i).unwrap(),
          ),
        )
        assert_true(physical_equal(@vector.ranking_shape_input(shape), ranking))
      }
      assert_true(ranking_execution_input_at(check, -1) is None)
      assert_true(ranking_execution_input_at(check, count) is None)
      let input_phase = match check.rule {
        AdmitCompleteRankings
        | ValidateRankingUniqueness
        | ValidateContiguousInputRanks
        | AuthenticateRankingScores
        | AdmitRankingScoreRanges
        | ValidateRankingTieAgreement => true
        ApplyRankingWindow
        | EvaluateRankingScores
        | OrderFusedRankings
        | AssignFusedRanks => false
      }
      assert_eq(
        operation_execution_phase(RankingExecution(check)),
        if input_phase {
          BeforeOperationInputUse
        } else {
          BeforeOperationOutput
        },
      )
      assert_eq(
        operation_execution_failure(RankingExecution(check)),
        RejectOperationOutput,
      )
      assert_true(
        ranking_execution_check({ ..site, step: 99, }, policy)
        is Err(ForeignOccurrence(99)),
      )
      assert_true(
        ranking_execution_check({ ..site, group: 1, }, policy)
        is Err(ForeignOccurrence(0)),
      )
      assert_true(
        ranking_execution_check({ ..site, index: 99, }, policy)
        is Err(ForeignOccurrence(0)),
      )
    }
    assert_eq(bound, if rrf { 7 } else { 8 })
    assert_eq(unresolved, 3)
  }
}
