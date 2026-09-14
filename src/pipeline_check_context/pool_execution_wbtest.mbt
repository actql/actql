///|
test "pool bindings retain member completion separately from grouping identity" {
  let policy = sequence_limit_policy(false)
  for numeric_id in [false, true] {
    let rows = @carrier.rows(
      [
        (
          Unqualified("id"),
          Some(
            @contract.primitive(
              if numeric_id {
                NumberType
              } else {
                StringType
              },
              nullable=false,
            ),
          ),
        ),
        (
          Unqualified("group"),
          Some(@contract.primitive(NumberType, nullable=false)),
        ),
        (
          Unqualified("v"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=20,
    ).unwrap()
    for vectors in [false, true] {
      for reduction in ["mean", "sum", "max"] {
        let pipeline = @pipeline.check_carriers(
          asof_test_cursor(
            "[" +
            (if vectors {
              "{\"to_vectors\":{\"id\":\"id\",\"vector\":\"v\"}}"
            } else {
              "{\"assert_rows\":{\"unique_by\":[\"id\"]}}"
            }) +
            ",{\"pool_vectors\":{\"vector\":\"v\",\"by\":[\"group\",\"id\"],\"method\":\"" +
            reduction +
            "\"}}]",
          ),
          [("rows", @carrier.relation(rows))],
          None,
          None,
          {
            max_steps: 2,
            max_work: 100000,
            max_text_bytes: 100000,
            max_nodes: 10000,
            max_tokens: 10000,
            max_depth: 100,
          },
        ).unwrap()
        let step = @pipeline.step_at(pipeline, 1).unwrap()
        guard step.operation is @pipeline.Pool(operation) else { fail("pool") }
        let options = @vector.pooled_options(operation)
        assert_eq(@vector.pool_group_count(options), 2)
        assert_eq(
          @vector.pool_group_at(options, 0),
          Some(@schema.Unqualified("group")),
        )
        assert_eq(
          @vector.pool_group_at(options, 1),
          Some(@schema.Unqualified("id")),
        )
        assert_true(@vector.pool_group_at(options, -1) is None)
        assert_true(@vector.pool_group_at(options, 2) is None)
        assert_eq(
          @vector.pool_method(options),
          match reduction {
            "mean" => Mean
            "sum" => Sum
            _ => Max
          },
        )
        assert_eq(
          @vector.pool_encodes_member_key(operation),
          !vectors && numeric_id,
        )
        assert_eq(@vector.pool_key_declaration(operation) is Some(_), !vectors)
        let group = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
        let mut encoded = 0
        let mut native_order = 0
        let mut encoded_order = 0
        let mut resources = 0
        for index in 0..<@pipeline.operation_obligations_count(group) {
          let site : OperationRequirementSite = {
            stage: 0,
            producer_visit: 0,
            step: 1,
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
          if site.requirement is @pipeline.PoolRequirement(ResolvePoolProfile) {
            assert_true(result is Ok(None))
            continue
          }
          guard result is Ok(Some(PoolExecution(check))) else {
            fail("missing pool binding")
          }
          assert_true(physical_equal(check.step, step))
          assert_true(physical_equal(check.operation, operation))
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.policy, policy))
          assert_eq(check.input, @pipeline.Step(0))
          let input_phase = match check.rule {
            ValidateDeclaredPoolKey(_)
            | JournalPoolMemberIdentity
            | EncodePoolMemberKeyByScalarLengths
            | AdmitPoolVectorComponents
            | ValidatePoolMemberIdentityGlobally
            | MatchPoolDimensions
            | ResolvePoolResources => true
            _ => false
          }
          assert_eq(
            operation_execution_phase(PoolExecution(check)),
            if input_phase {
              BeforeOperationInputUse
            } else {
              BeforeOperationOutput
            },
          )
          match check.rule {
            EncodePoolMemberKeyByScalarLengths => encoded += 1
            OrderPoolMembersByEncodedIdentity => encoded_order += 1
            OrderPoolMembersByIdentity => native_order += 1
            ResolvePoolResources => {
              resources += 1
              assert_eq(pool_resource_count(check), 5)
              assert_eq(pool_resource_at(check, 0), Some(InputAndGroupingWork))
              assert_eq(pool_resource_at(check, 1), Some(FoldWork))
              assert_eq(pool_resource_at(check, 2), Some(MemberOrderingWork))
              assert_eq(
                pool_resource_at(check, 3),
                Some(ValueAndTemporaryBytes),
              )
              assert_eq(pool_resource_at(check, 4), Some(RetainedPoolState))
              assert_true(pool_resource_at(check, -1) is None)
              assert_true(pool_resource_at(check, 5) is None)
            }
            _ => ()
          }
          assert_eq(
            operation_execution_failure(PoolExecution(check)),
            RejectOperationOutput,
          )
          assert_true(
            pool_execution_check({ ..site, step: 99, }, policy)
            is Err(ForeignOccurrence(99)),
          )
          assert_true(
            pool_execution_check({ ..site, group: 1, }, policy)
            is Err(ForeignOccurrence(1)),
          )
          assert_true(
            pool_execution_check({ ..site, index: 99, }, policy)
            is Err(ForeignOccurrence(1)),
          )
        }
        assert_eq(resources, 1)
        assert_eq(encoded, if !vectors && numeric_id { 1 } else { 0 })
        assert_eq(encoded_order, encoded)
        assert_eq(native_order, 1 - encoded)
      }
    }
  }
}
