///|
test "formal lexical ranking retains profile resources and RRF dependencies across imports" {
  for tokenizer in ["unicode_words", "char_bigram"] {
    for empty in [false, true] {
      for material in [false, true] {
        let programs : Array[CheckedProgram] = []
        let succeeded = try {
          let _ = local_construction_fixture(
            { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
            through_check=true,
            checked_results=programs,
            second_stage=true,
            veca=true,
            text_rank=true,
            text_rank_material=material,
            generated_schema="{\"id\":{\"type\":\"string\",\"nullable\":false},\"text\":{\"type\":\"string\",\"nullable\":false}}",
            generated_rows=Some(
              if empty {
                "[]"
              } else {
                "[{\"id\":\"a\",\"text\":\"Hello hello\"},{\"id\":\"b\",\"text\":\"\"}]"
              },
            ),
            producer_expression="id",
            producer_suffix=",{\"text_rank\":{\"queries\":\"derived\",\"candidate_id\":\"id\",\"candidate_text\":\"text\",\"query_id\":\"id\",\"query_text\":\"text\",\"tokenizer\":\"" +
              tokenizer +
              "\",\"scoring\":{\"bm25\":{\"k1\":1.2,\"b\":0.75}},\"k\":2},\"as\":\"ranked\"},{\"merge_rankings\":{\"with\":\"ranked\",\"by\":[\"query_id\"],\"candidate\":\"candidate_id\",\"rank\":\"rank\",\"k\":2,\"score_policy\":{\"rrf\":{\"rank_constant\":1,\"rank_window\":1,\"weights\":[1,1]}}}},{\"select\":[{\"id\":\"query_id\"},{\"value\":\"candidate_id\"}],\"as\":\"projected\"}",
            producer_result_from="projected",
            extra_step_budget=3,
          )
          true
        } catch {
          _ => false
        }
        if !material {
          assert_false(succeeded)
          assert_eq(programs.length(), 0)
          continue
        }
        assert_true(succeeded)
        let program = programs[0]
        assert_eq(unit_count(program), 2)
        let closure = @context.stage_requirement_operations(
          program.requirements,
        )
        let mut tokenizer_resources = 0
        let mut scoring_resources = 0
        let mut ranking_resources = 0
        for i in 0..<@context.operation_closure_count(closure) {
          match @context.operation_closure_at(closure, i) {
            Some(ExecutionCheck(TextRankExecution(check))) => {
              assert_true(
                physical_equal(check.site.pipeline, program.units[0].pipeline),
              )
              assert_eq(check.site.step, 2)
              assert_eq(check.corpus, @pipeline.Step(1))
              assert_eq(check.queries, @pipeline.Step(1))
              assert_eq(
                @lexical.cid(
                  @environment.selected_text_rank_profile(
                    check.selection.selected,
                  ),
                ),
                text_profile_fixture_cid(),
              )
              match check.rule {
                ResolveTokenizerAndNormalizedTextCeilings => {
                  tokenizer_resources += 1
                  assert_eq(@context.text_rank_resource_count(check), 4)
                }
                ResolveStatisticsScoringAndOutputResources => {
                  scoring_resources += 1
                  assert_eq(@context.text_rank_resource_count(check), 6)
                  assert_eq(
                    @policy.ceiling_value(check.host_output_rows.unwrap()),
                    1000L,
                  )
                }
                _ => ()
              }
            }
            Some(ExecutionCheck(RankingExecution(check))) => {
              if check.rule == RequireRankingResources {
                ranking_resources += 1
              }
              for j in 0..<@context.ranking_execution_input_count(check) {
                let (_, shape) = @context.ranking_execution_input_at(check, j).unwrap()
                assert_true(
                  @evidence.ranking_input_text(
                    @evidence.ranking_shape_input(shape),
                  )
                  is Some(_),
                )
              }
            }
            _ => ()
          }
        }
        assert_eq(tokenizer_resources, 3)
        assert_eq(scoring_resources, 3)
        assert_eq(ranking_resources, 3)
      }
    }
  }
}
