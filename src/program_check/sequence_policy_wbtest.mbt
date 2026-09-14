///|
test "SourceView sequence retains input policy and owned matching limits across Carrier alternatives" {
  for events in [false, true] {
    for overlap in ["allow", "disallow"] {
      for contiguity in ["adjacent", "subsequence"] {
        for
          guard_text in ["", ",\"max_matches_per_key\":2,\"max_output_rows\":3"] {
          let body = "{\"by\":[],\"id\":\"id\",\"time\":\"extra\",\"pattern\":[{\"as\":\"a\",\"where\":\"extra > 0\"},{\"as\":\"b\",\"where\":\"id = id\"}],\"within\":10,\"overlap\":\"" +
            overlap +
            "\",\"contiguity\":\"" +
            contiguity +
            "\"" +
            guard_text +
            "}"
          let program = checked_direct_program_fixture(
            sequence_body=body,
            sequence_events=events,
          )
          let policy = publication_source_policy(
            program.units[0].publications[0],
          ).unwrap()
          assert_eq(publication_policy_source_count(policy), 1)
          assert_eq(
            publication_policy_carrier_step_count(policy),
            if events {
              2
            } else {
              1
            },
          )
          let retained = publication_policy_carrier_step_at(policy, 0).unwrap()
          guard retained.operation is Sequence(operation) else {
            fail("missing retained Sequence")
          }
          assert_eq(retained.step, if events { 1 } else { 0 })
          guard @pipeline.step_at(program.units[0].pipeline, retained.step).unwrap().operation
            is Sequence(original) else {
            fail("original Sequence lost")
          }
          assert_true(physical_equal(operation, original))
          assert_true(retained.unknown_provenance)
          assert_eq(@relation.sequence_pattern_count(operation), 2)
          assert_eq(unit_sequence_limit_count(program, 0), Some(1))
          let limits = unit_sequence_limit_at(program, 0, 0).unwrap()
          assert_true(
            physical_equal(
              sequence_limit_source(limits).pipeline,
              program.units[0].pipeline,
            ),
          )
          for scope in [@sequence.MatchesPerKey, OutputRows] {
            assert_eq(
              @derivation.minimum_value(
                @wire.limit_minimum(sequence_limit_claim(limits, scope)),
              ),
              1L,
            )
          }
          let closure = @context.stage_requirement_operations(
            requirements(program),
          )
          let mut matches = 0
          let mut bounds = 0
          for i in 0..<@context.operation_closure_count(closure) {
            if @context.operation_closure_at(closure, i)
              is Some(ExecutionCheck(check)) {
              match check {
                SequenceMatch(v) => {
                  assert_eq(v.site.step, retained.step)
                  assert_true(
                    physical_equal(v.site.pipeline, program.units[0].pipeline),
                  )
                  assert_eq(v.within_ms, 10L)
                  matches += 1
                }
                SequenceLimits(v) => {
                  assert_eq(v.site.step, retained.step)
                  assert_eq(
                    @context.operation_execution_failure(check),
                    RejectOperationOutput,
                  )
                  bounds += 1
                }
                _ => ()
              }
            }
          }
          assert_eq((matches, bounds), (1, 1))
        }
      }
    }
  }
}

///|
test "sequence policy charges later predicate nodes even after unknown within provenance" {
  let usages : Array[Int] = []
  for predicate in ["id = id", "id = id AND extra = extra"] {
    let body = "{\"by\":[],\"id\":\"id\",\"time\":\"extra\",\"pattern\":[{\"as\":\"a\",\"where\":\"TRUE\"},{\"as\":\"b\",\"where\":\"" +
      predicate +
      "\"}],\"within\":10,\"overlap\":\"allow\",\"contiguity\":\"subsequence\"}"
    let program = checked_direct_program_fixture(sequence_body=body)
    let unit = program.units[0]
    let result = @context.publication_row_limit_result(
      unit.publications[0].selection,
    )
    let budget = IdentityBudget::{
      work: 1000000,
      bytes: 100000,
      nodes: 10000,
      depth: 100,
    }
    let policy = prepare_publication_source_policy(unit, result, budget).unwrap()
    assert_true(policy.unknown_provenance)
    let used = 1000000 - budget.work
    usages.push(used)
    let exact = IdentityBudget::{
      work: used,
      bytes: 100000,
      nodes: 10000,
      depth: 100,
    }
    let _ = prepare_publication_source_policy(unit, result, exact).unwrap()
    assert_eq(exact.work, 0)
    try
      prepare_publication_source_policy(unit, result, {
        work: used - 1,
        bytes: 100000,
        nodes: 10000,
        depth: 100,
      })
    catch {
      BudgetExceeded => ()
      error => raise error
    } noraise {
      _ => fail("sequence policy exceeded aggregate work")
    }
  }
  // The extra comparison adds two field nodes, one equality and one AND.
  // No other graph or policy contribution changes.
  assert_eq(usages[1] - usages[0], 4)
}
