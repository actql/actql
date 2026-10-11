///|
test "GoogleSQL Unicode scalar spellings and quoted octet alias share unary identity" {
  for
    (name, tag) in [
      ("BYTE_LENGTH", "byte_length"),
      ("OCTET_LENGTH", "byte_length"),
      ("UNICODE", "unicode"),
      ("CHR", "chr"),
    ] {
    for spelling in [name, name.to_lower(), "`" + name + "`"] {
      assert_eq(emit(spelling + "(@p)"), "{\"" + tag + "\":{\"$param\":\"p\"}}")
      for args in ["", "1,2"] {
        assert_true(
          lower(fixture(spelling + "(" + args + ")"), _ => None, limits())
          is Err({ issue: InvalidArguments, .. }),
        )
      }
    }
    assert_true(
      lower(fixture("ACTQL." + name + "(1)"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
  }
  assert_true(
    same_scalar_function(
      scalar_identity_name("byte_length"),
      scalar_identity_name("OCTET_LENGTH", quoted=true),
    ),
  )
  assert_false(
    same_scalar_function(
      scalar_identity_name("BYTE_LENGTH"),
      scalar_identity_name("LENGTH"),
    ),
  )
  assert_false(
    same_scalar_function(
      scalar_identity_name("UNICODE"),
      scalar_identity_name("CHR"),
    ),
  )
}
