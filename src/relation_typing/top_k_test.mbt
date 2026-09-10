///|
test "top-k keeps typed input fields and requires explicit total-order obligations" {
  for op in [@relation_typing.TopK, TopKBy] {
    let body = if op is TopK {
      "{\"k\":2,\"by\":[{\"id\":\"asc\"},{\"id\":\"asc\"}]}"
    } else {
      "{\"partition_by\":[],\"k\":2,\"by\":[{\"id\":\"asc\"},{\"id\":\"asc\"}]}"
    }
    let v = checked(op, body)
    assert_true(@contract.type_equal(input(), output_row(v), 100))
    assert_eq(@relation_typing.binding_count(v), 0)
    match @relation_typing.row_operation(v).unwrap() {
      TopK(count~, order~) | TopKBy(count~, order~, ..) => {
        assert_eq(count, Literal(2L))
        assert_eq(order.length(), 2)
        order.clear()
      }
      _ => fail("expected top-k")
    }
    match @relation_typing.row_operation(v).unwrap() {
      TopK(order~, ..) | TopKBy(order~, ..) => assert_eq(order.length(), 2)
      _ => fail("expected top-k")
    }
    let pending = @relation_typing.pending_validations(v)
    assert_true(pending.any(p => p.kind is SortOrderCompletion))
    assert_true(pending.any(p => p.kind is TopKSelectionEnvelope))
    assert_eq(pending.any(p => p.kind is TopKPartitioning), op is TopKBy)
  }
}

///|
test "top-k partitions retain repeated reference keys without constructing order evidence" {
  let row = schema(
    "{\"id\":{\"type\":\"string\",\"nullable\":false},\"ref\":{\"type\":\"resource_ref\",\"resource_kind\":\"file\",\"nullable\":true}}",
  )
  let v = check_row(
    TopKBy,
    cursor(
      "{\"partition_by\":[\"ref\",\"ref\"],\"k\":1,\"by\":[{\"id\":\"asc\"}]}",
    ),
    row,
    None,
    limits(),
  ).unwrap()
  match @relation_typing.row_operation(v).unwrap() {
    TopKBy(partition~, ..) => {
      assert_eq(partition.length(), 2)
      partition.clear()
    }
    _ => fail("expected partitioned top-k")
  }
  assert_true(
    check_row(
      TopKBy,
      cursor("{\"partition_by\":[\"id\"],\"k\":1,\"by\":[{\"ref\":\"asc\"}]}"),
      row,
      None,
      limits(),
    )
    is Err({ kind: NotAuthorOrderable("ref"), .. }),
  )
}

///|
test "top-k closes its grammar and rejects invalid static counts and keys" {
  for
    (op, body) in [
      (@relation_typing.TopK, "{\"k\":1,\"by\":[]}"),
      (TopK, "{\"k\":1,\"by\":[{\"missing\":\"asc\"}]}"),
      (TopK, "{\"k\":1,\"by\":[{\"id\":\"asc\"}],\"partition_by\":[]}"),
      (TopKBy, "{\"k\":1,\"by\":[{\"id\":\"asc\"}]}"),
      (
        TopKBy,
        "{\"partition_by\":[\"missing\"],\"k\":1,\"by\":[{\"id\":\"asc\"}]}",
      ),
    ] {
    assert_true(check_row(op, cursor(body), input(), None, limits()) is Err(_))
  }
  for
    k in [
      "0", "-1", "1.5", "9007199254740992", "null", "\"1\"", "{\"add\":[1,2]}",
    ] {
    assert_true(
      check_row(
        TopK,
        cursor("{\"k\":" + k + ",\"by\":[{\"id\":\"asc\"}]}"),
        input(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
  ignore(checked(TopK, "{\"k\":9007199254740991,\"by\":[{\"id\":\"asc\"}]}"))
}

///|
test "top-k symbolic counts and partition traversal use the shared budget" {
  let params = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\",\"nullable\":true}}")),
    { max_parameters: 10, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let body = cursor(
    "{\"partition_by\":[\"id\",\"id\"],\"k\":{\"$param\":\"n\"},\"by\":[{\"amount\":\"desc\"}]}",
  )
  let v = check_row(TopKBy, body, input(), Some(params), limits()).unwrap()
  assert_true(
    @relation_typing.pending_validations(v).any(p => {
      p.kind is BoundInteger(name="n", minimum=1L)
    }),
  )
  let exact = {
    ..limits(),
    max_work: @relation_typing.work_used(v),
    max_nodes: @relation_typing.nodes_used(v),
    max_text_bytes: @relation_typing.text_bytes_used(v),
    max_tokens: 0,
  }
  assert_true(check_row(TopKBy, body, input(), Some(params), exact) is Ok(_))
  for
    l in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(check_row(TopKBy, body, input(), Some(params), l) is Err(_))
  }
}
