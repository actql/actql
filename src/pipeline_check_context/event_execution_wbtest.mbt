///|
test "event execution retains roles and future validation across empty and duplicate inputs" {
  for timestamp in [false, true] {
    for empty in [false, true] {
      for kind in ["bridge", "mark", "drop", "dedupe", "session"] {
        let domain = if timestamp { "timestamp" } else { "number" }
        let clock = if timestamp { "\"2020-01-01T00:00:00.000Z\"" } else { "1" }
        let row = "{\"id\":2,\"at\":" + clock + "}"
        let tail = match kind {
          "bridge" => ""
          "mark" | "drop" =>
            ",{\"watermark_events\":{\"watermark_ms\":-0.5,\"policy\":\"" +
            kind +
            "\"}}"
          "dedupe" =>
            ",{\"dedupe_events\":{\"by\":[\"id\",\"id\"],\"order_by\":[{\"at\":\"asc\"}]}}"
          _ => ",{\"session\":{\"by\":[],\"gap\":\"1s\"}}"
        }
        let source = asof_test_cursor(
          "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"" +
          domain +
          "\",\"nullable\":false}},\"rows\":[" +
          (if empty { "" } else { row + "," + row }) +
          "]},\"as\":\"seed\"},{\"to_events\":{\"id\":\"id\",\"time\":\"at\"}}" +
          tail +
          "]",
        )
        let result = @pipeline.check_with_evidence(source, [], None, None, {
          max_steps: 3,
          max_work: 100000,
          max_text_bytes: 100000,
          max_nodes: 10000,
          max_tokens: 10000,
          max_depth: 100,
        })
        let pipeline = result.unwrap()
        let ordinal = if kind == "bridge" { 1 } else { 2 }
        let step = @pipeline.step_at(pipeline, ordinal).unwrap()
        guard step.operation is @pipeline.Event(operation) else {
          fail("event")
        }
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
            step: ordinal,
            group: 0,
            index,
            pipeline,
            obligations,
            requirement,
          }
          match event_execution_check(site).unwrap() {
            Some(EventExecution(check)) => {
              linked += 1
              assert_true(physical_equal(check.site, site))
              assert_true(physical_equal(check.step, step))
              assert_true(physical_equal(check.operation, operation))
              assert_eq(check.input, @pipeline.Step(ordinal - 1))
              assert_eq(
                operation_execution_failure(EventExecution(check)),
                RejectOperationOutput,
              )
              match check.rule {
                AdmitEventValues
                | ValidateEventIdentities
                | ConvertEventClock =>
                  assert_eq(
                    operation_execution_phase(EventExecution(check)),
                    BeforeOperationInputUse,
                  )
                ClassifyEventWatermark => {
                  assert_eq(@event.watermark(check.operation), Some(-0.5))
                  assert_eq(
                    @event.policy(check.operation),
                    Some(if kind == "mark" { @event.Mark } else { @event.Drop }),
                  )
                  assert_eq(
                    operation_execution_phase(EventExecution(check)),
                    BeforeOperationOutput,
                  )
                }
                SelectEventRepresentative => {
                  guard @event.options(check.operation) is Dedupe(spec) else {
                    fail("dedupe")
                  }
                  assert_eq(@event.dedupe_key_count(spec), 2)
                  assert_eq(
                    operation_execution_phase(EventExecution(check)),
                    BeforeOperationOutput,
                  )
                }
              }
              assert_true(
                event_execution_check({ ..site, step: 0, })
                is Err(ForeignOccurrence(_)),
              )
              assert_true(
                event_execution_check({ ..site, index: 999, })
                is Err(ForeignOccurrence(_)),
              )
            }
            None => {
              unclosed += 1
              assert_true(
                requirement
                is @pipeline.EventRequirement(
                  ResolveTeaProfile
                  | ResolveEventResources
                  | SessionArithmetic
                  | SessionIdentity
                ),
              )
            }
            _ => fail("wrong check")
          }
        }
        assert_eq(
          linked,
          2 +
          (if timestamp { 1 } else { 0 }) +
          (if kind == "mark" || kind == "drop" || kind == "dedupe" {
            1
          } else {
            0
          }),
        )
        assert_eq(unclosed, if kind == "session" { 4 } else { 2 })
        guard @event.output(operation) is @carrier.EventValue(events) else {
          fail("carrier")
        }
        assert_eq(events.identity.name, Unqualified("id"))
        assert_eq(events.time.name, Unqualified("at"))
        assert_eq(
          events.clock_encoding,
          if timestamp {
            @carrier.UtcTimestamp
          } else {
            @carrier.Milliseconds
          },
        )
      }
    }
  }
}
