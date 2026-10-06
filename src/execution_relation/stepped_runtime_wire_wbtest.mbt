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
test "stepped long object key preserves exact custody and cleanup on refusal" {
  let name = String::make(256, 'k')
  guard logical_literal("{\"" + name + "\":null}")
    is Captured(@admitted.JsonData(payload)) else {
    fail("expected independent checked JSON object")
  }
  // Keep this bare-payload custody boundary separate from the typed envelope.
  let value = Captured(payload)
  for (slots, succeeds) in [(6, true), (5, false)] {
    let workspace = row_workspace(slots)
    let writer = @encode.writer(265, 2, 1)
    let cursor = start_stepped_runtime_wire(value, writer, workspace).unwrap()
    let mut done = false
    let mut failed = false
    for _ in 0..<100 {
      if done || failed {
        break
      }
      match advance_stepped_runtime_wire(cursor) {
        Ok(value) => done = value
        Err(Workspace) => {
          assert_false(cursor.closed)
          assert_true(workspace.live > 0)
          failed = true
        }
        Err(_) => fail("unexpected long key failure")
      }
    }
    assert_eq((done, failed), (succeeds, !succeeds))
    close_stepped_runtime_wire(cursor)
    close_stepped_runtime_wire(cursor)
    assert_eq(workspace.live, 0)
    if succeeds {
      assert_eq(@encode.finish(writer), "{\"" + name + "\":null}")
    } else {
      @encode.cancel_writer(writer)
    }
  }
  let workspace = row_workspace(6)
  let writer = @encode.writer(265, 2, 1)
  let cursor = start_stepped_runtime_wire(value, writer, workspace).unwrap()
  for _ in 0..<5 {
    assert_false(advance_stepped_runtime_wire(cursor).unwrap())
  }
  assert_true(@encode.writer_progress(writer).0 > 1)
  close_stepped_runtime_wire(cursor)
  assert_eq(workspace.live, 0)
  assert_true(
    try {
      @encode.finish(writer) |> ignore
      false
    } catch {
      @encode.ClosedWriter => true
      _ => false
    },
  )
}

///|
test "typed JSON long key retains exact envelope and bounded key custody" {
  let name = String::make(256, 'k')
  let value = logical_literal("{\"" + name + "\":null}")
  guard value is Captured(@admitted.JsonData(_)) else {
    fail("expected independent checked JSON object")
  }
  let expected = "{\"$json\":{\"" + name + "\":null}}"
  // The payload is 265 bytes, two nodes and depth one. Its JSON envelope
  // adds ten bytes, one node and one level. JsonEnd remains live alongside
  // ObjectValueNext/KeyNext: three handles, three frames and one spare slot.
  for (slots, succeeds) in [(7, true), (6, false)] {
    let workspace = row_workspace(slots)
    let writer = @encode.writer(275, 3, 2)
    let cursor = start_stepped_runtime_wire(value, writer, workspace).unwrap()
    let mut done = false
    let mut failed = false
    for _ in 0..<100 {
      if done || failed {
        break
      }
      let before = @encode.writer_progress(writer).0
      match advance_stepped_runtime_wire(cursor) {
        Ok(value) => {
          assert_true(@encode.writer_progress(writer).0 - before <= 68)
          done = value
        }
        Err(Workspace) => {
          failed = true
          assert_false(cursor.closed)
          assert_eq((cursor.reserved, workspace.live), (6, 6))
          assert_eq(@encode.writer_progress(writer).0, before)
          assert_eq(before, 10)
        }
        Err(_) => fail("unexpected typed JSON key failure")
      }
    }
    assert_eq((done, failed), (succeeds, !succeeds))
    assert_eq(workspace.peak, slots)
    close_stepped_runtime_wire(cursor)
    close_stepped_runtime_wire(cursor)
    assert_eq((cursor.reserved, workspace.live), (0, 0))
    if succeeds {
      assert_eq(@encode.finish_text_usage(writer), (expected, 275, 3, 2))
    } else {
      @encode.cancel_writer(writer)
    }
  }
  let workspace = row_workspace(7)
  let writer = @encode.writer(275, 3, 2)
  let cursor = start_stepped_runtime_wire(value, writer, workspace).unwrap()
  // Envelope, object, key selection, ordering, quote, then one key chunk.
  for _ in 0..<6 {
    assert_false(advance_stepped_runtime_wire(cursor).unwrap())
  }
  assert_eq(@encode.writer_progress(writer).0, 75)
  close_stepped_runtime_wire(cursor)
  close_stepped_runtime_wire(cursor)
  assert_eq((cursor.reserved, workspace.live), (0, 0))
  assert_true(
    try {
      @encode.finish(writer) |> ignore
      false
    } catch {
      @encode.ClosedWriter => true
      _ => false
    },
  )
}

