///|
test "typed page local counters do not cross funding boundary within a frame window" {
  let contract = @contract.primitive(@contract.NumberType, nullable=false)
  let value = @admitted.checked_number_value(1.0, contract).unwrap()
  let rows = Array::make(4096, [value])
  let calls = Ref(0)
  let (nodes, text, frames) = count_row_input_values(rows, 16, _ => {
    calls.val += 1
    Ok(())
  }).unwrap()
  assert_eq(nodes, 8192L)
  assert_eq(text, 0L)
  assert_eq(frames, 16)
  assert_eq(calls.val, 0)
}

///|
test "typed page grows only exhausted buffer chunks and reuses the funded window" {
  let mut payload = @admitted.null_value()
  for _ in 0..<65 {
    payload = @admitted.array_value([payload, @admitted.null_value()])
  }
  let (value, _, _) = @admitted.recheck_json_payload_usage(payload, {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 0,
  }).unwrap()
  let calls = Ref(0)
  let (_, _, frames) = count_row_input_values([[value]], 16, _ => {
    calls.val += 1
    Ok(())
  }).unwrap()
  // At most one geometric expansion per frame-buffer size, not per node.
  assert_true(calls.val > 0 && calls.val <= 4)
  assert_true(frames >= 66 && frames <= 132)
  let previous = calls.val
  count_row_input_values([[value]], frames, _ => {
    calls.val += 1
    Ok(())
  }).unwrap()
  |> ignore
  assert_eq(calls.val, previous)
  assert_true(
    count_row_input_values([[value]], 16, _ => Err(Physical(ExecutionLimit)))
    is Err(Physical(ExecutionLimit)),
  )
}
