///|
test "bridge identity domains and qualified roles retain exact contracts" {
  for
    id in [
      @contract.primitive(StringType, nullable=false),
      @contract.decimal_contract(38, 9, nullable=false).unwrap(),
      @contract.primitive(NumberType, nullable=true),
      @contract.primitive(JsonType, nullable=false),
    ] {
    let rows = @carrier.rows(
      [
        (@row.Qualified(Left, "id"), Some(id)),
        (
          @row.Qualified(Right, "embedding"),
          Some(@contract.vector_contract(2, nullable=false).unwrap()),
        ),
      ],
      field_set=Closed,
      max_fields=2,
      max_name_bytes=100,
    ).unwrap()
    let result = @vector_typing.check(
      ToVectors,
      cursor("{\"id\":\"left.id\",\"vector\":\"right.embedding\"}"),
      @carrier.relation(rows),
      None,
      limits(),
    )
    if id.nullable || id.shape is Json {
      assert_true(
        result
        is Err({ kind: InvalidRole(InvalidRole(Qualified(Left, "id"))), .. }),
      )
    } else {
      guard @vector_typing.output(result.unwrap()) is @carrier.VectorValue(v) else {
        abort("vectors")
      }
      assert_eq(
        @carrier.vector_identities(v)[0].name,
        @row.Qualified(Left, "id"),
      )
      assert_true(
        @contract.type_equal(
          @carrier.vector_identities(v)[0].contract.unwrap(),
          id,
          10,
        ),
      )
      assert_eq(
        @carrier.vector_components(v).name,
        @row.Qualified(Right, "embedding"),
      )
    }
  }
}

///|
test "explicit vector bridge preserves semantic names and non-string identities" {
  guard vectors() is @carrier.VectorValue(v) else { abort("vectors") }
  let records = @carrier.vector_records(v)
  let checked = @vector_typing.check(
    ToVectors,
    cursor("{\"id\":\"id\",\"vector\":\"embedding\"}"),
    @carrier.relation(records),
    None,
    limits(),
  ).unwrap()
  guard @vector_typing.output(checked) is @carrier.VectorValue(result) else {
    abort("vectors")
  }
  assert_eq(
    @carrier.vector_components(result).name,
    @row.Unqualified("embedding"),
  )
  assert_true(
    @carrier.vector_identities(result)[0].contract.unwrap().shape is Number,
  )
  assert_true(
    @carrier.lookup(@carrier.vector_records(result), Unqualified("vector"))
    is Absent,
  )
  assert_true(
    indexed_obligation_copy(
      @vector_typing.pending_validations(checked),
      @vector_typing.pending_validation_count(checked),
      i => @vector_typing.pending_validation_at(checked, i),
      (a, b) => a == b,
    ).contains(ValidateUniqueIdentities),
  )
  let issue = @vector_typing.check(
    ToVectors,
    cursor("{\"id\":\"payload\",\"vector\":\"embedding\"}"),
    @carrier.relation(records),
    None,
    limits(),
  ).unwrap_err()
  assert_eq(issue.path, [@source.Key("id")])
  assert_true(issue.kind is InvalidRole(UnknownRole(Unqualified("payload"))))
}

///|
test "vector bridge accepts open payload knowledge but requires typed roles" {
  guard vectors(open=true) is @carrier.VectorValue(v) else { abort("vectors") }
  let records = @carrier.vector_records(v)
  assert_true(
    @vector_typing.check(
      ToVectors,
      cursor("{\"id\":\"id\",\"vector\":\"embedding\"}"),
      @carrier.relation(records),
      None,
      limits(),
    )
    is Ok(_),
  )
  for
    body in [
      "{\"id\":\"id\",\"vector\":\"missing\"}", "{\"id\":\"id\",\"vector\":\"id\"}",
      "{\"id\":\"id\"}", "{\"id\":\"id\",\"vector\":\"embedding\",\"extra\":true}",
    ] {
    assert_true(
      @vector_typing.check(
        ToVectors,
        cursor(body),
        @carrier.relation(records),
        None,
        limits(),
      )
      is Err(_),
    )
  }
}
