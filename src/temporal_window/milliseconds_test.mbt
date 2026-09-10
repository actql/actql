///|
test "shared millisecond admission retains window scalar domains and exact budgets" {
  let cap : @temporal_window.Limits = {
    max_work: 1000,
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 1000,
  }
  for
    (text, expected) in [
      ("1", 1L),
      ("\"01S\"", 1000L),
      ("9007199254740991", 9007199254740991L),
    ] {
    let checked = @temporal_window.read_milliseconds(
      cursor(text),
      PositiveMilliseconds,
      None,
      cap,
    ).unwrap()
    assert_true(@temporal_window.milliseconds_value(checked) is Literal(_))
    match @temporal_window.milliseconds_value(checked) {
      Literal(n) => assert_eq(n, expected)
      _ => abort("literal")
    }
    let u = @temporal_window.milliseconds_usage(checked)
    assert_true(
      @temporal_window.read_milliseconds(
        cursor(text),
        PositiveMilliseconds,
        None,
        {
          ..cap,
          max_work: u.work,
          max_nodes: u.nodes,
          max_text_bytes: u.text_bytes,
        },
      )
      is Ok(_),
    )
    assert_true(
      @temporal_window.read_milliseconds(
        cursor(text),
        PositiveMilliseconds,
        None,
        { ..cap, max_work: u.work - 1, },
      )
      is Err(_),
    )
  }
  for text in ["0", "-1", "1.5", "\"1.5s\"", "9007199254740992"] {
    assert_true(
      @temporal_window.read_milliseconds(
        cursor(text),
        PositiveMilliseconds,
        None,
        cap,
      )
      is Err(_),
    )
  }
  assert_true(
    @temporal_window.read_milliseconds(
      cursor("-1"),
      SignedMilliseconds,
      None,
      cap,
    )
    is Ok(_),
  )
}
