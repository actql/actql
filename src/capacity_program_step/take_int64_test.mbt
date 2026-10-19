///|
test "take capacity uses the exact original int64 count without changing the count law" {
  let declarations = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"int64\"}}")),
    { max_parameters: 1, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
  ).unwrap()
  let p = pipeline(
    "[{\"take\":{\"$param\":\"n\"}}]",
    parameters=Some(declarations),
  )
  for
    (text, valid) in [
      ("1", true),
      ("9007199254740991", true),
      ("0", false),
      ("-1", false),
      ("9007199254740992", false),
      ("9223372036854775807", false),
    ] {
    let values = count_values(declarations, Some("{\"n\":\"" + text + "\"}"))
    let bindings = @capacity_program_step.bind_parameters(
      p,
      values,
      max_work=1,
      max_text_bytes=1,
    ).unwrap()
    let derived = @capacity_program_step.derive_bound(
      p,
      0,
      [],
      derive_limits(),
      bindings=Some(bindings),
    )
    assert_eq(derived is Ok(_), valid)
    if valid {
      let bound = derived.unwrap().bound
      let claim = @capacity_program_step.checked_proof(bound)
      assert_eq(
        @wire.value(@wire.program_proof_witness(claim)).to_string(),
        text,
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          0,
          claim,
          [],
          bindings=Some(bindings),
        )
        is Ok(_),
      )
      let foreign = pipeline(
        "[{\"take\":{\"$param\":\"n\"}}]",
        parameters=Some(declarations),
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          foreign,
          0,
          claim,
          [],
          bindings=Some(bindings),
        )
        is Err(_),
      )
    }
  }
}
