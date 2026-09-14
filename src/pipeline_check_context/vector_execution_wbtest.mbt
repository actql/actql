///|
test "vector execution bindings preserve roles metrics and obligations without executing" {
  let policy = sequence_limit_policy(false)
  let input = @carrier.relation(
    @carrier.rows(
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
    ).unwrap(),
  )
  for metric in ["cosine", "dot", "l2"] {
    let pipeline = @pipeline.check_carriers(
      asof_test_cursor(
        "[{\"to_vectors\":{\"id\":\"key\",\"vector\":\"embedding\"}},{\"normalize_vectors\":true},{\"score_vectors\":{\"query\":[1,2],\"metric\":\"" +
        metric +
        "\"}},{\"normalize_vectors\":true},{\"vectors\":true}]",
      ),
      [("rows", input)],
      None,
      None,
      {
        max_steps: 5,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap()
    for n in 0..<4 {
      let step = @pipeline.step_at(pipeline, n).unwrap()
      let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
      let expected : Array[VectorRule] = [
        AdmitVectorComponents,
        RequireVectorIdentityUniqueness,
        RequireVectorResources,
      ]
      if n == 1 || n == 3 {
        expected.push(NormalizeVectorArithmetic)
      }
      if n == 2 {
        expected.push(ComputeVectorScores)
        expected.push(OrderVectorScores)
      }
      let actual : Array[VectorRule] = []
      for index in 0..<@pipeline.operation_obligations_count(group) {
        let site : OperationRequirementSite = {
          stage: 0,
          producer_visit: 0,
          step: n,
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
          is @pipeline.VectorRequirement(ResolveVecaProfile | MatchDimensions) {
          assert_true(result is Ok(None))
          continue
        }
        guard result is Ok(Some(VectorExecution(check))) else {
          fail("missing vector binding")
        }
        actual.push(check.rule)
        assert_true(physical_equal(check.site, site))
        assert_true(physical_equal(check.step, step))
        assert_true(physical_equal(check.policy, policy))
        assert_eq(
          check.input,
          if n == 0 {
            @pipeline.Input(0)
          } else {
            @pipeline.Step(n - 1)
          },
        )
        guard step.operation is @pipeline.Vector(operation) else {
          fail("vector operation")
        }
        assert_true(physical_equal(check.operation, operation))
        if n == 2 {
          assert_eq(
            @vector.metric(operation),
            Some(
              match metric {
                "dot" => Dot
                "l2" => L2
                _ => Cosine
              },
            ),
          )
          let query = @vector.query(operation).unwrap()
          assert_eq(@vector.query_value_count(query), Some(2))
          assert_eq(@vector.query_value_at(query, 0), Some(1.0))
          assert_eq(@vector.query_value_at(query, 1), Some(2.0))
        }
        assert_eq(
          operation_execution_phase(VectorExecution(check)),
          if check.rule == AdmitVectorComponents ||
            check.rule == RequireVectorIdentityUniqueness ||
            check.rule == RequireVectorResources {
            BeforeOperationInputUse
          } else {
            BeforeOperationOutput
          },
        )
        assert_eq(
          operation_execution_failure(VectorExecution(check)),
          RejectOperationOutput,
        )
        assert_true(
          vector_execution_check({ ..site, index: 99, }, policy)
          is Err(ForeignOccurrence(_)),
        )
        assert_true(
          vector_execution_check({ ..site, step: 99, }, policy)
          is Err(ForeignOccurrence(99)),
        )
        assert_true(
          vector_execution_check({ ..site, group: 1, }, policy)
          is Err(ForeignOccurrence(_)),
        )
      }
      assert_eq(actual, expected)
    }
    let normalized = @pipeline.step_at(pipeline, 3).unwrap()
    guard normalized.operation is @pipeline.Vector(operation) else {
      fail("normalization")
    }
    assert_true(@vector.query(operation) is None)
    assert_true(@vector.metric(operation) is None)
    assert_true(
      physical_equal(@vector.input(operation), @vector.output(operation)),
    )
  }
}
