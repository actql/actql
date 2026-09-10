///|
fn scalar(kind : String, nullable? : Bool = false) -> @value_contract.Contract {
  author(
    "{\"type\":\"" + kind + "\",\"nullable\":" + nullable.to_string() + "}",
  )
}

///|
test "all scalar type pairs and recursive-only types stay distinct" {
  let kinds = ["string", "number", "boolean", "timestamp", "date", "json"]
  for a in kinds {
    for b in kinds {
      let x = scalar(a)
      let y = scalar(b)
      assert_eq(@value_contract.type_equal(x, y, 1), a == b)
      assert_eq(@value_contract.assignable(x, y, 1), a == b)
      assert_eq(@value_contract.join_nullability(x, y, 1) is Some(_), a == b)
      assert_eq(@value_contract.key_comparable(x, y), a == b && a != "json")
    }
    let nonnull = scalar(a)
    let nullable = scalar(a, nullable=true)
    assert_true(!@value_contract.type_equal(nonnull, nullable, 1))
    assert_true(@value_contract.assignable(nonnull, nullable, 1))
    assert_true(!@value_contract.assignable(nullable, nonnull, 1))
    assert_true(
      @value_contract.type_equal(
        @value_contract.join_nullability(nonnull, nullable, 1).unwrap(),
        nullable,
        1,
      ),
    )
  }
  let object = author("{\"type\":\"object\",\"nullable\":false,\"fields\":{}}")
  let array = author(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  let vector = author(
    "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":1}",
  )
  for value in [object, array, vector] {
    assert_true(!@value_contract.key_comparable(value, value))
    assert_true(!@value_contract.assignable(value, scalar("json"), 2))
  }
}

///|
test "text bounds equality directional assignment and least restrictive join" {
  let tight = checked(
    "{\"type\":\"string\",\"nullable\":false,\"min_length\":3,\"max_codepoints\":5,\"max_utf8_bytes\":8}",
  )
  let broad = checked(
    "{\"type\":\"string\",\"nullable\":true,\"min_length\":1,\"max_codepoints\":10,\"max_utf8_bytes\":20}",
  )
  assert_true(@value_contract.assignable(tight, broad, 1))
  assert_true(!@value_contract.assignable(broad, tight, 1))
  assert_true(
    @value_contract.type_equal(
      @value_contract.join_nullability(tight, broad, 1).unwrap(),
      broad,
      1,
    ),
  )
  let free = scalar("string", nullable=true)
  assert_true(@value_contract.assignable(tight, free, 1))
  assert_true(!@value_contract.assignable(free, tight, 1))
  assert_true(
    @value_contract.type_equal(
      @value_contract.join_nullability(tight, free, 1).unwrap(),
      free,
      1,
    ),
  )
  let zero = checked(
    "{\"type\":\"string\",\"nullable\":false,\"min_length\":0}",
  )
  assert_true(!@value_contract.type_equal(zero, scalar("string"), 1))
  assert_true(@value_contract.key_comparable(tight, broad))
}

