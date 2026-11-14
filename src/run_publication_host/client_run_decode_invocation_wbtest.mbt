///|
test "Run decode handoff belongs to one exact successful invocation" {
  let calls = Ref(0)
  let invoke = client_run_decode_invocation(_ => {
    calls.val += 1
    Ok(())
  })
  let parse = RunJournalParse(1024)
  let canonical = RunJournalCanonical(1024, 2048L, 14, 1)
  let retained = RunJournalRetained(1024, 2048L, 14, 1)
  assert_eq(invoke(parse), Ok(()))
  assert_eq(invoke(canonical), Ok(()))
  assert_eq(invoke(retained), Ok(()))
  assert_eq(calls.val, 3)
  assert_eq(invoke(retained), Err(ClientJournalDecodingIssue::CustodyLost))
  assert_eq(invoke(parse), Err(ClientJournalDecodingIssue::CustodyLost))
  assert_eq(calls.val, 3)
}

///|
test "Run decode refuses missing mismatched and refused canonical handoffs" {
  let canonical = RunJournalCanonical(1024, 2048L, 14, 1)
  let retained = RunJournalRetained(1024, 2048L, 14, 1)
  for stage in [canonical, retained] {
    let calls = Ref(0)
    let invoke = client_run_decode_invocation(_ => {
      calls.val += 1
      Ok(())
    })
    assert_true(invoke(stage) is Err(_))
    assert_eq(calls.val, 0)
  }
  for
    changed in [
      RunJournalRetained(1023, 2048L, 14, 1),
      RunJournalRetained(1024, 2047L, 14, 1),
      RunJournalRetained(1024, 2048L, 13, 1),
      RunJournalRetained(1024, 2048L, 14, 2),
    ] {
    let calls = Ref(0)
    let invoke = client_run_decode_invocation(_ => {
      calls.val += 1
      Ok(())
    })
    invoke(RunJournalParse(1024)).unwrap()
    invoke(canonical).unwrap()
    assert_true(invoke(changed) is Err(_))
    assert_true(invoke(retained) is Err(_))
    assert_eq(calls.val, 2)
  }
  let calls = Ref(0)
  let refused = client_run_decode_invocation(stage => {
    calls.val += 1
    match stage {
      RunJournalCanonical(_, _, _, _) =>
        Err(ClientJournalDecodingIssue::CustodyLost)
      _ => Ok(())
    }
  })
  refused(RunJournalParse(1024)).unwrap()
  assert_true(refused(canonical) is Err(_))
  assert_true(refused(retained) is Err(_))
  assert_eq(calls.val, 2)
}

///|
test "Run decode callback cannot ignore reentrant rejection and revive its handoff" {
  let nested : Ref[
    ((ClientRunJournalConstruction) -> Result[Unit, ClientJournalDecodingIssue])?,
  ] = Ref(None)
  let invoke = client_run_decode_invocation(_ => {
    match nested.val {
      Some(callback) => {
        let _ = callback(RunJournalParse(1024))
        ()
      }
      None => ()
    }
    Ok(())
  })
  nested.val = Some(invoke)
  assert_true(invoke(RunJournalParse(1024)) is Err(_))
  assert_true(invoke(RunJournalCanonical(1024, 2048L, 14, 1)) is Err(_))
  assert_true(invoke(RunJournalRetained(1024, 2048L, 14, 1)) is Err(_))
}
