///|
fn scalar_identity_name(
  value : String,
  quoted? : Bool = false,
) -> Array[@query.NamePart] {
  [{ value, quoted, }]
}

///|
test "scalar reuse identity comes from the installed lowering registry" {
  for
    (left, right) in [
      ("char_length", "CHARACTER_LENGTH"),
      ("CEIL", "CEILING"),
      ("SUBSTR", "SUBSTRING"),
    ] {
    assert_true(
      same_scalar_function(
        scalar_identity_name(left),
        scalar_identity_name(right, quoted=true),
      ),
    )
    assert_true(
      same_scalar_function(
        scalar_identity_name(right),
        scalar_identity_name(left),
      ),
    )
  }
  for
    (left, right) in [
      ("LENGTH", "ABS"),
      ("LENGTH", "CHAR_LENGTH"),
      ("CEIL", "FLOOR"),
      ("IFNULL", "COALESCE"),
      ("unknown", "unknown"),
    ] {
    assert_false(
      same_scalar_function(
        scalar_identity_name(left),
        scalar_identity_name(right),
      ),
    )
  }
  assert_false(
    same_scalar_function(
      [{ value: "ACTQL", quoted: false, }, { value: "CONCAT", quoted: false, }],
      scalar_identity_name("CONCAT"),
    ),
  )
  assert_false(
    same_scalar_function(
      [{ value: "other", quoted: false, }, { value: "LENGTH", quoted: false, }],
      scalar_identity_name("LENGTH"),
    ),
  )
}
