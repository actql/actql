///|
test "physical publication next coalesces rows while retaining the original tail and CID" {
  let output = retry_export()
  assert_eq(output.next(batch=true).unwrap(), Some("[{\"id\":1},{\"id\":2}"))
  assert_eq(output.next(batch=true).unwrap(), None)
  assert_eq(output.finish().unwrap(), "]")
  assert_eq(
    output.content_cid().unwrap(),
    "sha256:7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770",
  )
  output.cancel()
}

///|
test "publication row consumers retain one row per call without physical batch selection" {
  let output = retry_export()
  assert_eq(output.next().unwrap(), Some("[{\"id\":1}"))
  assert_eq(output.next().unwrap(), Some(",{\"id\":2}"))
  assert_eq(output.next().unwrap(), None)
  assert_eq(output.finish().unwrap(), "]")
  assert_eq(
    output.content_cid().unwrap(),
    "sha256:7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770",
  )
  output.cancel()
}

///|
test "physical publication advance charges the original transitions before coalesced output" {
  let output = retry_export()
  let text = StringBuilder()
  let mut batches = 0
  let mut complete = false
  for _ in 0..<1000 {
    let (next, used, issue) = output.advance(1, batch=true)
    assert_true(issue is None)
    let next = next.unwrap()
    assert_eq(used, next.steps)
    assert_true(used <= 1)
    if next.batch is Some(part) {
      batches += 1
      text.write_string(part)
    }
    if next.complete {
      complete = true
      break
    }
  }
  assert_true(complete)
  assert_eq(batches, 1)
  text.write_string(output.finish().unwrap())
  assert_eq(text.to_string(), "[{\"id\":1},{\"id\":2}]")
  assert_eq(
    output.content_cid().unwrap(),
    "sha256:7dcee6a0c50483d0fb68d53b37822d55409a37928ffa228c6b9a482e3373e770",
  )
  output.cancel()
}
