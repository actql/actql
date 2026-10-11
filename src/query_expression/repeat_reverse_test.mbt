///|
test "GoogleSQL repeat and reverse spellings retain distinct canonical arities" {
  for spelling in ["REPEAT", "repeat", "rEpEaT", "`REPEAT`"] {
    assert_eq(
      emit(spelling + "(s,@n)"),
      "{\"repeat\":[{\"field\":\"s\"},{\"$param\":\"n\"}]}",
    )
    for args in ["", "'a'", "'a',2,3"] {
      assert_true(
        lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
  }
  for spelling in ["REVERSE", "reverse", "rEvErSe", "`REVERSE`"] {
    assert_eq(emit(spelling + "(@s)"), "{\"reverse\":{\"$param\":\"s\"}}")
    for args in ["", "'a','b'"] {
      assert_true(
        lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
  }
  for name in ["REPEAT", "REVERSE"] {
    assert_true(
      lower(fixture("ACTQL." + name + "('a',2)"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
    assert_true(
      same_scalar_function(
        scalar_identity_name(name.to_lower()),
        scalar_identity_name(name, quoted=true),
      ),
    )
  }
  assert_false(
    same_scalar_function(
      scalar_identity_name("REPEAT"),
      scalar_identity_name("REVERSE"),
    ),
  )
}
