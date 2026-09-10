///|
test "constructed primitives retain the admitted checked representation" {
  for
    (kind, name) in [
      (@value_contract.StringType, "string"),
      (@value_contract.NumberType, "number"),
      (@value_contract.BooleanType, "boolean"),
      (@value_contract.DateType, "date"),
      (@value_contract.TimestampType, "timestamp"),
      (@value_contract.JsonType, "json"),
    ] {
    for nullable in [false, true] {
      let value = @value_contract.primitive(kind, nullable~)
      let expected = author(
        "{\"type\":\"" + name + "\",\"nullable\":" + nullable.to_string() + "}",
      )
      assert_true(@value_contract.type_equal(value, expected, 1))
    }
  }
}

///|
test "constructed numeric parameters match admission without new upper bounds" {
  for precision = -1; precision <= 39; precision = precision + 1 {
    for scale = -1; scale <= 40; scale = scale + 1 {
      let result = @value_contract.decimal_contract(
        precision,
        scale,
        nullable=false,
      )
      if precision >= 1 && precision <= 38 && scale >= 0 && scale <= precision {
        let expected = author(
          "{\"type\":\"decimal\",\"nullable\":false,\"precision\":" +
          precision.to_string() +
          ",\"scale\":" +
          scale.to_string() +
          "}",
        )
        assert_true(@value_contract.type_equal(result.unwrap(), expected, 1))
      } else {
        assert_true(result is None)
      }
    }
  }
  for dimensions in [1.0, 3.0, 9007199254740992.0, 1.0e100] {
    let expected = author(
      "{\"type\":\"vector\",\"nullable\":false,\"dimensions\":" +
      dimensions.to_string() +
      "}",
    )
    assert_true(
      @value_contract.type_equal(
        @value_contract.vector_contract(dimensions, nullable=false).unwrap(),
        expected,
        1,
      ),
    )
  }
  for dimensions in [-1.0, -0.0, 0.0, 0.5, 1.5, 0.0 / 0.0, 1.0 / 0.0] {
    assert_true(
      @value_contract.vector_contract(dimensions, nullable=false) is None,
    )
  }
}

///|
test "constructed bounds preserve safe integer limits and independent constraints" {
  let number = @value_contract.primitive(NumberType, nullable=false)
  for bound in [-1L, 0L, 1L, 9007199254740991L, 9007199254740992L] {
    let valid = bound >= 0L && bound <= 9007199254740991L
    assert_eq(
      @value_contract.array_contract(
        number,
        nullable=false,
        max_items=Some(bound),
      )
      is Some(_),
      valid,
    )
    assert_eq(
      @value_contract.string_contract(nullable=false, min_length=Some(bound))
      is Some(_),
      valid,
    )
    assert_eq(
      @value_contract.string_contract(
        nullable=false,
        max_codepoints=Some(bound),
      )
      is Some(_),
      valid,
    )
    assert_eq(
      @value_contract.string_contract(
        nullable=false,
        max_utf8_bytes=Some(bound),
      )
      is Some(_),
      valid,
    )
  }
  let value = @value_contract.string_contract(
    nullable=true,
    min_length=Some(3L),
    max_codepoints=Some(1L),
    max_utf8_bytes=Some(0L),
  ).unwrap()
  let expected = @value_contract.read_checked(
    cursor(
      "{\"type\":\"string\",\"nullable\":true,\"min_length\":3,\"max_codepoints\":1,\"max_utf8_bytes\":0}",
    ),
    limits(),
  ).unwrap()
  assert_true(@value_contract.type_equal(value, expected, 1))
  let array = @value_contract.array_contract(
    number,
    nullable=false,
    max_items=Some(0L),
  ).unwrap()
  let widened = @value_contract.with_nullability(array, true)
  assert_true(!array.nullable)
  assert_true(widened.nullable)
  match widened.shape {
    Array(item, max_items~) => {
      assert_true(!item.nullable)
      assert_eq(max_items, Some(0L))
    }
    _ => assert_true(false)
  }
  assert_true(
    @value_contract.type_equal(
      @value_contract.with_nullability(widened, false),
      array,
      2,
    ),
  )
}

