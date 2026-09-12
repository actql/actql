///|
test "admission usage accounts for typed values keys vectors and decimal text" {
  let c = contract(
    (
      #|{"type":"object","nullable":false,"fields":{"s":{"type":"string","nullable":false},"v":{"type":"vector","nullable":false,"dimensions":2},"d":{"type":"decimal","nullable":false,"precision":3,"scale":2}}}
    ),
  )
  let cursor = owned(parsed("{\"s\":\"é\",\"v\":[1,2],\"d\":\"1.20\"}"))
  let (checked, nodes, bytes) = @value_admission.admit_usage(
    c,
    cursor,
    limits(),
  ).unwrap()
  assert_true(physical_equal(checked.contract, c))
  assert_eq((nodes, bytes), (6, 9))
  assert_true(
    @value_admission.admit_usage(c, cursor, limits(nodes~, text=bytes, depth=2))
    is Ok(_),
  )
  assert_true(
    @value_admission.admit_usage(c, cursor, limits(nodes=nodes - 1, text=bytes))
    is Err(_),
  )
  assert_true(
    @value_admission.admit_usage(c, cursor, limits(nodes~, text=bytes - 1))
    is Err(_),
  )
  assert_true(
    @value_admission.admit_usage(c, cursor, limits(depth=1)) is Err(_),
  )
  assert_true(
    @value_admission.admit_usage(c, cursor, limits(nodes=-1)) is Err(_),
  )
  // Reusing the remainder admits one more scalar, but cannot reset text usage.
  let scalar = simple("string")
  let rest = @value_admission.admit_usage(
    scalar,
    owned(parsed("\"é\"")),
    limits(nodes=7 - nodes, text=11 - bytes),
  ).unwrap()
  assert_eq((rest.1, rest.2), (1, 2))
  assert_true(
    @value_admission.admit_usage(
      scalar,
      owned(parsed("\"é\"")),
      limits(nodes=7 - nodes, text=10 - bytes),
    )
    is Err(_),
  )
}

///|
test "nullable reference absence carries no reference authority and costs one node" {
  for name in ["artifact_ref", "resource_ref"] {
    let extra = if name == "resource_ref" {
      ",\"resource_kind\":\"record\""
    } else {
      ""
    }
    let wire = "{\"type\":\"" + name + "\",\"nullable\":true" + extra + "}"
    let c = contract(wire)
    let (checked, nodes, bytes) = @value_admission.admit_usage(
      c,
      owned(parsed("null")),
      limits(nodes=1, depth=0, text=0),
    ).unwrap()
    assert_true(checked.value is @value_admission.Null)
    assert_eq((nodes, bytes), (1, 0))
    assert_eq(
      outcome(
        @value_admission.admit(
          @contract.with_nullability(c, false),
          owned(parsed("null")),
          limits(),
        ),
      ),
      "UnexpectedNull",
    )
    let array = @contract.array_contract(c, nullable=false).unwrap()
    let admitted = @value_admission.admit_usage(
      array,
      owned(parsed("[null,null]")),
      limits(nodes=3, depth=1, text=0),
    ).unwrap()
    assert_eq((admitted.1, admitted.2), (3, 0))
    assert_true(admitted.0.value is @value_admission.Array(_))
    assert_true(
      @value_admission.admit_usage(array, owned(parsed("[null,{}]")), limits())
      is Err(_),
    )
  }
}
