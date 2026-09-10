///|
test "pool options keep authored grouping order and separate output alias" {
  let source = cursor(
    "{\"by\":[\"right.b\",\"left.a\"],\"vector\":\"embedding\",\"method\":\"mean\"}",
  )
  let c = @vector_typing.read_pool_options(source, limits()).unwrap()
  assert_eq(@vector_typing.pool_group_fields(c), [
    Qualified(Right, "b"),
    Qualified(Left, "a"),
  ])
  assert_eq(@vector_typing.pool_method(c), Mean)
  let fields = @vector_typing.pool_group_fields(c)
  fields[0] = Unqualified("mutated")
  assert_eq(@vector_typing.pool_group_fields(c)[0], Qualified(Right, "b"))
  let u = @vector_typing.pool_options_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@vector_typing.read_pool_options(source, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.read_pool_options(source, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  for reduction in ["mean", "sum", "max"] {
    let c = @vector_typing.read_pool_options(
      cursor(
        "{\"by\":[\"customer\"],\"method\":\"" +
        reduction +
        "\",\"output_id\":\"customer_id\"}",
      ),
      limits(),
    ).unwrap()
    assert_eq(@vector_typing.pool_output_id(c), Some("customer_id"))
    assert_true(@vector_typing.pool_vector(c) is None)
  }
}

///|
test "pool rejects empty duplicate groups aliases on tuples and undocumented options" {
  for
    text in [
      "{\"by\":[],\"method\":\"mean\"}", "{\"by\":[\"x\",\"x\"],\"method\":\"mean\"}",
      "{\"by\":[\"a\",\"b\"],\"method\":\"mean\",\"output_id\":\"id\"}", "{\"by\":[\"a\"],\"method\":\"avg\"}",
      "{\"by\":[\"a\"],\"method\":\"sum\",\"id\":\"member\"}", "{\"by\":[\"a\"],\"method\":\"sum\",\"output_id\":\"left.id\"}",
      "{\"by\":[\"a\"],\"method\":\"sum\",\"output_id\":\"__actql_id\"}",
    ] {
    assert_true(
      @vector_typing.read_pool_options(cursor(text), limits()) is Err(_),
    )
  }
  let issue = @vector_typing.read_pool_options(
    cursor("{\"by\":[\"x\",\"x\"],\"method\":\"mean\"}"),
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, DuplicatePoolField(Unqualified("x")))
  assert_eq(issue.path, [@source.Key("by"), @source.Index(1)])
}
