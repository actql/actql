///|
test "nearest execution retains both owned roles across mixed and unknown Carriers" {
  let policy = sequence_limit_policy(false)
  let rows = @carrier.rows(
    [
      (
        Unqualified("key"),
        Some(@contract.primitive(NumberType, nullable=false)),
      ),
      (
        Unqualified("embedding"),
        Some(@contract.vector_contract(2, nullable=false).unwrap()),
      ),
    ],
    field_set=Closed,
    max_fields=2,
    max_name_bytes=20,
  ).unwrap()
  let inputs = [
    @carrier.relation(rows),
    @carrier.vectors(
      rows,
      ids=[Unqualified("key")],
      components=Unqualified("embedding"),
      max_identity_fields=1,
    ).unwrap(),
    @carrier.unknown_carrier(VectorsKind),
  ]
  for a in 0..<3 {
    for b in 0..<3 {
      for same in [false, true] {
        if same && a != b {
          continue
        }
        let pipeline = @pipeline.check_carriers(
          asof_test_cursor(
            "[{\"from\":\"a\",\"nearest\":{\"queries\":\"" +
            (if same { "a" } else { "b" }) +
            "\",\"k\":2,\"metric\":\"dot\"" +
            (if a == 0 { ",\"candidate_id\":\"key\"" } else { "" }) +
            (if b == 0 { ",\"query_id\":\"key\"" } else { "" }) +
            "}}]",
          ),
          [("a", inputs[a]), ("b", inputs[b])],
          None,
          None,
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
        let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
        let mut admitted = 0
        let mut roles = 0
        let mut dimensions = 0
        let mut completions = 0
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
          let result = direct_execution_candidate(
            site,
            policy,
            Ok(None),
            Ok(None),
          )
          if site.requirement
            is @pipeline.NearestRequirement(
              ResolveNearestResources
              | ResolveNearestProfile
            ) {
            assert_true(result is Ok(None))
            continue
          }
          guard result is Ok(Some(NearestExecution(check))) else {
            fail("missing nearest binding")
          }
          admitted += 1
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.step, step))
          assert_true(physical_equal(check.policy, policy))
          assert_eq(check.candidates, @pipeline.Input(0))
          assert_eq(check.queries, @pipeline.Input(if same { 0 } else { 1 }))
          guard step.operation is @pipeline.Nearest(checked=operation, ..) else {
            fail("nearest")
          }
          assert_true(physical_equal(check.operation, operation))
          let pair = @vector.nearest_pair(operation)
          assert_eq(@vector.nearest_k(@vector.nearest_pair_options(pair)), 2L)
          let before = match check.rule {
            ValidateNearestRoleBindings(side) => {
              roles += 1
              assert_eq(if side is Candidates { a } else { b }, 2)
              assert_true(
                @vector.nearest_input_vectors(
                  @vector.nearest_pair_input(pair, side),
                )
                is None,
              )
              true
            }
            MatchNearestDimensions => {
              dimensions += 1
              true
            }
            JournalVectorFieldCompletion(side, name) => {
              completions += 1
              assert_eq(if side is Candidates { a } else { b }, 0)
              assert_true(
                @vector.nearest_input_vectors(
                  @vector.nearest_pair_input(pair, side),
                )
                is Some(_),
              )
              assert_eq(name, @schema.Unqualified("embedding"))
              true
            }
            AdmitQuantizedVectorComponents | ValidateBothUniqueIdentities =>
              true
            EvaluateExactNearestScores
            | RestoreSemanticIdentityValues
            | OrderQueriesByIdentity
            | OrderCandidatesByDescendingScoreThenIdentity
            | AssignContiguousOneBasedRanks
            | PreserveSimilarityAuthorityBoundary => false
            _ => {
              fail("unexpected requirement in this explicit identity fixture")
              false
            }
          }
          assert_eq(
            operation_execution_phase(NearestExecution(check)),
            if before {
              BeforeOperationInputUse
            } else {
              BeforeOperationOutput
            },
          )
          assert_eq(
            operation_execution_failure(NearestExecution(check)),
            RejectOperationOutput,
          )
          assert_true(
            nearest_execution_check({ ..site, step: 99, }, policy)
            is Err(ForeignOccurrence(99)),
          )
          assert_true(
            nearest_execution_check({ ..site, group: 1, }, policy)
            is Err(ForeignOccurrence(0)),
          )
          assert_true(
            nearest_execution_check({ ..site, index: 99, }, policy)
            is Err(ForeignOccurrence(0)),
          )
        }
        assert_eq(
          roles,
          (if a == 2 { 1 } else { 0 }) + (if b == 2 { 1 } else { 0 }),
        )
        assert_eq(dimensions, if a == 2 || b == 2 { 1 } else { 0 })
        assert_eq(
          completions,
          (if a == 0 { 1 } else { 0 }) + (if b == 0 { 1 } else { 0 }),
        )
        assert_eq(admitted, 8 + roles + dimensions + completions)
      }
    }
  }
}
