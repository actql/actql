///|
test "nearest options retain explicit roles and never supply source defaults" {
  let source = cursor(
    "{\"queries\":\"$queries\",\"candidate_id\":\"left.id\",\"candidate_vector\":\"embedding\",\"metric\":\"l2\",\"k\":9007199254740991}",
  )
  let c = @vector_typing.read_nearest_options(source, limits()).unwrap()
  assert_eq(@vector_typing.nearest_query_name(c), "$queries")
  assert_eq(@vector_typing.nearest_metric(c), L2)
  assert_eq(@vector_typing.nearest_k(c), 9007199254740991L)
  assert_eq(
    @vector_typing.nearest_candidate_roles(c).identity,
    Some(Qualified(Left, "id")),
  )
  assert_eq(
    @vector_typing.nearest_candidate_roles(c).vector,
    Some(Unqualified("embedding")),
  )
  assert_true(@vector_typing.nearest_query_roles(c).identity is None)
  assert_true(@vector_typing.nearest_query_roles(c).vector is None)
  let u = @vector_typing.nearest_options_usage(c)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_nodes: u.nodes,
    max_text_bytes: u.text_bytes,
  }
  assert_true(@vector_typing.read_nearest_options(source, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_nodes: u.nodes - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.read_nearest_options(source, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "nearest rejects extra corpus references approximate flags and malformed options" {
  for
    extra in [
      "\"corpus\":\"c\"", "\"exact\":true", "\"candidate_id\":null", "\"query_vector\":\"a.b.c\"",
    ] {
    assert_true(
      @vector_typing.read_nearest_options(
        cursor("{\"queries\":\"q\",\"k\":1,\"metric\":\"dot\"," + extra + "}"),
        limits(),
      )
      is Err(_),
    )
  }
  for k in ["0", "-1", "1.5", "9007199254740992", "{\"$param\":\"k\"}"] {
    assert_true(
      @vector_typing.read_nearest_options(
        cursor("{\"queries\":\"q\",\"metric\":\"dot\",\"k\":" + k + "}"),
        limits(),
      )
      is Err(_),
    )
  }
  for
    text in [
      "{}", "{\"queries\":\"q\",\"k\":1}", "{\"queries\":\"\",\"k\":1,\"metric\":\"dot\"}",
      "{\"queries\":\"q\",\"k\":1,\"metric\":\"L2\"}",
    ] {
    assert_true(
      @vector_typing.read_nearest_options(cursor(text), limits()) is Err(_),
    )
  }
}