///|
test "object assembly checks canonical names and copies the input collection" {
  let number = @value_contract.primitive(NumberType, nullable=false)
  let entries = [
    ("\u{10000}", number),
    ("\ue000", number),
    ("first\nname", number),
  ]
  let value = @value_contract.object_contract(
    entries,
    nullable=false,
    max_fields=3,
    max_name_bytes=17,
  ).unwrap()
  entries[0] = ("replacement", number)
  entries.clear()
  match value.shape {
    Object(fields) => {
      assert_eq(@value_contract.field_count(fields), 3)
      assert_eq(
        @value_contract.field_at(fields, 0).unwrap().name,
        "first\nname",
      )
      assert_eq(@value_contract.field_at(fields, 1).unwrap().name, "\u{10000}")
      assert_eq(@value_contract.field_at(fields, 2).unwrap().name, "\ue000")
      assert_true(@value_contract.field_at(fields, -1) is None)
      assert_true(@value_contract.field_at(fields, 3) is None)
      let copy = @value_contract.fields(fields)
      copy.clear()
      assert_eq(@value_contract.field_count(fields), 3)
    }
    _ => assert_true(false)
  }
  let empty = @value_contract.object_contract(
    [],
    nullable=false,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  assert_true(
    @value_contract.type_equal(
      empty,
      author("{\"type\":\"object\",\"nullable\":false,\"fields\":{}}"),
      1,
    ),
  )
  for name in ["", " ", "\ufeff", "a.b", "__cid", "__actql_x"] {
    assert_true(
      @value_contract.object_contract(
        [(name, number)],
        nullable=false,
        max_fields=1,
        max_name_bytes=100,
      )
      is Err(InvalidConstructionName(_)),
    )
  }
  for name in ["e\u0301", "a\r\nb"] {
    assert_true(
      @value_contract.object_contract(
        [(name, number)],
        nullable=false,
        max_fields=1,
        max_name_bytes=100,
      )
      is Err(NonCanonicalConstructionName(_)),
    )
  }
  assert_true(
    @value_contract.object_contract(
      [("\u0085", number)],
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    )
    is Ok(_),
  )
  assert_true(
    @value_contract.object_contract(
      [("x", number), ("x", number)],
      nullable=false,
      max_fields=2,
      max_name_bytes=2,
    )
    is Err(DuplicateConstructionName("x")),
  )
  let malformed = String::from_array([(0xd800).unsafe_to_char()])
  assert_true(
    @value_contract.object_contract(
      [(malformed, number)],
      nullable=false,
      max_fields=1,
      max_name_bytes=100,
    )
    is Err(InvalidConstructionUnicode),
  )
}

///|
test "object assembly budgets new structure without walking admitted children" {
  let mut child = @value_contract.primitive(NumberType, nullable=false)
  for _ in 0..<10000 {
    child = @value_contract.array_contract(child, nullable=false).unwrap()
  }
  let entries = [("é", child)]
  assert_true(
    @value_contract.object_contract(
      entries,
      nullable=false,
      max_fields=1,
      max_name_bytes=2,
    )
    is Ok(_),
  )
  assert_true(
    @value_contract.object_contract(
      entries,
      nullable=false,
      max_fields=0,
      max_name_bytes=2,
    )
    is Err(ConstructionLimit),
  )
  assert_true(
    @value_contract.object_contract(
      entries,
      nullable=false,
      max_fields=1,
      max_name_bytes=1,
    )
    is Err(ConstructionLimit),
  )
  assert_true(
    @value_contract.object_contract(
      entries,
      nullable=false,
      max_fields=-1,
      max_name_bytes=2,
    )
    is Err(InvalidConstructionLimits),
  )
  assert_true(
    @value_contract.object_contract(
      entries,
      nullable=false,
      max_fields=1,
      max_name_bytes=-1,
    )
    is Err(InvalidConstructionLimits),
  )
}
