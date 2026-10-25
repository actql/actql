///|
fn watermark_parameter_declarations() -> @parameters.Declarations {
  @parameters.read_declarations(
    Some(cursor("{\"threshold\":{\"type\":\"number\",\"nullable\":false}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
}

///|
fn watermark_parameter_owner(
  producer : @lower.BoundPrepared,
  policy : String,
  threshold : Double,
  parameter : Bool,
) -> @lower.BoundPrepared {
  let declarations = watermark_parameter_declarations()
  let checked = @pipeline.check_with_evidence(
    cursor(
      "[{\"watermark_events\":{\"watermark_ms\":" +
      (if parameter {
        "{\"$param\":\"threshold\"}"
      } else {
        threshold.to_string()
      }) +
      ",\"policy\":\"" +
      policy +
      "\"}}]",
    ),
    [
      (
        "prior",
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(producer)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    ],
    if parameter {
      Some(declarations)
    } else {
      None
    },
    Some(cursor("\"prior\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let bound = if parameter {
    guard @parameters.bind(
        declarations,
        Some(cursor("{\"threshold\":" + threshold.to_string() + "}")),
        { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
      ).unwrap()
      is @parameters.Ready(values) else {
      abort("missing threshold")
    }
    Some(values)
  } else {
    None
  }
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    bound,
    max_parameters=1,
    max_name_bytes=100,
  ).unwrap()
}

///|
test "watermark binding agrees with literals across policies thresholds quanta and empty inputs" {
  for threshold in [-2.5, 0.0, 1.5] {
    for policy in ["mark", "drop"] {
      for empty in [false, true] {
        let producer = producer_owner(false)
        let source_builder = @records.prepare_output(
          producer,
          @pipeline.Step(0),
          limits(),
          4096L,
          () => true,
        ).unwrap()
        // Deliberately unsorted occurrence order with equality in the middle.
        let times = [threshold + 1.0, threshold, threshold - 1.0]
        if !empty {
          for i in 0..<3 {
            @records.append_record(source_builder, [
              (@schema.Unqualified("event_id"), number(i.to_double() + 1.0)),
              (@schema.Unqualified("occurred_at"), number(times[i])),
              (@schema.Unqualified("payload"), text("p" + i.to_string())),
            ]).unwrap()
          }
        }
        let source = @records.finish_output(source_builder).unwrap()
        for parameter in [false, true] {
          let owner = watermark_parameter_owner(
            producer, policy, threshold, parameter,
          )
          // A second binding must not replace the first owner's snapshot.
          let other = watermark_parameter_owner(
            producer,
            policy,
            threshold + 100.0,
            true,
          )
          guard @lower.sequence_step(sequence(other), 0)
            is Some(@lower.EventStep(other_event)) else {
            fail("missing event")
          }
          assert_eq(
            @lower.event_watermark(other_event),
            Some(threshold + 100.0),
          )
          for quantum in [1, 7, 64] {
            let input = @records.prepare_producer_read(
              owner, 0, producer, source,
            ).unwrap()
            let execution = start_watermark(
              @bounded.control(),
              sequence(owner),
              0,
              input,
              limits(),
              4096L,
              () => true,
            ).unwrap()
            let mut completed = None
            for _ in 0..<1000 {
              match advance_watermark(execution, quantum).unwrap() {
                Continue(..) => ()
                Complete(output, ..) => {
                  completed = Some(output)
                  break
                }
                _ => fail("bounded watermark must complete")
              }
            }
            let output = completed.unwrap()
            assert_eq(cleanup_watermark(execution), Ok(true))
            let storage = @records.completed_storage(output).unwrap()
            let count = if empty { 0 } else if policy == "drop" { 2 } else { 3 }
            assert_eq(@storage.record_count(storage), count)
            for i in 0..<count {
              guard field(storage, i, "event_id").value is @value.Number(id) else {
                fail("wrong event_id type")
              }
              assert_eq(id, i.to_double() + 1.0)
              guard field(storage, i, "occurred_at").value
                is @value.Number(clock) else {
                fail("wrong occurred_at type")
              }
              assert_eq(clock, times[i])
              guard field(storage, i, "payload").value is @value.Text(payload) else {
                fail("wrong payload type")
              }
              assert_eq(payload, "p" + i.to_string())
              guard field(storage, i, "watermark_ms").value
                is @value.Number(watermark) else {
                fail("wrong watermark_ms type")
              }
              assert_eq(watermark, threshold)
              guard field(storage, i, "late").value is @value.Boolean(late) else {
                fail("wrong late type")
              }
              assert_eq(late, i == 2)
              guard field(storage, i, "watermark_decision").value
                is @value.Text(decision) else {
                fail("wrong watermark_decision type")
              }
              assert_eq(decision, if i == 2 { "mark" } else { "keep" })
            }
            assert_true(@records.discard_completed(output))
            assert_true(@records.producer_read_available(input))
          }
        }
        assert_true(@records.discard_completed(source))
      }
    }
  }
}

///|
test "watermark threshold binding refuses missing null and wrong type" {
  let declarations = watermark_parameter_declarations()
  assert_true(
    @parameters.bind(declarations, None, {
      max_nodes: 100,
      max_depth: 10,
      max_text_bytes: 1000,
    }).unwrap()
    is @parameters.NeedsBindings(_),
  )
  for
    supplied in [
      "{\"threshold\":null}", "{\"threshold\":\"0\"}", "{\"threshold\":true}",
    ] {
    assert_true(
      @parameters.bind(declarations, Some(cursor(supplied)), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      })
      is Err(_),
    )
  }
}

///|
test "watermark threshold binding refuses nonfinite raw numeric input" {
  let declarations = watermark_parameter_declarations()
  for value in [0.0 / 0.0, 1.0 / 0.0, -1.0 / 0.0] {
    let raw = @source.parse_json("{\"threshold\":0}", {
      max_input_bytes: 100,
      max_nodes: 10,
      max_depth: 3,
    }).unwrap()
    guard raw.value is @source.Object(fields) else { fail("object fixture") }
    fields[0] = {
      ..fields[0],
      value: { ..fields[0].value, value: @source.Number(value), },
    }
    let supplied = @decode.admit(raw, {
      max_nodes: 10,
      max_depth: 3,
      max_string_bytes: 100,
      max_total_string_bytes: 100,
    }).unwrap()
    assert_true(
      @parameters.bind(declarations, Some(supplied), {
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      })
      is Err(_),
    )
  }
}