///|
test "stepped runtime wire retains pending traversal on workspace failure" {
  let expr = lowered("{\"literal\":[1,2]}")
  guard @lower.expression_body(expr) is @lower.Literal(checked) &&
    checked.value is @admitted.JsonData(payload) else {
    fail("expected independent checked JSON array")
  }
  // Isolate the payload traversal here; the adjacent typed JSON case checks
  // the complete envelope and its additional retained continuation.
  // Three cursor handles and up to two continuations, with one conservative
  // pre-advance spare slot: six exact slots, five rejects before the next
  // emitter step. A rejected cursor stays owned until explicit cleanup.
  for (slots, succeeds) in [(6, true), (5, false)] {
    let workspace = row_workspace(slots)
    let writer = @encode.writer(5, 3, 1)
    let cursor = start_stepped_runtime_wire(
      Captured(payload),
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
test "typed JSON stepped wire reserves its envelope continuation exactly" {
  let expr = lowered(
    "{\"typed_literal\":{\"type\":\"json\",\"value\":\"[1,2]\"}}",
  )
  guard @lower.expression_body(expr) is @lower.Literal(checked) &&
    checked.value is @admitted.JsonData(_) else {
    fail("expected an independently authored typed JSON array")
  }
  // {"$json":[1,2]}: five payload bytes plus ten envelope bytes; the
  // envelope object, array and two numbers are four nodes at depth two.
  // Three handles + JsonEnd/ArrayNext/Read + one pre-advance spare = seven
  // slots. Six must stop before emitting the first number, retaining custody.
  for (slots, succeeds) in [(7, true), (6, false)] {
    let workspace = row_workspace(slots)
    let writer = @encode.writer(15, 4, 2)
    let cursor = start_stepped_runtime_wire(
      Captured(checked.value),
      writer,
      workspace,
    ).unwrap()
    let mut done = false
    let mut failed = false
    for _ in 0..<20 {
      if !done && !failed {
        let before = @encode.writer_progress(writer)
        match advance_stepped_runtime_wire(cursor) {
          Ok(value) => done = value
          Err(Workspace) => {
            failed = true
            assert_eq(workspace.live, 6)
            assert_eq(cursor.reserved, 6)
            assert_false(cursor.closed)
            assert_eq(@encode.writer_progress(writer), before)
            // The JSON envelope and array are open; no scalar was emitted.
            assert_eq(before.0, 10)
          }
          Err(_) => fail("unexpected typed JSON wire failure")
        }
      }
    }
    assert_eq(done, succeeds)
    assert_eq(failed, !succeeds)
    assert_eq(workspace.peak, slots)
    close_stepped_runtime_wire(cursor)
    close_stepped_runtime_wire(cursor)
    assert_true(cursor.closed)
    assert_eq((cursor.reserved, workspace.live), (0, 0))
    if succeeds {
      assert_eq(
        @encode.finish_text_usage(writer),
        ("{\"$json\":[1,2]}", 15, 4, 2),
      )
    } else {
      @encode.cancel_writer(writer)
    }
  }
}

///|
test "stepped Reference wire accounts nested canonical cursor custody" {
  let live = Ref(true)
  let checked = issued_artifact_value(
    select_checked_contract("{\"type\":\"artifact_ref\",\"nullable\":false}"),
    live,
  )
  guard checked.value is @admitted.Reference(reference) else {
    abort("expected issued Reference")
  }
  let expected = @admitted.reference_wire(reference)
  // Wrapper/admitted/leaf handles (3), Reference continuation (1), root and
  // metadata continuations plus a child (3), and one speculative frame (1).
  for limit in [8, 7] {
    let workspace = row_workspace(limit)
    let writer = @encode.writer(4096, 64, 4)
    let cursor = start_stepped_runtime_wire(
      Captured(checked.value),
      writer,
      workspace,
    ).unwrap()
    let mut complete = false
    let mut refused = false
    for _ in 0..<200 {
      let before = @encode.writer_progress(writer).0
      match advance_stepped_runtime_wire(cursor) {
        Ok(done) => {
          assert_true(@encode.writer_progress(writer).0 - before <= 68)
          complete = done
          if done {
            break
          }
        }
        Err(Workspace) => {
          refused = true
          break
        }
        _ => abort("unexpected Reference emission failure")
      }
    }
    assert_eq(complete, limit == 8)
    assert_eq(refused, limit == 7)
    if complete {
      assert_eq(@encode.finish(writer), expected)
      assert_eq(workspace.peak, 8)
    }
    close_stepped_runtime_wire(cursor)
    assert_eq(workspace.live, 0)
    assert_true(live.val && @admitted.reference_available(reference))
  }
  let workspace = row_workspace(8)
  let writer = @encode.writer(4096, 64, 4)
  let cursor = start_stepped_runtime_wire(
    Captured(checked.value),
    writer,
    workspace,
  ).unwrap()
  for _ in 0..<15 {
    assert_false(advance_stepped_runtime_wire(cursor).unwrap())
  }
  close_stepped_runtime_wire(cursor)
  assert_eq(workspace.live, 0)
  assert_true(@admitted.reference_available(reference))
  close_stepped_runtime_wire(cursor)
  assert_eq(workspace.live, 0)
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
