///|
fn number() -> @contract.Contract {
  @contract.primitive(NumberType, nullable=false)
}

///|
fn make(
  entries : Array[(@relation_schema.FieldName, @contract.Contract)],
) -> @relation_schema.Schema {
  @relation_schema.from_fields(
    entries,
    max_fields=20000,
    max_name_bytes=1000000,
  ).unwrap()
}

///|
test "indexed reference spelling borrows canonical flat and qualified names" {
  let long = "x".repeat(256)
  for
    (entries, expected) in [
      ([(@relation_schema.Unqualified(long), number())], [long]),
      (
        [
          (@relation_schema.Qualified(@relation_schema.Right, long), number()),
          (@relation_schema.Qualified(@relation_schema.Left, long), number()),
        ],
        ["left." + long, "right." + long],
      ),
    ] {
    let schema = make(entries)
    for index, name in expected {
      assert_eq(
        @relation_schema.field_reference_name_at(schema, index),
        Some(name),
      )
    }
    assert_true(@relation_schema.field_reference_name_at(schema, -1) is None)
    assert_true(
      @relation_schema.field_reference_name_at(schema, expected.length())
      is None,
    )
  }
}

///|
test "flat row adapter preserves all child contracts without admitting nullable or nonobject roots" {
  let child = @contract.array_contract(
    @contract.decimal_contract(38, 7, nullable=true).unwrap(),
    nullable=false,
    max_items=Some(12L),
  ).unwrap()
  let row = @contract.object_contract(
    [("values", child)],
    nullable=false,
    max_fields=1,
    max_name_bytes=6,
  ).unwrap()
  let schema = @relation_schema.from_object(row).unwrap()
  assert_true(
    @contract.type_equal(@relation_schema.as_object(schema).unwrap(), row, 100),
  )
  assert_true(
    @contract.type_equal(
      @relation_schema.lookup(schema, Unqualified("values")).unwrap(),
      child,
      100,
    ),
  )
  assert_true(
    @relation_schema.from_object(@contract.with_nullability(row, true))
    is Err(InvalidRowContract),
  )
  assert_true(@relation_schema.from_object(number()) is Err(InvalidRowContract))
  assert_eq(@relation_schema.field_count(make([])), 0)
  assert_true(@relation_schema.as_object(make([])) is Some(_))
}

///|
test "qualified fields are structural provenance, not dotted authored names or nested paths" {
  let entries = [
    (
      @relation_schema.Qualified(Right, "id"),
      @contract.primitive(StringType, nullable=true),
    ),
    (Unqualified("id"), number()),
    (Qualified(Left, "id"), number()),
  ]
  let schema = make(entries)
  entries.clear()
  assert_eq(@relation_schema.field_count(schema), 3)
  assert_eq(@relation_schema.fields(schema).map(f => f.name), [
    Unqualified("id"),
    Qualified(Left, "id"),
    Qualified(Right, "id"),
  ])
  assert_true(@relation_schema.as_object(schema) is None)
  assert_true(
    @relation_schema.lookup(schema, Qualified(Right, "id")).unwrap().nullable,
  )
  assert_true(
    !@relation_schema.lookup(schema, Qualified(Left, "id")).unwrap().nullable,
  )
  assert_true(@relation_schema.lookup(schema, Unqualified("left.id")) is None)
  assert_true(
    @relation_schema.lookup(schema, Qualified(Left, "id.part")) is None,
  )
  @relation_schema.fields(schema).clear()
  assert_eq(@relation_schema.field_count(schema), 3)
  assert_true(@relation_schema.field_at(schema, -1) is None)
  assert_true(@relation_schema.field_at(schema, 3) is None)
}

///|
test "field views expose exact reference and contract to adapters" {
  let schema = make([
    (Qualified(Left, "source_id"), number()),
    (Unqualified("label"), @contract.primitive(StringType, nullable=true)),
  ])
  let label = @relation_schema.lookup_reference(schema, "label").unwrap()
  assert_eq(@relation_schema.field_reference_name(label), "label")
  assert_true(
    @contract.type_equal(
      @relation_schema.field_contract(label),
      @contract.primitive(StringType, nullable=true),
      2,
    ),
  )
  let source = @relation_schema.lookup_reference(schema, "left.source_id").unwrap()
  assert_eq(@relation_schema.field_reference_name(source), "left.source_id")
}

