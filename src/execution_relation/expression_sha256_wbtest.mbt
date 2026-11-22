///|
test "SHA256 computes exact UTF-8 and binary digests" {
  // Independent Python hashlib SHA-256 and RFC 4648 base64 vectors.
  for
    (input, expected) in [
      ("", "47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="),
      ("a", "ypeBEsobvcr6wjGzmiPcTaeG7/gUfE5yuYB3ha/uSLs="),
      ("é", "SplVfkAzw1Od4utlRyAXytX5VX96BiWgnxw/biumnEw="),
      ("e\u{0301}", "vxJ2ew8qVrIZAHW66BafZW486NY1fUr/GEvGx+pI+fY="),
      ("a".repeat(63) + "🙂b", "2kfJ1itzwtWR8cFGJx+wpn6uYnmoVkXig2Hx95ISfMg="),
    ] {
    let source = "{\"sha256\":{\"literal\":" +
      Json::string(input).stringify() +
      "}}"
    guard run_expr(source) is Ok(Captured(@admitted.Binary(bytes))) else {
      fail("expected typed BYTES")
    }
    assert_eq(@admitted.bytes_count(bytes), 32)
    assert_eq(@admitted.bytes_wire_text(bytes), expected, msg=input)
  }
  let nested = "{\"sha256\":{\"sha256\":{\"literal\":\"a\"}}}"
  guard run_expr(nested) is Ok(Captured(@admitted.Binary(bytes))) else {
    fail("expected typed BYTES")
  }
  assert_eq(
    @admitted.bytes_wire_text(bytes),
    "v106/7c+/S7Gw2rTES3ZM+/tY8Thy//PqI4nWcFE8tg=",
  )
  assert_true(run_expr("{\"sha256\":{\"literal\":null}}") is Ok(Null))
}

///|
test "SHA256 uses fixed scratch and retires the original input root on cancellation" {
  let expression = lowered("{\"sha256\":{\"literal\":\"🙂continued\"}}")
  for slots in [SHA256_WORKSPACE_SLOTS - 1, SHA256_WORKSPACE_SLOTS] {
    let budget = test_logical_budget(10000L, 10000L)
    let caller = retain_logical_value(budget, Number(8.0)).unwrap()
    let workspace = row_workspace(slots)
    let frame = expression_frame(
      expression,
      {},
      [],
      { remaining: 1000, max_frames: 100, },
      workspace,
      Some(expression_roots(budget, 120)),
    ).unwrap()
    let mut result = Ok(None)
    let mut moved = false
    for _ in 0..<64 {
      result = advance_expression_frame(frame)
      if frame.state is Digest(state) && state.position == 2 {
        moved = true
        assert_true(budget.live > 1L)
        break
      }
      if !(result is Ok(None)) {
        break
      }
    }
    if slots == SHA256_WORKSPACE_SLOTS - 1 {
      assert_true(result is Err({ kind: WorkspaceLimit, .. }))
      assert_false(moved)
    } else {
      assert_true(result is Ok(None))
      assert_true(moved)
    }
    let spent = budget.work
    close_expression_frame(frame)
    assert_eq((budget.live, workspace.live, budget.work), (1L, 0, spent))
    assert_false(caller.released)
    release_logical_root(budget, caller).unwrap()
  }
}
