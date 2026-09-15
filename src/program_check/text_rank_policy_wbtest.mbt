///|
test "lexical publication retains corpus and query policy with pinned profile and RRF" {
  for tokenizer in ["unicode_words", "char_bigram"] {
    for empty_query in [false, true] {
      for fused in [false, true] {
        let steps = "{\"filter\":\"" +
          (if empty_query { "FALSE" } else { "TRUE" }) +
          "\",\"as\":\"queries\"},{\"from\":\"docs\",\"text_rank\":{\"queries\":\"queries\",\"candidate_id\":\"doc_id\",\"candidate_text\":\"text\",\"query_id\":\"doc_id\",\"query_text\":\"text\",\"tokenizer\":\"" +
          tokenizer +
          "\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":2},\"as\":\"ranked\"}" +
          (if fused {
            ",{\"merge_rankings\":{\"with\":\"ranked\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":1,\"rank_window\":1,\"weights\":[1,1]}}}}"
          } else {
            ""
          })
        let program = checked_direct_program_fixture(lexical_steps=steps)
        let unit = program.units[0]
        let policy = publication_source_policy(unit.publications[0]).unwrap()
        assert_eq(publication_policy_source_count(policy), 1)
        assert_eq(
          publication_policy_carrier_step_count(policy),
          if fused {
            2
          } else {
            1
          },
        )
        let retained = publication_policy_carrier_step_at(
          policy,
          if fused {
            1
          } else {
            0
          },
        ).unwrap()
        guard retained.operation is TextRank(queries=target, checked=operation) else {
          fail("lexical operation lost")
        }
        assert_eq(retained.step, 2)
        assert_eq(target, Step(1))
        assert_true(retained.unknown_provenance)
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut tokenization = 0
        let mut scoring = 0
        let mut ranking = 0
        for i in 0..<@context.operation_closure_count(closure) {
          match @context.operation_closure_at(closure, i) {
            Some(ExecutionCheck(TextRankExecution(check))) => {
              assert_true(physical_equal(check.operation, operation))
              assert_true(physical_equal(check.site.pipeline, unit.pipeline))
              assert_eq(check.corpus, Step(0))
              assert_eq(check.queries, Step(1))
              assert_eq(
                @lexical.cid(
                  @environment.selected_text_rank_profile(
                    check.selection.selected,
                  ),
                ),
                text_profile_fixture_cid(),
              )
              assert_eq(
                @context.operation_execution_failure(TextRankExecution(check)),
                RejectOperationOutput,
              )
              match check.rule {
                ResolveTokenizerAndNormalizedTextCeilings => {
                  tokenization += 1
                  assert_eq(@context.text_rank_resource_count(check), 4)
                }
                ResolveStatisticsScoringAndOutputResources => {
                  scoring += 1
                  assert_eq(@context.text_rank_resource_count(check), 6)
                }
                _ => ()
              }
            }
            Some(ExecutionCheck(RankingExecution(check))) => {
              if check.rule == RequireRankingResources {
                ranking += 1
              }
              for j in 0..<@context.ranking_execution_input_count(check) {
                let (_, shape) = @context.ranking_execution_input_at(check, j).unwrap()
                assert_true(
                  physical_equal(
                    @vector.ranking_input_text(
                      @vector.ranking_shape_input(shape),
                    ).unwrap(),
                    operation,
                  ),
                )
              }
            }
            _ => ()
          }
        }
        assert_eq((tokenization, scoring), (1, 1))
        assert_eq(ranking, if fused { 1 } else { 0 })
      }
    }
  }
}

///|
test "lexical publication cannot substitute a profile pin for admitted profile material" {
  try
    checked_direct_program_fixture(
      lexical_steps="{\"text_rank\":{\"queries\":\"docs\",\"candidate_id\":\"doc_id\",\"candidate_text\":\"text\",\"query_id\":\"doc_id\",\"query_text\":\"text\",\"tokenizer\":\"unicode_words\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":2}}",
      lexical_material=false,
    )
  catch {
    Closure(Operations(Lexical(MissingArtifact(selection)))) =>
      assert_eq(
        @environment.text_rank_selection_cid(selection),
        text_profile_fixture_cid(),
      )
    error => raise error
  } noraise {
    _ => fail("profile CID alone cannot complete lexical publication")
  }
}
