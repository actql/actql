///|
test "stepped runtime wire has independent Text workspace and byte boundaries" {
  let text = String::make(130, 'a') + "😀"
  // 130 ASCII + four emoji bytes + two quotes. The raw Text cursor owns
  // two handles and one continuation slot, irrespective of the byte size.
  for
    (bytes, slots, succeeds) in [
      (136, 3, true),
      (135, 3, false),
      (136, 2, false),
    ] {
    let writer = @encode.writer(bytes, 1, 0)
    let workspace = row_workspace(slots)
    match start_stepped_runtime_wire(Text(text), writer, workspace) {
      Err(Workspace) => assert_eq(slots, 2)
      Err(_) => fail("unexpected wire start failure")
      Ok(cursor) => {
        let mut done = false
        let mut failed = false
        for _ in 0..<10 {
          if !done && !failed {
            match advance_stepped_runtime_wire(cursor) {
              Ok(value) => done = value
              Err(Encoding(@encode.OutputLimit)) => failed = true
              Err(_) => fail("unexpected wire failure")
            }
          }
        }
        assert_eq(done, succeeds)
        assert_eq(failed, !succeeds)
        close_stepped_runtime_wire(cursor)
        assert_eq(workspace.live, 0)
        if succeeds {
          assert_eq(@encode.finish(writer), "\"" + text + "\"")
        }
      }
    }
  }
}

///|
test "stepped runtime wire retains pending traversal on workspace failure" {
  let expr = lowered("{\"literal\":[1,2]}")
  guard @lower.expression_body(expr) is @lower.Literal(checked) else {
    fail("expected independent checked array")
  }
  // Three cursor handles and up to two continuations, with one conservative
  // pre-advance spare slot: six exact slots, five rejects before the next
  // emitter step. A rejected cursor stays owned until explicit cleanup.
  for (slots, succeeds) in [(6, true), (5, false)] {
    let workspace = row_workspace(slots)
    let writer = @encode.writer(5, 3, 1)
    let cursor = start_stepped_runtime_wire(
      Captured(checked.value),
      writer,
      workspace,
    ).unwrap()
    let mut done = false
    let mut failed = false
    for _ in 0..<20 {
      if !done && !failed {
        match advance_stepped_runtime_wire(cursor) {
          Ok(value) => done = value
          Err(Workspace) => {
            failed = true
            assert_true(workspace.live > 0)
            assert_false(cursor.closed)
          }
          Err(_) => fail("unexpected nested wire failure")
        }
      }
    }
    assert_eq(done, succeeds)
    assert_eq(failed, !succeeds)
    close_stepped_runtime_wire(cursor)
    close_stepped_runtime_wire(cursor)
    assert_eq(workspace.live, 0)
    if succeeds {
      assert_eq(@encode.finish(writer), "[1,2]")
    } else {
      @encode.cancel_writer(writer)
    }
  }
}

///|
test "progressed Text and Reference wire cancellation return reservations" {
  let contract = select_checked_contract(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"mail/message\"}",
  )
  let source = issued_resource_value(
    contract,
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    Ref(true),
  )
  guard source.value is @admitted.Reference(source) else {
    fail("expected issued reference")
  }
  let wire = @admitted.reference_wire(source).replace(
    old="\"provider_namespace\":\"mail\"",
    new="\"provider_namespace\":\"" + String::make(1024, 'x') + "\"",
  )
  let reference = issued_reference_value(contract, wire, Ref(true))
  let text = String::make(4096, 'a')
  let checked_text = lowered("{\"literal\":\"" + text + "\"}")
  guard @lower.expression_body(checked_text) is @lower.Literal(checked_text) else {
    fail("expected checked Text")
  }
  for
    value in [
      Text(text),
      Captured(checked_text.value),
      Captured(reference.value),
    ] {
    let workspace = row_workspace(10)
    let writer = @encode.writer(8192, 64, 4)
    let cursor = start_stepped_runtime_wire(value, writer, workspace).unwrap()
    let mut advances = 0
    while @encode.writer_progress(writer).0 < 1024 {
      assert_false(advance_stepped_runtime_wire(cursor).unwrap())
      advances += 1
      assert_true(advances < 100)
    }
    assert_true(advances > 1 && workspace.live > 0)
    assert_false(cursor.closed)
    close_stepped_runtime_wire(cursor)
    close_stepped_runtime_wire(cursor)
    assert_true(cursor.closed)
    assert_eq(cursor.reserved, 0)
    assert_eq(workspace.live, 0)
    assert_true(
      advance_stepped_runtime_wire(cursor)
      is Err(Encoding(@encode.ClosedWriter)),
    )
    assert_true(
      try {
        @encode.finish(writer) |> ignore
        false
      } catch {
        @encode.ClosedWriter | @encode.InvalidStructure => true
        _ => false
      },
    )
  }
  guard reference.value is @admitted.Reference(reference) else {
    fail("expected borrowed reference")
  }
  assert_true(@admitted.reference_available(reference))
  assert_eq(@admitted.reference_wire(reference), wire)
}