///|
test "field validation reuses authored leaf rules on both sides without normalizing names" {
  for leaf in ["", " ", "a.b", "__cid", "__actql_x", "e\u{301}", "a\r\nb"] {
    for
      name in [
        @relation_schema.Unqualified(leaf),
        Qualified(Left, leaf),
        Qualified(Right, leaf),
      ] {
      assert_true(
        @relation_schema.from_fields(
          [(name, number())],
          max_fields=1,
          max_name_bytes=100,
        )
        is Err(InvalidField(_, _)),
      )
    }
  }
  for leaf in ["first\nname", "\u{85}", "__proto__", "😀"] {
    let schema = make([(Qualified(Left, leaf), number())])
    assert_true(
      @relation_schema.lookup(schema, Qualified(Left, leaf)) is Some(_),
    )
  }
  let malformed = String::from_array([(0xD800).unsafe_to_char()])
  assert_true(
    @relation_schema.from_fields(
      [(Unqualified(malformed), number())],
      max_fields=1,
      max_name_bytes=100,
    )
    is Err(InvalidField(_, @contract.InvalidConstructionUnicode)),
  )
  for
    name in [
      @relation_schema.Unqualified("id"),
      Qualified(Left, "id"),
      Qualified(Right, "id"),
    ] {
    let e = @relation_schema.from_fields(
      [(name, number()), (name, number())],
      max_fields=2,
      max_name_bytes=100,
    ).unwrap_err()
    assert_eq(e, DuplicateField(name))
  }
}

///|
test "reference ordering is UTF16 and not input order or row ordering evidence" {
  let a = make([
    (Qualified(Left, "\u{e000}"), number()),
    (Qualified(Left, "😀"), number()),
    (Unqualified("z"), number()),
    (Unqualified("left"), number()),
  ])
  assert_eq(@relation_schema.fields(a).map(f => f.name), [
    Unqualified("left"),
    Qualified(Left, "😀"),
    Qualified(Left, "\u{e000}"),
    Unqualified("z"),
  ])
  let b = make([
    (Unqualified("\u{e000}"), number()),
    (Unqualified("😀"), number()),
  ])
  assert_eq(@relation_schema.fields(b).map(f => f.name), [
    Unqualified("😀"),
    Unqualified("\u{e000}"),
  ])
  assert_true(@relation_schema.lookup(a, Qualified(Left, "missing")) is None)
}

///|
test "construction limits count reference prefixes and accept exact UTF8 boundaries" {
  let entries = [
    (@relation_schema.Qualified(Left, "é"), number()),
    (Qualified(Right, "😀"), number()),
  ]
  assert_true(
    @relation_schema.from_fields(entries, max_fields=2, max_name_bytes=17)
    is Ok(_),
  )
  assert_true(
    @relation_schema.from_fields(entries, max_fields=2, max_name_bytes=16)
    is Err(LimitExceeded),
  )
  assert_true(
    @relation_schema.from_fields(entries, max_fields=1, max_name_bytes=17)
    is Err(LimitExceeded),
  )
  assert_true(
    @relation_schema.from_fields([], max_fields=0, max_name_bytes=0) is Ok(_),
  )
  assert_true(
    @relation_schema.from_fields([], max_fields=-1, max_name_bytes=0)
    is Err(InvalidLimits),
  )
  assert_true(
    @relation_schema.from_fields([], max_fields=0, max_name_bytes=-1)
    is Err(InvalidLimits),
  )
  assert_true(
    @relation_schema.from_fields(
      [(Qualified(Left, "id"), number())],
      max_fields=1,
      max_name_bytes=4,
    )
    is Err(LimitExceeded),
  )
}

///|
test "deep child contracts are shared and wide lookups preserve each typed name" {
  let mut deep = number()
  for _ in 0..<10000 {
    deep = @contract.array_contract(deep, nullable=false).unwrap()
  }
  let schema = make([(Qualified(Left, "deep"), deep)])
  let mut child = @relation_schema.lookup(schema, Qualified(Left, "deep")).unwrap()
  for _ in 0..<10000 {
    child = match child.shape {
      @contract.Array(item, ..) => item
      _ => abort("fixture")
    }
  }
  assert_true(child.shape is @contract.Number)
  let entries : Array[(@relation_schema.FieldName, @contract.Contract)] = []
  for i in 0..<10000 {
    entries.push((Qualified(Right, "f" + i.to_string()), number()))
  }
  let wide = make(entries)
  for i in 0..<10000 {
    assert_true(
      @relation_schema.lookup(wide, Qualified(Right, "f" + i.to_string()))
      is Some(_),
    )
  }
}
