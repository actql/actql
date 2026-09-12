///|
test "take encodes both count and offset and retains order owner" {
  let sequence = @lowering_relation.prepare_sequence(
    expression_pipeline(",{\"take\":{\"count\":9007199254740991,\"offset\":1}}"),
    sequence_limits(),
  ).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(@lowering_relation.RowStep(kernel)) else {
    fail("take kernel")
  }
  let writer = @encode.writer(10000, 1000, 100)
  @lowering_relation.emit_kernel_node(kernel, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"id\":\"limit_1\",\"in\":[\"values_0\"],\"op\":\"REL.limit\",\"params\":{\"count\":9007199254740991,\"offset\":1}}",
  )
  assert_eq(
    @lowering_relation.kernel_take(kernel),
    Some((9007199254740991L, 1L)),
  )
}

///|
test "take binds retained parameter values and rejects invalid ranges before rows" {
  let d = declarations()
  let p = prepared_with(
    d,
    tail=",{\"take\":{\"count\":{\"$param\":\"amount\"},\"offset\":{\"$param\":\"amount\"}}}",
  )
  for
    (number, valid) in [
      ("7", true),
      ("0", false),
      ("-1", false),
      ("1.5", false),
      ("9007199254740992", false),
    ] {
    guard @parameter.bind(d, Some(cursor("{\"amount\":" + number + "}")), {
        max_nodes: 100,
        max_depth: 20,
        max_text_bytes: 1000,
      }).unwrap()
      is Ready(values) else {
      fail("bound fixture")
    }
    let owner = @lowering_relation.bind_parameters(
      p,
      Some(values),
      max_parameters=1,
      max_name_bytes=6,
    ).unwrap()
    let result = @lowering_relation.prepare_sequence(owner, sequence_limits())
    if valid {
      guard @lowering_relation.sequence_step(result.unwrap(), 1)
        is Some(@lowering_relation.RowStep(kernel)) else {
        fail("take kernel")
      }
      assert_eq(@lowering_relation.kernel_take(kernel), Some((7L, 7L)))
    } else {
      assert_true(
        result
        is Err(
          @lowering_relation.KernelFailure(
            1,
            @lowering_relation.InvalidTakeCount
          )
        ),
      )
    }
  }
}
