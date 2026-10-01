///|
test "complete machine source retains annotations bindings and authored arrays" {
  // Expected source is written independently, in canonical object-key order.
  // Array order, empty Effect bodies, NULL and business meta stay significant.
  let expected =
    #|{"bindings":{"input":{"kind":"source"}},"id":"p","meta":{"note":"retained"},"results":{"out":{"from":{"result":"r","stage":"s"}}},"stages":[{"effects":{"write":{"create":{}}},"id":"s","inputs":{},"results":{"r":{"from":"rows"}},"steps":[{"as":"rows","meta":{"note":"authored"},"values":{"rows":[{"id":2,"meta":null},{"id":1,"meta":"business"}],"schema":{"id":{"nullable":false,"type":"number"},"meta":{"nullable":true,"type":"string"}}}}]}],"version":"actql/0.1"}
  let admitted = parsed(expected, format=Json)
  let writer = @encode.writer(expected.length(), 1000, 30)
  emit_program_source(admitted, writer)
  let actual = @encode.finish(writer)
  assert_eq(actual, expected)
  assert_eq(effect_names(stages(parsed(actual, format=Json))[0]), ["write"])
  assert_true(stripped(expected) != expected)
  // Failed bounded emission cannot expose a partially encoded Program.
  for
    (bytes, nodes, depth) in [
      (expected.length() - 1, 1000, 30),
      (expected.length(), 1, 30),
      (expected.length(), 1000, 1),
    ] {
    let limited = @encode.writer(bytes, nodes, depth)
    assert_true(
      try {
        emit_program_source(admitted, limited)
        false
      } catch {
        @encode.OutputLimit => true
        _ => false
      },
    )
    assert_true(
      try {
        let _ = @encode.finish(limited)
        false
      } catch {
        @encode.ClosedWriter => true
        _ => false
      },
    )
  }
}
