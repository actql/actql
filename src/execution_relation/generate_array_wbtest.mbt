///|
fn generated_array_source(bounds : Array[String]) -> String {
  "{\"generate_array\":[" +
  bounds
  .map(bound => {
    if bound == "NULL" {
      "{\"literal\":null}"
    } else {
      "{\"typed_literal\":{\"type\":\"int64\",\"value\":\"" + bound + "\"}}"
    }
  })
  .join(",") +
  "]}"
}

///|
test "GENERATE_ARRAY admits complete output before its builder allocation" {
  // The quoted operands occupy 3+4 bytes and coexist with the 42-byte Array.
  // Entry, operand production/consumption and result production cost 3+4+11
  // work. Array construction peaks at 2 view, 1 continuation, 4 argument, 2
  // accumulator and 10 builder slots, above the operand measurement peak.
  let source = generated_array_source(["1", "10"])
  for
    (work, bytes, live, nodes, slots, refusal) in [
      (18, 42, 49, 11, 19, None),
      (17, 42, 49, 11, 19, Some(LogicalValue(WorkLimit))),
      (18, 41, 49, 11, 19, Some(LogicalValue(ValueMeasure(WireMeasureFailure)))),
      (18, 42, 48, 11, 19, Some(LogicalValue(LiveValueLimit))),
      (18, 42, 49, 10, 19, Some(LogicalValue(ValueMeasure(HostMeasureLimit)))),
      (18, 42, 49, 11, 18, Some(WorkspaceLimit)),
    ] {
    let logical = logical_budget(
      {
        max_input_rows: 1L,
        max_value_bytes: bytes.to_int64(),
        max_live_value_bytes: live.to_int64(),
        max_work: work.to_int64(),
      },
      bytes,
      nodes,
      2,
    ).unwrap()
    let workspace = row_workspace(slots)
    let outcome = evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 1000, max_frames: 10, },
      workspace,
      logical_work=Some(logical),
    )
    match (outcome, refusal) {
      (Ok(value), None) => {
        assert_eq(
          object_result_wire(value),
          "[\"1\",\"2\",\"3\",\"4\",\"5\",\"6\",\"7\",\"8\",\"9\",\"10\"]",
        )
        assert_eq((logical.work, logical.peak, workspace.peak), (18L, 49L, 19))
      }
      (Err(issue), _) => assert_eq(Some(issue.kind), refusal)
      _ => fail("a one-short limit admitted the complete array")
    }
    assert_eq((logical.live, workspace.live), (0L, 0))
  }
}

///|
test "GENERATE_ARRAY builds exact rows without stepping beyond signed64 endpoints" {
  for
    (bounds, expected) in [
      (["1", "3"], "[\"1\",\"2\",\"3\"]"),
      (["10", "0", "-3"], "[\"10\",\"7\",\"4\",\"1\"]"),
      (["1", "3", "-1"], "[]"),
      (["1", "NULL"], "null"),
      (
        ["9223372036854775806", "9223372036854775807"],
        "[\"9223372036854775806\",\"9223372036854775807\"]",
      ),
      (
        ["9223372036854775807", "-9223372036854775808", "-9223372036854775808"],
        "[\"9223372036854775807\",\"-1\"]",
      ),
    ] {
    assert_eq(
      object_result_wire(run_expr(generated_array_source(bounds)).unwrap()),
      expected,
    )
  }
  assert_true(
    run_expr(generated_array_source(["2", "3", "0"]))
    is Err({ kind: Scalar(InvalidOperand), .. }),
  )
  assert_true(
    run_expr(
      generated_array_source(["-9223372036854775808", "9223372036854775807"]),
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
}
