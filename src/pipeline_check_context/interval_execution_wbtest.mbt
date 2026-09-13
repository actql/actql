///|
test "interval endpoint and order links retain exact inputs without closing resources" {
  for timestamp in [false, true] {
    for mode in ["point_in_interval", "overlap"] {
      for kind in ["inner", "left", "semi", "anti"] {
        for ordered_right in [false, true] {
          let domain = if timestamp { "timestamp" } else { "number" }
          let data = if timestamp {
            "\"2020-01-01T00:00:00.000Z\""
          } else {
            "1"
          }
          let source = @source.parse_json(
            "[{\"values\":{\"schema\":{\"clock\":{\"type\":\"" +
            domain +
            "\",\"nullable\":false}},\"rows\":[{\"clock\":" +
            data +
            "}]},\"as\":\"seed\"},{\"interval_join\":{\"with\":\"" +
            (if ordered_right { "seed" } else { "unknown" }) +
            "\",\"kind\":\"" +
            kind +
            "\",\"mode\":\"" +
            mode +
            "\",\"on\":[],\"left\":" +
            (if mode == "overlap" {
              "{\"start\":\"clock\",\"end\":\"clock\"}"
            } else {
              "{\"time\":\"clock\"}"
            }) +
            ",\"right\":{\"start\":\"clock\",\"end\":\"clock\"}}}]",
            { max_input_bytes: 10000, max_nodes: 1000, max_depth: 30, },
          ).unwrap()
          let cursor = @decode.admit(source, {
            max_nodes: 1000,
            max_depth: 30,
            max_string_bytes: 10000,
            max_total_string_bytes: 10000,
          }).unwrap()
          let schema = @schema.from_fields(
            [
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
            max_fields=1,
            max_name_bytes=20,
          ).unwrap()
          let pipeline = @pipeline.check(
            cursor,
            [("unknown", schema)],
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
          let step = @pipeline.step_at(pipeline, 1).unwrap()
          let obligations = @pipeline.operation_obligation_group_at(
            step.operation,
            0,
          ).unwrap()
          let mut endpoints = 0
          let mut clocks = 0
          let mut orders = 0
          let mut pending_resources = 0
          for index in 0..<@pipeline.operation_obligations_count(obligations) {
            let requirement = @pipeline.operation_obligations_at(
              obligations, index,
            ).unwrap()
            let site = {
              stage: 0,
              producer_visit: 0,
              step: 1,
              group: 0,
              index,
              pipeline,
              obligations,
              requirement,
            }
            let result = interval_execution_check(site).unwrap()
            match result {
              Some(IntervalExecution(check)) => {
                assert_true(physical_equal(check.site, site))
                assert_true(physical_equal(check.step, step))
                assert_eq(check.left, @pipeline.Step(0))
                assert_eq(
                  check.right,
                  if ordered_right {
                    @pipeline.Step(0)
                  } else {
                    @pipeline.Input(0)
                  },
                )
                assert_eq(@pipeline.input_occurrence_count(check.step), 2)
                assert_eq(check.timestamp, timestamp)
                assert_eq(
                  check.right_time,
                  Interval(Unqualified("clock"), Unqualified("clock")),
                )
                assert_eq(
                  check.left_time is Point(_),
                  mode == "point_in_interval",
                )
                assert_eq(
                  operation_execution_failure(IntervalExecution(check)),
                  RejectOperationOutput,
                )
                match check.rule {
                  AdmitAllIntervalEndpoints => endpoints += 1
                  AdmitSafeIntegerClocks => {
                    clocks += 1
                    assert_false(timestamp)
                  }
                  PreserveIntervalOccurrenceOrder => {
                    orders += 1
                    let left_only = kind == "semi" || kind == "anti"
                    assert_eq(
                      check.output_order is Some(_),
                      ordered_right || left_only,
                    )
                    if check.output_order is Some(order) {
                      let expected = @pipeline.logical_order(pipeline, Step(1)).unwrap()
                      assert_true(physical_equal(order, expected))
                      assert_eq(
                        @pipeline.order_dependency_count(order),
                        if left_only {
                          1
                        } else {
                          2
                        },
                      )
                    }
                  }
                }
                assert_eq(
                  operation_execution_phase(IntervalExecution(check)),
                  if check.rule == PreserveIntervalOccurrenceOrder {
                    BeforeOperationOutput
                  } else {
                    BeforeOperationInputUse
                  },
                )
                // A different checked step cannot inherit this temporal obligation.
                assert_true(
                  interval_execution_check({ ..site, step: 0, })
                  is Err(ForeignOccurrence(_)),
                )
              }
              None => {
                assert_true(
                  requirement
                  is @pipeline.IntervalJoinRequirement(ResolveProductBound) ||
                  requirement
                  is @pipeline.IntervalJoinRequirement(ResolveOutputLimit) ||
                  requirement
                  is @pipeline.IntervalJoinRequirement(ResolveSearchWork),
                )
                pending_resources += 1
              }
              _ => fail("wrong execution family")
            }
          }
          assert_eq(endpoints, 1)
          assert_eq(clocks, if timestamp { 0 } else { 1 })
          assert_eq(orders, 1)
          assert_eq(pending_resources, 3)
          // Equal endpoints are intentionally not evaluated here. Every interval,
          // including unmatched rows, must pass the retained pre-matching check.
        }
      }
    }
  }
}
