///|
test "cross join qualifies every field without null extension or equality keys" {
  let p = @relation_join.check_cross(
    cursor("{\"with\":\"right\"}"),
    row(),
    row(),
    None,
    limits(),
  ).unwrap()
  let output = @relation_join.cross_output_schema(p)
  for side in [@schema.Left, @schema.Right] {
    for f in @schema.fields(row()) {
      let name = match f.name {
        Unqualified(n) => n
        _ => abort("flat test schema")
      }
      assert_true(
        @contract.type_equal(
          @schema.lookup(output, Qualified(side, name)).unwrap(),
          f.contract,
          100,
        ),
      )
    }
  }
  assert_eq(@schema.field_count(output), 2 * @schema.field_count(row()))
  assert_true(@relation_join.cross_projection(p) is None)
  assert_eq(@relation_join.cross_requires_one_right_row(p), false)
  assert_eq(
    indexed_obligation_copy(
      @relation_join.cross_pending_validations(p),
      @relation_join.cross_pending_validation_count(p),
      i => @relation_join.cross_pending_validation_at(p, i),
      (a, b) => a == b,
    ),
    [
      ResolveProductBound,
      ResolveOutputLimit,
      PreserveLeftMajorProductOrder,
      StableIdentity(@schema.Left),
      StableIdentity(@schema.Right),
    ],
  )
}

///|
test "cross singleton assertions and aliases are retained without fabricated evidence" {
  let p = @relation_join.check_cross(
    cursor(
      "{\"with\":\"r\",\"right_rows\":\"one\",\"select\":{\"z\":\"right.id\",\"a\":\"left.id\",\"again\":\"left.id\"},\"max_output_rows\":7}",
    ),
    row(),
    row(),
    None,
    limits(),
  ).unwrap()
  assert_true(@relation_join.cross_requires_one_right_row(p))
  assert_eq(@relation_join.cross_output_guard(p), Some(Literal(7L)))
  let projection = @relation_join.cross_projection(p).unwrap()
  assert_eq(projection.map(p => p.output), [
    Unqualified("a"),
    Unqualified("again"),
    Unqualified("z"),
  ])
  assert_eq(projection.map(p => p.input), [
    Qualified(Left, "id"),
    Qualified(Left, "id"),
    Qualified(Right, "id"),
  ])
  projection.clear()
  assert_eq(@relation_join.cross_projection(p).unwrap().length(), 3)
  let pending = indexed_obligation_copy(
    @relation_join.cross_pending_validations(p),
    @relation_join.cross_pending_validation_count(p),
    i => @relation_join.cross_pending_validation_at(p, i),
    (a, b) => a == b,
  )
  assert_true(pending.contains(ValidateExactlyOneRightRow))
  pending.clear()
  assert_eq(
    indexed_obligation_copy(
      @relation_join.cross_pending_validations(p),
      @relation_join.cross_pending_validation_count(p),
      i => @relation_join.cross_pending_validation_at(p, i),
      (a, b) => a == b,
    ).length(),
    6,
  )
}

///|
test "cross closed syntax and malformed projections or guards are rejected" {
  for
    extra in [
      ",\"on\":\"id\"", ",\"left\":\"x\"", ",\"kind\":\"inner\"", ",\"right_rows\":\"ONE\"",
      ",\"right_rows\":null", ",\"right_rows\":{\"$param\":\"n\"}",
    ] {
    assert_true(
      @relation_join.check_cross(
        cursor("{\"with\":\"r\"" + extra + "}"),
        row(),
        row(),
        None,
        limits(),
      )
      is Err({ kind: InvalidBody, .. }),
    )
  }
  for
    selection in [
      "{}", "{\"id\":\"id\"}", "{\"id\":\"right.missing\"}", "{\"left.id\":\"right.id\"}",
    ] {
    assert_true(
      @relation_join.check_cross(
        cursor("{\"with\":\"r\",\"select\":" + selection + "}"),
        row(),
        row(),
        None,
        limits(),
      )
      is Err(_),
    )
  }
  for guard_text in ["0", "-1", "1.5", "9007199254740992", "null", "\"2\""] {
    let e = @relation_join.check_cross(
      cursor("{\"with\":\"r\",\"max_output_rows\":" + guard_text + "}"),
      row(),
      row(),
      None,
      limits(),
    ).unwrap_err()
    assert_eq(e.kind, InvalidGuard)
    assert_eq(e.path, [Key("max_output_rows")])
  }
}

///|
test "cross accepts empty flat schemas and rejects qualified operands" {
  let empty = @schema.from_fields([], max_fields=0, max_name_bytes=0).unwrap()
  let body = cursor("{\"with\":\"r\",\"right_rows\":\"one\"}")
  let p = @relation_join.check_cross(body, empty, empty, None, limits()).unwrap()
  assert_eq(@schema.field_count(@relation_join.cross_output_schema(p)), 0)
  assert_true(@relation_join.cross_requires_one_right_row(p))
  let scoped = @schema.from_fields(
    [(Qualified(Left, "id"), @contract.primitive(StringType, nullable=false))],
    max_fields=1,
    max_name_bytes=7,
  ).unwrap()
  assert_true(
    @relation_join.check_cross(body, scoped, empty, None, limits())
    is Err({ kind: QualifiedInput(Left), .. }),
  )
  assert_true(
    @relation_join.check_cross(body, empty, scoped, None, limits())
    is Err({ kind: QualifiedInput(Right), .. }),
  )
}

///|
test "cross exact cumulative limits include source and both operands" {
  let body = cursor(
    "{\"with\":\"r\",\"right_rows\":\"one\",\"max_output_rows\":100}",
  )
  let p = @relation_join.check_cross(body, row(), row(), None, limits()).unwrap()
  let used = @relation_join.cross_usage(p)
  let exact : @relation_join.Limits = {
    ..limits(),
    max_work: used.work,
    max_text_bytes: used.text_bytes,
    max_nodes: used.nodes,
  }
  assert_true(
    @relation_join.check_cross(body, row(), row(), None, exact) is Ok(_),
  )
  for
    small in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_depth: 0, },
    ] {
    assert_true(
      @relation_join.check_cross(body, row(), row(), None, small)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
}

///|
test "cross symbolic output guards preserve unresolved binding checks" {
  let declarations = @parameter.read_declarations(
    Some(
      cursor(
        "{\"cap\":{\"type\":\"number\",\"default\":5},\"bad\":{\"type\":\"string\"}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let p = @relation_join.check_cross(
    cursor("{\"with\":\"r\",\"max_output_rows\":{\"$param\":\"cap\"}}"),
    row(),
    row(),
    Some(declarations),
    limits(),
  ).unwrap()
  assert_eq(@relation_join.cross_output_guard(p), Some(Parameter("cap")))
  assert_true(
    indexed_obligation_copy(
      @relation_join.cross_pending_validations(p),
      @relation_join.cross_pending_validation_count(p),
      i => @relation_join.cross_pending_validation_at(p, i),
      (a, b) => a == b,
    ).contains(BindGuard("cap")),
  )
  for name in ["bad", "missing"] {
    assert_true(
      @relation_join.check_cross(
        cursor(
          "{\"with\":\"r\",\"max_output_rows\":{\"$param\":\"" + name + "\"}}",
        ),
        row(),
        row(),
        Some(declarations),
        limits(),
      )
      is Err(_),
    )
  }
}
