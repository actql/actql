///|
test "Farm fingerprint matches upstream vectors at every block and short-range boundary" {
  // Independent google/farmhash Fingerprint64 0d859a8, built with the default
  // public util::Fingerprint64. Values are interpreted as signed 64-bit words.
  for
    (count, expected) in [
      (0, -7286425919675154353L),
      (1, -5528939962900187677L),
      (3, 2640714258260161385L),
      (4, 1897425971756105985L),
      (7, -4471619969553224102L),
      (8, -6757268377441319535L),
      (16, 2515449721340945090L),
      (17, -2109127690140680281L),
      (32, -2297946276753761476L),
      (33, 1751653597827402391L),
      (63, -3126555383678660945L),
      (64, -7749126383854300567L),
      (65, 7372463055786621747L),
      (127, 8249335288357397231L),
      (128, 1300677609871410583L),
      (129, 5569039068079253021L),
      (190, -6039093506449337907L),
      (192, -8774657095792711943L),
      (193, -4607613093606640252L),
      (257, 6951152463520653364L),
    ] {
    let text = StringBuilder(size_hint=count)
    for i in 0..<count {
      text.write_char("abcdef0123456789!"[i % 17].to_int().unsafe_to_char())
    }
    let source = "{\"farm_fingerprint\":{\"literal\":\"" +
      text.to_string() +
      "\"}}"
    assert_true(
      run_expr(source) is Ok(Captured(@admitted.Signed64(actual))) &&
      actual == expected,
      msg=count.to_string(),
    )
  }
}

///|
test "Farm fingerprint uses the original Unicode scalars, including a block split inside a scalar" {
  for
    (text, expected) in [
      ("é", 693143013273849025L),
      ("e\u{0301}", 3027947468494914332L),
      ("🙂a\\u0000é", -6436683000666930182L),
      (
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa🙂b", -6551866991269175390L,
      ),
      ("1footrue", -1541654101129638711L),
    ] {
    let source = "{\"farm_fingerprint\":{\"literal\":\"" + text + "\"}}"
    assert_true(
      run_expr(source) is Ok(Captured(@admitted.Signed64(actual))) &&
      actual == expected,
      msg=source,
    )
  }
  assert_true(run_expr("{\"farm_fingerprint\":{\"literal\":null}}") is Ok(Null))
}

///|
test "Farm fingerprint admits a fixed continuation and retires on cancellation" {
  let expression = lowered(
    "{\"farm_fingerprint\":{\"literal\":\"🙂continued\"}}",
  )
  for slots in [29, 30] {
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
      if frame.state is Fingerprint(state) && state.bytes == 4L {
        moved = true
        assert_true(budget.live > 1L)
        break
      }
      if !(result is Ok(None)) {
        break
      }
    }
    if slots == 29 {
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
