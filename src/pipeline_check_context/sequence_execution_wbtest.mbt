///|
test "sequence input duties retain occurrence roles without claiming matching success" {
  for events in [false, true] {
    for empty in [false, true] {
      for overlap in ["allow", "disallow"] {
        for contiguity in ["adjacent", "subsequence"] {
          let rows = if empty {
            "[]"
          } else {
            "[{\"id\":1,\"time\":2},{\"id\":1,\"time\":1}]"
          }
          let text = "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"time\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
            rows +
            "},\"as\":\"rows\"}," +
            (if events {
              "{\"to_events\":{\"id\":\"id\",\"time\":\"time\"}},"
            } else {
              ""
            }) +
            "{\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"time\",\"pattern\":[{\"as\":\"a\",\"where\":\"TRUE\"},{\"as\":\"b\",\"where\":\"TRUE\"}],\"within\":10,\"overlap\":\"" +
            overlap +
            "\",\"contiguity\":\"" +
            contiguity +
            "\"}}]"
          let pipeline = @pipeline.check_with_evidence(
            asof_test_cursor(text),
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
          let step_index = if events { 2 } else { 1 }
          let step = @pipeline.step_at(pipeline, step_index).unwrap()
          let mut checked = 0
          let mut retained = 0
          for
            group in 0..<@pipeline.operation_obligation_group_count(
              step.operation,
            ) {
            let obligations = @pipeline.operation_obligation_group_at(
              step.operation,
              group,
            ).unwrap()
            for index in 0..<@pipeline.operation_obligations_count(obligations) {
              let site : OperationRequirementSite = {
                stage: 0,
                producer_visit: 1,
                step: step_index,
                group,
                index,
                pipeline,
                obligations,
                requirement: @pipeline.operation_obligations_at(
                  obligations, index,
                ).unwrap(),
              }
              match sequence_execution_check(site) {
                Ok(Some(SequenceExecution(check))) => {
                  checked += 1
                  assert_true(physical_equal(check.site, site))
                  assert_true(physical_equal(check.step, step))
                  assert_eq(check.input, step.input.unwrap())
                  guard step.operation is @pipeline.Sequence(operation) else {
                    fail("sequence")
                  }
                  assert_true(physical_equal(check.operation, operation))
                  assert_eq(
                    @relation.sequence_identity(operation),
                    @schema.Unqualified("id"),
                  )
                  assert_eq(
                    @relation.sequence_time(operation),
                    @schema.Unqualified("time"),
                  )
                  let expected = match check.rule {
                    AdmitSequenceValues => @relation.ValidateEventValues
                    ValidateSequenceIdentities => @relation.UniqueEventIdentity
                    OrderSequenceEvents => @relation.AscendingEventOrder
                  }
                  assert_true(
                    site.requirement is @pipeline.SequenceRequirement(actual) &&
                    actual == expected,
                  )
                  assert_eq(
                    operation_execution_phase(SequenceExecution(check)),
                    BeforeOperationInputUse,
                  )
                  assert_eq(
                    operation_execution_failure(SequenceExecution(check)),
                    RejectOperationOutput,
                  )
                  assert_true(
                    sequence_execution_check({ ..site, step: 0, })
                    is Err(ForeignOccurrence(_)),
                  )
                  assert_true(
                    sequence_execution_check({ ..site, index: 999, })
                    is Err(ForeignOccurrence(_)),
                  )
                }
                Ok(None) =>
                  if site.requirement
                    is @pipeline.SequenceRequirement(
                      BoundedMatchSearch
                      | AtomicMatchLimits
                    ) {
                    retained += 1
                  }
                _ => fail("unexpected sequence disposition")
              }
            }
          }
          assert_eq(checked, 3)
          assert_eq(retained, 2)
        }
      }
    }
  }
}
