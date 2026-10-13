///|
test "SourceView scores validate both original pages before filter and alias projection" {
  let (run, ledger) = source_relation_keys_run("source-score-hidden-invalid", drop_key=true, scores=true)
  // id=0 is filtered out, but its score assertion still applies to raw capture.
  for page in ["[{\"id\":2,\"payload\":0.5}]", "[{\"id\":0,\"payload\":2}]"] {
    assert_eq(@row_host.accept_row_run_page(run, @utf8.encode(page)).unwrap(), 1)
  }
  @row_host.finish_row_run(run).unwrap()
  @row_host.begin_row_capture(run).unwrap()
  let mut refused = false
  for _ in 0..<10000 {
    match @row_host.advance_row_capture(run, 1) {
      Err(Residual(Execution(InputScore(0, InvalidScore(1))))) => { refused = true; break }
      Ok((false, _)) => ()
      _ => fail("original second-page range violation must not be hidden")
    }
  }
  assert_true(refused)
  assert_true(@row_host.capture_row_run(run) is Err(_))
  @row_host.close_row_run(run)
  let reserved = @resources.ledger_usage(ledger).reserved_execution_bytes
  assert_true(reserved > 0L)
  let mut closed = false
  for _ in 0..<10000 {
    if @row_host.advance_row_capture_cleanup(run, 1).unwrap() { closed = true; break }
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, reserved)
  }
  assert_true(closed)
  row_page_assert_closed(run, ledger)
}

///|
test "SourceView lawful score capture retains one acquisition and cleans the original owner" {
  let (run, ledger) = source_relation_keys_run("source-score-valid", drop_key=true, scores=true)
  for page in ["[{\"id\":2,\"payload\":0.5}]", "[{\"id\":0,\"payload\":0.5}]"] {
    assert_eq(@row_host.accept_row_run_page(run, @utf8.encode(page)).unwrap(), 1)
  }
  @row_host.finish_row_run(run).unwrap()
  @row_host.begin_row_capture(run).unwrap()
  let mut completed = false
  for _ in 0..<10000 {
    let (done, _) = @row_host.advance_row_capture(run, 1).unwrap()
    if done { completed = true; break }
  }
  assert_true(completed)
  let capture = @row_host.capture_row_run(run).unwrap()
  // Existing $minimum excludes id=0; the alias publishes only payload as value.
  assert_eq(@query.captured_source_statistics(@row_host.row_capture_source(capture).unwrap()).unwrap().rows, 1)
  let usage = @resources.ledger_usage(ledger)
  assert_true(@row_host.row_capture_source(capture) is Ok(_))
  assert_eq(@resources.ledger_usage(ledger), usage)
  @row_host.close_row_run(run)
  let mut closed = false
  for _ in 0..<10000 {
    if @row_host.advance_row_capture_cleanup(run, 1).unwrap() { closed = true; break }
  }
  assert_true(closed)
  row_page_assert_closed(run, ledger)
}
