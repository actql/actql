///|
test "original schema receipt is unavailable before EOF and canonical identity is fixed" {
  let output = retry_export()
  assert_true(output.result_schema_cid() is Err(InvalidState))
  assert_true(output.result_schema_wire() is Err(InvalidState))
  while output.next().unwrap() is Some(_) {

  }
  assert_true(output.result_schema_wire() is Err(InvalidState))
  output.finish().unwrap() |> ignore
  // Independently fixed canonical literal and its SHA256; no product oracle.
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  assert_eq(
    output.result_schema_cid().unwrap(),
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  output.cancel()
}

///|
test "borrowed snapshot cancellation retains original schema receipt" {
  let output = retry_export()
  while output.next().unwrap() is Some(_) {

  }
  output.finish().unwrap() |> ignore
  // Snapshot requires the original issued evidence; reuse the established
  // binding fixture's same evidence inputs, never recreate a Result.
  let (run, invocation, retention) = storage_binding_context()
  output
  .issue_result_evidence(
    "sha256:" + "1".repeat(64),
    ["sha256:" + "2".repeat(64)],
    @publication.publication_contract_identity(run),
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
    100000,
    10000,
    100,
  )
  .unwrap()
  output.issue_artifact(invocation, retention, 100000, 10000, 100).unwrap()
  |> ignore
  let child = output.start_captured_snapshot(100000, 10000, 100).unwrap()
  assert_eq(child.advance(1).unwrap(), (false, 1))
  child.cancel()
  assert_eq(
    output.result_schema_cid().unwrap(),
    "sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513",
  )
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  output.cancel()
}

///|
test "parent cleanup cannot lend a stale schema receipt" {
  let output = retry_export()
  while output.next().unwrap() is Some(_) {

  }
  output.finish().unwrap() |> ignore
  output.cancel()
  assert_true(output.result_schema_cid() is Err(InvalidState))
  assert_true(output.result_schema_wire() is Err(InvalidState))
}
