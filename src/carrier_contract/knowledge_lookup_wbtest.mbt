///|
test "virtual lookup comparison preserves complete UTF16 spelling order without flattening qualification" {
  let long = String::make(130, 'a') + "😀é"
  let names : Array[@row.FieldName] = [
    Unqualified(""),
    Unqualified("a"),
    Unqualified("é"),
    Unqualified("é"),
    Unqualified("😀"),
    Unqualified("\ue000"),
    Unqualified("left." + long),
    Qualified(Left, long),
    Qualified(Right, long),
  ]
  for left in names {
    for right in names {
      // Independent original materialized spelling algorithm, not fragments.
      let original = @canonical.compare_utf16(
        @row.reference_name(left),
        @row.reference_name(right),
      )
      assert_eq(compare_knowledge_reference(left, right), original)
    }
  }
}

///|
test "virtual lookup retains original field and exact open closed untyped qualification distinctions" {
  let long = String::make(130, 'a') + "é"
  let name = @row.Qualified(Left, long)
  for set in [Open, Closed] {
    let original = rows(
      [(name, None)],
      field_set=set,
      max_fields=1,
      max_name_bytes=1000,
    ).unwrap()
    let field = field_at(original, 0).unwrap()
    guard lookup(original, name) is Present(found) else {
      abort("original field expected")
    }
    assert_true(physical_equal(found, field))
    assert_true(found.contract is None)
    assert_true(complete_schema(original) is None)
    if set == Open {
      assert_true(lookup(original, @row.Unqualified("left." + long)) is Unknown)
      assert_true(lookup(original, @row.Qualified(Right, long)) is Unknown)
    } else {
      assert_true(lookup(original, @row.Unqualified("left." + long)) is Absent)
      assert_true(lookup(original, @row.Qualified(Right, long)) is Absent)
    }
  }
}
