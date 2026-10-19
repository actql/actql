///|
test "take binds original int64 parameters directly and emits unchanged numeric count bodies" {
  let d = @parameter.read_declarations(
    Some(
      cursor(
        "{\"amount\":{\"type\":\"number\"},\"n\":{\"type\":\"int64\"},\"off\":{\"type\":\"int64\"}}",
      ),
    ),
    { max_parameters: 10, max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
  ).unwrap()
  let p = prepared_with(
    d,
    tail=",{\"take\":{\"count\":{\"$param\":\"n\"},\"offset\":{\"$param\":\"off\"}}}",
  )
  for
    (n, valid) in [
      ("1", true),
      ("9007199254740991", true),
      ("0", false),
      ("-1", false),
      ("9007199254740992", false),
      ("9223372036854775807", false),
    ] {
    guard @parameter.bind(
        d,
        Some(cursor("{\"amount\":7,\"n\":\"" + n + "\",\"off\":\"0\"}")),
        { max_nodes: 100, max_depth: 20, max_text_bytes: 1000, },
      ).unwrap()
      is Ready(values) else {
      fail("bound fixture")
    }
    let owner = @lowering_relation.bind_parameters(
      p,
      Some(values),
      max_parameters=3,
      max_name_bytes=100,
    ).unwrap()
    assert_true(
      @lowering_relation.parameter_value(owner, "n").unwrap().value
      is @value.Signed64(_),
    )
    let result = @lowering_relation.prepare_sequence(owner, sequence_limits())
    assert_eq(result is Ok(_), valid)
    if valid {
      guard @lowering_relation.sequence_step(result.unwrap(), 1)
        is Some(@lowering_relation.RowStep(kernel)) else {
        fail("take kernel")
      }
      let writer = @encode.writer(10000, 1000, 100)
      @lowering_relation.emit_kernel_node(kernel, writer)
      assert_eq(
        @encode.finish(writer),
        "{\"id\":\"limit_1\",\"in\":[\"values_0\"],\"op\":\"REL.limit\",\"params\":{\"count\":" +
        n +
        ",\"offset\":0}}",
      )
    }
  }
}
