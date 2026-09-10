///|
test "row assertions preserve nullable schemas and retain physical obligations" {
  for body in ["{\"where\":\"flag\"}", "{\"unique_by\":[\"id\"]}"] {
    let value = checked(AssertRows, body)
    assert_true(@contract.type_equal(input_row(value), output_row(value), 1000))
    let pending = @relation_typing.pending_validations(value)
    assert_eq(pending.length(), 2)
    assert_eq(pending[0].kind, AtomicRowAssertion)
    assert_eq(pending[1].kind, AssertionConsumption)
    let exact = {
      ..limits(),
      max_work: @relation_typing.work_used(value),
      max_text_bytes: @relation_typing.text_bytes_used(value),
      max_nodes: @relation_typing.nodes_used(value),
      max_tokens: @relation_typing.tokens_used(value),
    }
    assert_true(
      check_row(AssertRows, cursor(body), input(), None, exact) is Ok(_),
    )
    for
      bound in [
        { ..exact, max_work: exact.max_work - 1, },
        { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
        { ..exact, max_nodes: exact.max_nodes - 1, },
      ] {
      assert_true(
        check_row(AssertRows, cursor(body), input(), None, bound) is Err(_),
      )
    }
  }
}

///|
test "row assertion syntax rejects invalid alternatives and invalid equality keys" {
  rejected(AssertRows, "{}", InvalidBody)
  rejected(AssertRows, "{\"where\":true,\"unique_by\":[\"id\"]}", InvalidBody)
  rejected(AssertRows, "{\"unique_by\":[]}", EmptyBody)
  rejected(AssertRows, "{\"unique_by\":[\"id\",\"id\"]}", DuplicateOutput("id"))
  rejected(AssertRows, "{\"unique_by\":[\"missing\"]}", UnknownField("missing"))
  rejected(AssertRows, "{\"where\":\"amount\"}", ExpectedBoolean)
  rejected(
    AssertRows,
    "{\"where\":\"flag\",\"on_failure\":\"skip\"}",
    InvalidBody,
  )
  let row = schema("{\"x\":{\"type\":\"json\",\"nullable\":false}}")
  assert_eq(
    check_row(
      AssertRows,
      cursor("{\"unique_by\":[\"x\"]}"),
      row,
      None,
      limits(),
    ).unwrap_err().kind,
    NotKeyComparable("x"),
  )
}

///|
test "unique assertions admit nullable reference domains without narrowing or proof" {
  let row = schema(
    "{\"resource\":{\"type\":\"resource_ref\",\"resource_kind\":\"Customer\",\"nullable\":true},\"artifact\":{\"type\":\"artifact_ref\",\"nullable\":true},\"n\":{\"type\":\"number\",\"nullable\":true}}",
  )
  let value = check_row(
    AssertRows,
    cursor("{\"unique_by\":[\"resource\",\"artifact\",\"n\"]}"),
    row,
    None,
    limits(),
  ).unwrap()
  assert_true(@contract.type_equal(output_row(value), row, 1000))
  for name in ["resource", "artifact", "n"] {
    assert_true(field(output_row(value), name).nullable)
  }
  assert_eq(@relation_typing.pending_validations(value).map(p => p.kind), [
    AtomicRowAssertion,
    AssertionConsumption,
  ])
}

///|
test "assertion predicate diagnostics preserve nested reference origins" {
  let issue = check_row(
    AssertRows,
    cursor("{\"where\":{\"eq\":[{\"field\":\"id\"},{\"field\":\"missing\"}]}}"),
    input(),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.kind, UnknownField("missing"))
  assert_eq(issue.path, [@source.Key("where"), Key("eq"), Index(1)])
}

///|
test "assertion key accessors detach arrays and preserve authored order" {
  let value = checked(AssertRows, "{\"unique_by\":[\"id\",\"amount\"]}")
  match @relation_typing.row_operation(value).unwrap() {
    AssertUnique(keys) => {
      assert_eq(keys[0].field, @schema.Unqualified("id"))
      keys[0] = keys[1]
    }
    _ => fail("expected key assertion")
  }
  match @relation_typing.row_operation(value).unwrap() {
    AssertUnique(keys) => assert_eq(keys[0].field, @schema.Unqualified("id"))
    _ => fail("expected key assertion")
  }
}
