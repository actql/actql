///|
test "analytic calls retain filter demand and per-frame unresolved resource and numeric checks" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      scalar_steps(
        (
          #|{"analytic":{"partition_by":["id","id"],"order_by":[{"id":"asc"}],"frame":{"start":"current_row","end":"current_row"},"functions":{"z":{"fn":"sum","field":"id"},"a":{"fn":"count","expr":"id / 0","filter":"FALSE"},"items":{"fn":"array_agg","field":"id"},"text":{"fn":"string_agg","field":"x","delimiter":","},"first":{"fn":"first_value","expr":"id"},"variance":{"fn":"var_pop","field":"id"}}}}
        ),
      ),
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
  let requirements = operation_resolution_requirements(index)
  let mut peers = 0
  let mut demands = 0
  let mut aggregates = 0
  let mut contracts = 0
  let mut statistical = 0
  let mut collection = 0
  let mut numeric = 0
  for i in 0..<operation_resolution_count(index) {
    let site = operation_requirements_at(requirements, i).unwrap()
    guard site.requirement is @pipeline.RelationRequirement(pending) else {
      continue
    }
    match operation_resolution_at(index, i).unwrap() {
      Execution(AnalyticExecution(check)) => {
        assert_true(physical_equal(check.site, site))
        assert_true(
          physical_equal(
            check.step,
            @pipeline.step_at(site.pipeline, site.step).unwrap(),
          ),
        )
        assert_eq(check.step.input, Some(check.input))
        assert_true(
          physical_equal(
            @relation.analytic(check.operation).unwrap(),
            check.analytic,
          ),
        )
        assert_eq(
          operation_execution_phase(AnalyticExecution(check)),
          BeforeOperationOutput,
        )
        assert_eq(
          operation_execution_failure(AnalyticExecution(check)),
          RejectOperationOutput,
        )
        let call = match check.rule {
          EnforceArrayItems(_, _) => fail("array bounds need explicit linking")
          EnforceStringBytes(_, _) =>
            fail("string bounds need explicit linking")
          PartitionAuthoredPeers => {
            assert_eq(pending.kind, @relation.AnalyticPeerOrder)
            assert_eq(@relation.analytic_partition_count(check.analytic), 2)
            assert_eq(@relation.analytic_term_count(check.operation), 1)
            peers += 1
            None
          }
          EvaluateCallDemands => {
            assert_eq(pending.kind, @relation.AnalyticFrameDemand)
            assert_eq(@relation.analytic_call_count(check.analytic), 6)
            assert_true(@relation.analytic_frame(check.analytic) is Some(_))
            demands += 1
            None
          }
          EvaluateAggregate(call) => {
            assert_eq(pending.kind, @relation.AggregateDemand)
            if call.name == "a" {
              guard call.function is @relation.Aggregate(aggregate) else {
                fail("not aggregate")
              }
              assert_true(@relation.aggregate_filter(aggregate) is Some(_))
              assert_true(
                @relation.aggregate_argument(aggregate)
                is @relation.Expression(_),
              )
            }
            aggregates += 1
            Some(call)
          }
          ValidateResultContract(call) => {
            assert_eq(pending.kind, @relation.AggregateEnvelope)
            assert_true(
              call.name == "a" || call.name == "z" || call.name == "variance",
            )
            contracts += 1
            Some(call)
          }
          EnforceStatisticalLaw(call, law) => {
            assert_eq(pending.kind, @relation.StatisticalAggregateLaw)
            assert_eq(call.name, "variance")
            assert_true(law is PopulationVariance)
            statistical += 1
            Some(call)
          }
        }
        if call is Some(call) {
          assert_true(
            physical_equal(
              call,
              @relation.analytic_call_for_validation(check.analytic, site.index).unwrap(),
            ),
          )
        }
      }
      Unresolved => {
        if pending.kind is @relation.NumericAggregateObservation {
          numeric += 1
        }
        if pending.kind is @relation.AggregateEnvelope {
          collection += 1
        }
      }
      _ => ()
    }
  }
  assert_true(peers > 1)
  assert_eq(demands, peers)
  assert_eq(aggregates, peers * 5)
  assert_eq(contracts, peers * 3)
  assert_eq(statistical, peers)
  assert_eq(collection, peers * 2)
  assert_eq(numeric, peers)
  assert_true(
    close_program_operations(index, 10000000, 1000)
    is Err(IncompleteResolution(_)),
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
}
