///|
fn object_result_wire(value : Value) -> String raise {
  let writer = @encode.writer(10000, 10000, 100)
  emit_runtime_value(value, writer)
  @encode.finish(writer)
}

///|
test "property measurement of a borrowed large object yields before consuming it" {
  let count = 2048
  let rows = Array::make(count, "1").join(",")
  let pipeline = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"items\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}}}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"v\":{\"property\":{\"value\":{\"coalesce\":[{\"field\":\"payload\"},{\"literal\":null}]},\"name\":\"items\"}}}}]",
  )
  let expression = @lower.lower_expression(pipeline, 1, 0, {
    max_nodes: 10000,
    max_work: 100000,
    max_depth: 100,
    max_literal_nodes: 10000,
    max_literal_text_bytes: 100000,
  }).unwrap()
  let contract = @contract.read_checked(
    input_cursor(
      (
        #|{"type":"object","nullable":false,"additional_properties":false,"fields":{"items":{"type":"array","nullable":false,"items":{"type":"number","nullable":false}}}}
      ),
    ),
    { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let input = capture(
    @admitted.admit(
      contract,
      @decode.admit(
        @source.parse_json("{\"items\":[" + rows + "]}", {
          max_input_bytes: 10000,
          max_nodes: 10000,
          max_depth: 10,
        }).unwrap(),
        {
          max_nodes: 10000,
          max_depth: 10,
          max_string_bytes: 10000,
          max_total_string_bytes: 10000,
        },
      ).unwrap(),
      { max_nodes: 10000, max_depth: 10, max_text_bytes: 10000, },
    ).unwrap().value,
  )
  let logical = logical_budget(
    {
      max_input_rows: 2L,
      max_value_bytes: 10000L,
      max_live_value_bytes: 100000L,
      max_work: 100000L,
    },
    10000,
    10000,
    100,
  ).unwrap()
  let frame = expression_frame(
    expression,
    Map([("payload", input)]),
    [],
    { remaining: 100000, max_frames: 10, },
    row_workspace(100),
    Some(expression_roots(logical, 10)),
  ).unwrap()
  for _ in 0..<12 {
    assert_true(advance_expression_frame(frame).unwrap() is None)
  }
  assert_true(frame.state is MeasureObjectOperand(_, _))
  assert_eq(logical.work, 3L, msg="no complete-value charge before measurement")
  assert_eq(logical.live, 0L)
  close_expression_frame(frame)
  assert_eq(logical.live, 0L)
  assert_eq(frame.workspace.live, 0)
  assert_eq(object_result_wire(input), "{\"items\":[" + rows + "]}")
}

///|
test "object projection keeps canonical fields and nullable child values" {
  let expression = lowered(
    (
      #|{"object":{"value":{"object":{"risk":{"literal":"high"},"reason":{"if":[{"literal":false},{"literal":"explanation"},{"literal":null}]}}},"outcome":{"literal":"ok"},"input_key":{"object":{"id":{"literal":"a"}}}}}
    ),
  )
  let result = evaluate_expression(expression, Map([]), [], {
    remaining: 1000,
    max_frames: 100,
  }).unwrap()
  assert_eq(
    object_result_wire(result),
    (
      #|{"input_key":{"id":"a"},"outcome":"ok","value":{"reason":null,"risk":"high"}}
    ),
  )
}

///|
test "nested property evaluates once and propagates a nullable receiver" {
  for selected in [true, false] {
    let source = "{\"property\":{\"value\":{\"property\":{\"value\":{\"object\":{\"value\":{\"if\":[{\"literal\":" +
      selected.to_string() +
      "},{\"object\":{\"risk\":{\"literal\":\"high\"}}},{\"literal\":null}]}}},\"name\":\"value\"}},\"name\":\"risk\"}}"
    let result = evaluate_expression(lowered(source), Map([]), [], {
      remaining: 1000,
      max_frames: 100,
    }).unwrap()
    assert_eq(
      object_result_wire(result),
      if selected {
        "\"high\""
      } else {
        "null"
      },
    )
  }
}

///|
test "object construction has fixed independent control and workspace bounds" {
  let expression = lowered(
    (
      #|{"object":{"b":{"literal":2},"a":{"literal":7}}}
    ),
  )
  // Three entry/return pairs, two field-name bytes, two copied field views,
  // and three bounded finalization transitions: exactly thirteen control units.
  // Views (2), continuation (1), builder (1), and two tuple/root triples (6).
  for (work, slots) in [(13, 10), (12, 10), (13, 9)] {
    let frame = expression_frame(
      expression,
      Map([]),
      [],
      { remaining: work, max_frames: 10, },
      row_workspace(slots),
      None,
    ).unwrap()
    let mut polls = 0
    let mut terminal = false
    for _ in 0..<20 {
      polls += 1
      match advance_expression_frame(frame) {
        Ok(None) => ()
        Ok(Some(value)) => {
          assert_eq((work, slots), (13, 10))
          assert_eq(object_result_wire(value.value), "{\"a\":7,\"b\":2}")
          terminal = true
          break
        }
        Err(issue) => {
          assert_eq(
            issue.kind,
            if slots == 9 {
              WorkspaceLimit
            } else {
              ControlLimit
            },
          )
          terminal = true
          break
        }
      }
    }
    assert_true(terminal && polls <= 9)
    assert_eq(frame.workspace.live, 0)
    assert_true(frame.objects.is_empty())
  }
}

///|
test "object cancellation retains input roots and closes partial construction" {
  let logical = test_logical_budget(1000L, 1000L)
  let expression = lowered(
    (
      #|{"object":{"a":{"literal":7},"b":{"literal":2}}}
    ),
  )
  let workspace = row_workspace(10)
  let frame = expression_frame(
    expression,
    Map([]),
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
    Some(expression_roots(logical, 10)),
  ).unwrap()
  // The first member has been appended; the second has not been evaluated.
  for _ in 0..<3 {
    assert_true(advance_expression_frame(frame).unwrap() is None)
  }
  assert_true(logical.live > 0L)
  let work = logical.work
  let builder = frame.objects[0]
  close_expression_frame(frame)
  assert_eq(logical.work, work)
  assert_eq(logical.live, 0L)
  assert_eq(workspace.live, 0)
  assert_true(@admitted.finish_object_value(builder) is None)
  assert_true(advance_expression_frame(frame) is Err(_))
}

///|
test "object and property draining preserve stepped logical accounting" {
  for
    source in [
      (
        #|{"object":{"a":{"literal":7},"b":{"object":{"c":{"literal":2}}}}}
      ),
      (
        #|{"property":{"value":{"object":{"risk":{"literal":"high"}}},"name":"risk"}}
      ),
    ] {
    let a = test_logical_budget(1000L, 1000L)
    let b = test_logical_budget(1000L, 1000L)
    let stepped = resume_test_expression(source, a, 1).unwrap()
    let drained = resume_test_expression(source, b, 1, drain=true).unwrap()
    assert_eq(
      object_result_wire(stepped.value),
      object_result_wire(drained.value),
    )
    release_logical_root(a, stepped.root.unwrap()).unwrap()
    release_logical_root(b, drained.root.unwrap()).unwrap()
    assert_eq((a.work, a.live, a.peak), (b.work, b.live, b.peak))
    assert_eq(a.live, 0L)
  }
}

///|
test "object reserves growing bytes before append and charges its exact weight" {
  let expression = lowered(
    (
      #|{"object":{"a":{"literal":7},"b":{"literal":2}}}
    ),
  )
  // Entries (3), child result/consumption (4), object weight (5): work 12.
  // Parent bytes 13 coexist with its two one-byte child roots: live 15.
  for
    (work, live, bytes) in [
      (12L, 15L, 13L),
      (11L, 15L, 13L),
      (12L, 14L, 13L),
      (12L, 15L, 12L),
    ] {
    let base = test_logical_budget(work, live)
    let budget = { ..base, limits: { ..base.limits, max_value_bytes: bytes, }, }
    let frame = expression_frame(
      expression,
      Map([]),
      [],
      { remaining: 1000, max_frames: 10, },
      row_workspace(10),
      Some(expression_roots(budget, 10)),
    ).unwrap()
    let mut terminal = false
    for _ in 0..<100 {
      match advance_expression_frame(frame) {
        Ok(None) => ()
        Ok(Some(value)) => {
          assert_eq((work, live, bytes), (12L, 15L, 13L))
          assert_eq(budget.work, 12L)
          assert_eq(budget.peak, 15L)
          release_logical_root(budget, value.root.unwrap()).unwrap()
          terminal = true
          break
        }
        Err(issue) => {
          assert_eq(
            issue.kind,
            LogicalValue(
              if work == 11L {
                ValueMeasure(LogicalWorkLimit)
              } else if live == 14L {
                LiveValueLimit
              } else {
                ValueMeasure(WireMeasureFailure)
              },
            ),
          )
          terminal = true
          break
        }
      }
    }
    assert_true(terminal)
    assert_eq(budget.live, 0L)
    assert_eq(frame.workspace.live, 0)
  }
}

///|
test "object measurement yields before publication and cancellation releases its owner" {
  let expression = lowered(
    (
      #|{"object":{"a":{"literal":7},"b":{"literal":2}}}
    ),
  )
  let budget = test_logical_budget(1000L, 1000L)
  let frame = expression_frame(
    expression,
    Map([]),
    [],
    { remaining: 1000, max_frames: 10, },
    row_workspace(10),
    Some(expression_roots(budget, 10)),
  ).unwrap()
  let mut reached = false
  for _ in 0..<50 {
    assert_true(advance_expression_frame(frame).unwrap() is None)
    if frame.state is MeasureObject(_, _, _) {
      reached = true
      break
    }
  }
  assert_true(reached)
  assert_eq(budget.live, 13L)
  close_expression_frame(frame)
  assert_eq(budget.live, 0L)
  assert_eq(frame.workspace.live, 0)
  assert_true(advance_expression_frame(frame) is Err(_))
}
