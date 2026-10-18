///|
fn composite_bridge_rows() -> @carrier.Carrier {
  @carrier.relation(
    @carrier.rows(
      [
        (
          @row.Qualified(Left, "tenant"),
          Some(@contract.primitive(StringType, nullable=false)),
        ),
        (
          @row.Qualified(Right, "serial"),
          Some(@contract.decimal_contract(19, 0, nullable=false).unwrap()),
        ),
        (
          @row.Qualified(Right, "embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=3,
      max_name_bytes=100,
    ).unwrap(),
  )
}

///|
test "composite vector bridge preserves ordered original identity roles and their exact types" {
  let rows = composite_bridge_rows()
  let checked = @vector_typing.check(
    ToVectors,
    cursor(
      "{\"id\":[\"right.serial\",\"left.tenant\"],\"vector\":\"right.embedding\"}",
    ),
    rows,
    None,
    limits(),
  ).unwrap()
  guard @vector_typing.output(checked) is @carrier.VectorValue(result) else {
    fail("The bridge must retain its checked Vectors carrier")
  }
  assert_eq(@carrier.vector_identity_count(result), 2)
  let serial = @carrier.vector_identity_at(result, 0).unwrap()
  let tenant = @carrier.vector_identity_at(result, 1).unwrap()
  assert_eq(serial.name, @row.Qualified(Right, "serial"))
  assert_eq(tenant.name, @row.Qualified(Left, "tenant"))
  assert_true(
    @contract.type_equal(
      serial.contract.unwrap(),
      @contract.decimal_contract(19, 0, nullable=false).unwrap(),
      10,
    ),
  )
  assert_true(
    @contract.type_equal(
      tenant.contract.unwrap(),
      @contract.primitive(StringType, nullable=false),
      10,
    ),
  )
  assert_eq(
    @carrier.vector_components(result).name,
    @row.Qualified(Right, "embedding"),
  )
  assert_eq(@carrier.field_count(@carrier.vector_records(result)), 3)
  assert_true(
    @vector_typing.pending_validations(checked).contains(
      ValidateUniqueIdentities,
    ),
  )
}

///|
test "composite vector bridge retains singleton scalar roles without inventing an identity field" {
  for id in ["\"left.tenant\"", "[\"left.tenant\"]"] {
    let checked = @vector_typing.check(
      ToVectors,
      cursor("{\"id\":" + id + ",\"vector\":\"right.embedding\"}"),
      composite_bridge_rows(),
      None,
      limits(),
    ).unwrap()
    guard @vector_typing.output(checked) is @carrier.VectorValue(result) else {
      fail("Vectors")
    }
    assert_eq(@carrier.vector_identity_count(result), 1)
    assert_eq(
      @carrier.vector_identity_at(result, 0).unwrap().name,
      @row.Qualified(Left, "tenant"),
    )
    assert_eq(@carrier.field_count(@carrier.vector_records(result)), 3)
  }
}

///|
test "composite vector bridge rejects empty malformed repeated and component identity roles" {
  for
    id in [
      "[]", "[\"left.tenant\",\"left.tenant\"]", "[\"right.embedding\",\"left.tenant\"]",
      "[\"left.tenant\",null]", "[\"left.tenant\",[\"right.serial\"]]", "[\"left.tenant\",1]",
      "[\"\",\"right.serial\"]",
    ] {
    assert_true(
      @vector_typing.check(
        ToVectors,
        cursor("{\"id\":" + id + ",\"vector\":\"right.embedding\"}"),
        composite_bridge_rows(),
        None,
        limits(),
      )
      is Err(_),
      msg=id,
    )
  }
  let issue = @vector_typing.check(
    ToVectors,
    cursor(
      "{\"id\":[\"left.tenant\",\"right.missing\"],\"vector\":\"right.embedding\"}",
    ),
    composite_bridge_rows(),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.path, [@source.Key("id"), @source.Index(1)])
  assert_true(
    issue.kind is InvalidRole(UnknownRole(Qualified(Right, "missing"))),
  )
}

///|
test "composite bridge charges the complete original role vector before admission" {
  let source = cursor(
    "{\"id\":[\"right.serial\",\"left.tenant\"],\"vector\":\"right.embedding\"}",
  )
  let rows = composite_bridge_rows()
  let checked = @vector_typing.check(ToVectors, source, rows, None, limits()).unwrap()
  let used = @vector_typing.usage(checked)
  let exact : @vector_typing.Limits = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    @vector_typing.check(ToVectors, source, rows, None, exact) is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      @vector_typing.check(ToVectors, source, rows, None, cap)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}
