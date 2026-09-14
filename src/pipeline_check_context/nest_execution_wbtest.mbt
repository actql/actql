///|
test "nest execution bindings retain both roles without resolving static limits" {
  for rows in ["[]", "[{\"id\":1},{\"id\":1}]"] {
    let pipeline = @pipeline.check_with_evidence(
      asof_test_cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
        rows +
        "},\"as\":\"seed\"},{\"filter\":\"TRUE\"},{\"nest\":{\"with\":\"seed\",\"on\":[{\"left\":\"id\",\"right\":\"id\"},{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"children\",\"fields\":[\"id\"],\"max_items\":3}}]",
      ),
      [],
      None,
      None,
      {
        max_steps: 3,
        max_work: 100000,
        max_text_bytes: 100000,
        max_nodes: 10000,
        max_tokens: 10000,
        max_depth: 100,
      },
    ).unwrap()
    let step = @pipeline.step_at(pipeline, 2).unwrap()
    let obligations = @pipeline.operation_obligation_group_at(step.operation, 0).unwrap()
    let mut execution = 0
    let mut unresolved = 0
    for index in 0..<@pipeline.operation_obligations_count(obligations) {
      let site : OperationRequirementSite = {
        stage: 2,
        producer_visit: 3,
        step: 2,
        group: 0,
        index,
        pipeline,
        obligations,
        requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
      }
      match nest_execution_check(site).unwrap() {
        Some(NestExecution(check)) => {
          execution += 1
          assert_true(physical_equal(check.site, site))
          assert_true(physical_equal(check.step, step))
          assert_eq(check.parent, @pipeline.Step(1))
          assert_eq(check.child, @pipeline.Step(0))
          assert_eq(@nest.key_count(check.operation), 2)
          assert_eq(@nest.item_guard(check.operation), Some(@nest.Literal(3L)))
          match site.requirement {
            @pipeline.NestRequirement(@nest.ValidateOutputsBeforeConsumers) =>
              assert_eq(check.rule, AdmitAttachedValues)
            @pipeline.NestRequirement(@nest.PropagatePolicyAndCompleteness) =>
              assert_eq(check.rule, PreserveNestedDependencies)
            _ => fail("a static obligation became an execution permission")
          }
          assert_eq(
            operation_execution_phase(NestExecution(check)),
            BeforeOperationOutput,
          )
          assert_eq(
            operation_execution_failure(NestExecution(check)),
            RejectOperationOutput,
          )
          for
            bad in [
              { ..site, step: 0, },
              { ..site, group: 1, },
              { ..site, index: 2147483647, },
            ] {
            assert_true(nest_execution_check(bad) is Err(ForeignOccurrence(_)))
          }
          guard direct_execution_candidate(
              site,
              sequence_limit_policy(false),
              Ok(None),
              Ok(None),
            )
            is Ok(Some(NestExecution(selected))) else {
            fail("nest execution was not connected to the shared dispatcher")
          }
          assert_eq(selected.rule, check.rule)
        }
        None => {
          unresolved += 1
          assert_true(
            site.requirement
            is @pipeline.NestRequirement(
              @nest.ResolveTotalOrder
              | ResolveItemLimit
              | ResolveNestedEnvelope
            ),
          )
        }
        _ => fail("foreign execution rule")
      }
    }
    assert_eq(execution, 2)
    assert_eq(unresolved, 3)
  }
}
