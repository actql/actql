///|
test "text ranking bindings retain selected lexical artifacts and producer input roles" {
  for tokenizer in ["unicode_words", "char_bigram"] {
    for same_input in [false, true] {
      let cells = lexical_cells(lexical_host(), true, tokenizer~, same_input~)
      let selected = lexical_artifact(cells)
      let lexical = check_program_operation_lexical(
        cells,
        Some(selected),
        10000000,
        3,
      ).unwrap()
      let calendar = check_program_operation_calendar(
        lexical,
        None,
        10000000,
        0,
      ).unwrap()
      let profiles = link_program_operation_profiles(calendar, 10000000, 100).unwrap()
      let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
      let requirements = operation_resolution_requirements(index)
      let mut executions = 0
      let mut resources = 0
      for i in 0..<operation_resolution_count(index) {
        let site = operation_requirements_at(requirements, i).unwrap()
        if site.requirement
          is @pipeline.TextRankRequirement(
            ResolveTokenizerAndNormalizedTextCeilings
            | ResolveStatisticsScoringAndOutputResources
          ) {
          assert_true(operation_resolution_at(index, i) is Some(Unresolved))
          resources += 1
        }
        guard operation_resolution_at(index, i)
          is Some(Execution(TextRankExecution(check))) else {
          continue
        }
        executions += 1
        assert_true(physical_equal(check.site, site))
        assert_true(physical_equal(check.selection.selected, selected))
        assert_true(physical_equal(check.selection.operation, check.operation))
        assert_true(
          physical_equal(
            check.step,
            @pipeline.step_at(site.pipeline, site.step).unwrap(),
          ),
        )
        assert_eq(check.selection.stage, site.stage)
        assert_eq(check.selection.producer_visit, site.producer_visit)
        assert_eq(check.corpus, @pipeline.Step(1))
        assert_eq(check.queries, @pipeline.Step(if same_input { 1 } else { 0 }))
        let options = @vector.text_rank_options(check.operation)
        assert_eq(
          @vector.text_rank_tokenizer(options),
          if tokenizer == "unicode_words" {
            UnicodeWords
          } else {
            CharBigram
          },
        )
        assert_eq(@vector.text_rank_bm25(options), (1.2, 0.75))
        assert_eq(@vector.text_rank_k(options), 1.0)
        let input_phase = match check.rule {
          ValidateCompleteTextInputs
          | ValidateGlobalStringIdentities(_)
          | NormalizeAndTokenizeWithPinnedUnicode => true
          _ => false
        }
        assert_eq(
          operation_execution_phase(TextRankExecution(check)),
          if input_phase {
            BeforeOperationInputUse
          } else {
            BeforeOperationOutput
          },
        )
        assert_eq(
          operation_execution_failure(TextRankExecution(check)),
          RejectOperationOutput,
        )
      }
      assert_eq(executions, 33)
      assert_eq(resources, 6)
      let foreign = lexical_artifact(lexical_cells(lexical_host(), true))
      assert_true(
        check_program_operation_lexical(cells, Some(foreign), 10000000, 3)
        is Err(ForeignEnvironment),
      )
      let work = operation_resolution_work(index)
      let count = operation_resolution_count(index)
      assert_true(
        index_program_operation_resolutions(profiles, work, count) is Ok(_),
      )
      assert_true(
        index_program_operation_resolutions(profiles, work - 1, count)
        is Err(BudgetExceeded),
      )
      assert_true(
        index_program_operation_resolutions(profiles, work, count - 1)
        is Err(BudgetExceeded),
      )
      check_operation_closure(index)
    }
  }
}
