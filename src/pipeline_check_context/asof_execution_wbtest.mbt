///|
test "asof execution retains clocks identity selection and generated order independently" {
  for left_timestamp in [false, true] {
    for right_timestamp in [false, true] {
      for kind in ["left", "inner"] {
        for direction in ["backward", "forward", "nearest"] {
          let source = @source.parse_json(
            "[{\"from\":\"l\",\"asof_join\":{\"with\":\"r\",\"kind\":\"" +
            kind +
            "\",\"by\":[],\"left_id\":\"id\",\"left_time\":\"clock\",\"right_time\":\"clock\",\"direction\":\"" +
            direction +
            "\",\"tolerance\":100,\"select\":{\"id\":\"left.id\",\"matched\":\"right.clock\"}}}]",
            { max_input_bytes: 10000, max_nodes: 1000, max_depth: 30, },
          ).unwrap()
          let cursor = @decode.admit(source, {
            max_nodes: 1000,
            max_depth: 30,
            max_string_bytes: 10000,
            max_total_string_bytes: 10000,
          }).unwrap()
          let schema = (timestamp : Bool) => {
            @schema.from_fields(
              [
                (
                  Unqualified("id"),
                  @contract.primitive(NumberType, nullable=false),
                ),
                (
                  Unqualified("clock"),
                  @contract.primitive(
                    if timestamp {
                      TimestampType
                    } else {
                      NumberType
                    },
                    nullable=false,
                  ),
                ),
              ],
              max_fields=2,
              max_name_bytes=100,
            ).unwrap()
          }
          let pipeline = @pipeline.check(
            cursor,
            [("l", schema(left_timestamp)), ("r", schema(right_timestamp))],
            None,
            None,
            {
              max_steps: 10,
              max_work: 100000,
              max_text_bytes: 100000,
              max_nodes: 10000,
              max_tokens: 10000,
              max_depth: 100,
            },
          ).unwrap()
          let step = @pipeline.step_at(pipeline, 0).unwrap()
          let contracts : CoreContractBuilder = {
            limits: { max_work: 2, max_roots: 2, max_bodies: 2, max_edges: 0, },
            roots: [],
            bodies: [],
            seen: {},
            dependencies: {},
            work: 0,
            edges: 0,
            hash_limits: { max_bytes: 0, max_nodes: 0, max_depth: 0, },
            hash_bytes: 0,
            hash_nodes: 0,
          }
          core_operation_count_root(contracts, step.operation, 2, 3, 0)
          assert_eq(contracts.work, 2)
          assert_eq(contracts.roots.length(), 2)
          assert_eq(contracts.roots[0].site, OperationAsOfSearchRules(2, 3, 0))
          assert_eq(contracts.roots[0].body, AsOfSearchRules)
          assert_eq(contracts.roots[1].body, JoinCountRules)
          let obligations = @pipeline.operation_obligation_group_at(
            step.operation,
            0,
          ).unwrap()
          let mut linked = 0
          let mut unclosed = 0
          for index in 0..<@pipeline.operation_obligations_count(obligations) {
            let requirement = @pipeline.operation_obligations_at(
              obligations, index,
            ).unwrap()
            let site = {
              stage: 0,
              producer_visit: 0,
              step: 0,
              group: 0,
              index,
              pipeline,
              obligations,
              requirement,
            }
            match asof_execution_check(site).unwrap() {
              Some(AsOfExecution(check)) => {
                linked += 1
                assert_true(physical_equal(check.site, site))
                assert_true(physical_equal(check.step, step))
                assert_eq(
                  (check.left, check.right),
                  (@pipeline.Input(0), @pipeline.Input(1)),
                )
                assert_eq(
                  (check.left_timestamp, check.right_timestamp),
                  (left_timestamp, right_timestamp),
                )
                assert_eq(check.left_time, Unqualified("clock"))
                assert_eq(check.right_time, Unqualified("clock"))
                assert_eq(@join.asof_identity(check.operation), [
                  Unqualified("id"),
                ])
                assert_eq(@join.asof_completed_tie_break(check.operation), [])
                assert_eq(
                  @join.asof_direction(check.operation),
                  match direction {
                    "backward" => @evidence.Backward
                    "forward" => @evidence.Forward
                    _ => @evidence.Nearest
                  },
                )
                assert_eq(
                  @pipeline.order_origin(check.output_order),
                  @pipeline.Step(0),
                )
                assert_eq(
                  @pipeline.order_dependency_count(check.output_order),
                  0,
                )
                assert_true(
                  physical_equal(
                    check.output_order,
                    @pipeline.logical_order(pipeline, @pipeline.Step(0)).unwrap(),
                  ),
                )
                assert_eq(
                  operation_execution_failure(AsOfExecution(check)),
                  RejectOperationOutput,
                )
                assert_eq(
                  operation_execution_phase(AsOfExecution(check)),
                  match check.rule {
                    AdmitAsOfClocksAndDistances
                    | ValidateAsOfLeftIdentity
                    | ValidateAsOfKey(_, _) => BeforeOperationInputUse
                    SelectAsOfMatch | OrderAsOfOutput => BeforeOperationOutput
                  },
                )
                assert_true(
                  asof_execution_check({ ..site, step: 1, })
                  is Err(ForeignOccurrence(1)),
                )
                assert_true(
                  asof_execution_check({ ..site, index: 100, })
                  is Err(ForeignOccurrence(0)),
                )
              }
              None => {
                unclosed += 1
                assert_true(
                  requirement
                  is @pipeline.AsOfRequirement(
                    ResolveSearchWork
                    | ResolveOutputLimit
                    | ResolveTeaProfile
                  ),
                )
              }
              _ => fail("wrong execution kind")
            }
          }
          assert_eq((linked, unclosed), (4, 3))
        }
      }
    }
  }
}