///|
test "nested nullability and array extents combine at every position" {
  let a = author(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"b\":{\"type\":\"number\",\"nullable\":true},\"a\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}}}",
  )
  let b = author(
    "{\"type\":\"object\",\"nullable\":true,\"fields\":{\"a\":{\"type\":\"array\",\"nullable\":true,\"max_items\":4,\"items\":{\"type\":\"number\",\"nullable\":true}},\"b\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  let expected = author(
    "{\"type\":\"object\",\"nullable\":true,\"fields\":{\"a\":{\"type\":\"array\",\"nullable\":true,\"max_items\":4,\"items\":{\"type\":\"number\",\"nullable\":true}},\"b\":{\"type\":\"number\",\"nullable\":true}}}",
  )
  let joined = @value_contract.join_nullability(a, b, 4).unwrap()
  assert_true(@value_contract.type_equal(joined, expected, 4))
  assert_true(@value_contract.assignable(a, joined, 4))
  assert_true(@value_contract.assignable(b, joined, 4))
  assert_true(!@value_contract.assignable(a, b, 4))
  assert_true(
    @value_contract.type_equal(
      joined,
      @value_contract.join_nullability(b, a, 4).unwrap(),
      4,
    ),
  )
  assert_true(@value_contract.type_equal(a, checked(render(a)), 4))
  let missing_field = author(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{}}",
  )
  assert_true(!@value_contract.assignable(a, missing_field, 4))
  assert_true(@value_contract.join_nullability(a, missing_field, 4) is None)
  let free = author(
    "{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  let zero = author(
    "{\"type\":\"array\",\"nullable\":false,\"max_items\":0,\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  assert_true(@value_contract.assignable(zero, free, 2))
  assert_true(!@value_contract.assignable(free, zero, 2))
  assert_true(
    @value_contract.type_equal(
      @value_contract.join_nullability(zero, free, 2).unwrap(),
      free,
      2,
    ),
  )
}

///|
test "decimal vector and reference parameters use distinct relations" {
  let d1 = author(
    "{\"type\":\"decimal\",\"nullable\":false,\"precision\":18,\"scale\":2}",
  )
  let d2 = author(
    "{\"type\":\"decimal\",\"nullable\":true,\"precision\":38,\"scale\":3}",
  )
  assert_true(!@value_contract.type_equal(d1, d2, 1))
  assert_true(!@value_contract.assignable(d1, d2, 1))
  assert_true(@value_contract.join_nullability(d1, d2, 1) is None)
  assert_true(@value_contract.key_comparable(d1, d2))
  let v1 = author("{\"type\":\"vector\",\"nullable\":false,\"dimensions\":2}")
  let v2 = author("{\"type\":\"vector\",\"nullable\":false,\"dimensions\":3}")
  assert_true(!@value_contract.assignable(v1, v2, 1))
  assert_true(@value_contract.join_nullability(v1, v2, 1) is None)
  let r1 = author(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"a\"}",
  )
  let r2 = author(
    "{\"type\":\"resource_ref\",\"nullable\":false,\"resource_kind\":\"b\"}",
  )
  assert_true(!@value_contract.key_comparable(r1, r2))
  assert_true(@value_contract.key_comparable(r1, r1))
  assert_true(@value_contract.join_nullability(r1, r2, 1) is None)
  let pdf = author(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/pdf\"}",
  )
  let json = author(
    "{\"type\":\"artifact_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
  )
  let any = scalar("artifact_ref")
  assert_true(@value_contract.assignable(pdf, any, 1))
  assert_true(!@value_contract.assignable(any, pdf, 1))
  assert_true(!@value_contract.assignable(pdf, json, 1))
  assert_true(@value_contract.key_comparable(pdf, json))
  assert_true(
    @value_contract.type_equal(
      @value_contract.join_nullability(pdf, json, 1).unwrap(),
      any,
      1,
    ),
  )
  assert_true(!@value_contract.key_comparable(pdf, r1))
}

///|
test "relation budgets are explicit and failures return no partial join" {
  let value = scalar("number")
  assert_true(
    try {
      ignore(@value_contract.type_equal(value, value, -1))
      false
    } catch {
      @value_contract.InvalidRelationLimit => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(@value_contract.assignable(value, value, 0))
      false
    } catch {
      @value_contract.RelationLimit => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(@value_contract.join_nullability(value, value, 0))
      false
    } catch {
      @value_contract.RelationLimit => true
      _ => false
    },
  )
  let a = author(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  let b = author(
    "{\"type\":\"object\",\"nullable\":false,\"fields\":{\"y\":{\"type\":\"number\",\"nullable\":false}}}",
  )
  assert_true(!@value_contract.type_equal(a, b, 2))
  assert_true(@value_contract.join_nullability(a, b, 2) is None)
}
