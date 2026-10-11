///|
test "translate instr lowering retains authored default omission and ordered array bodies" {
  {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":\"translate('ab','ab','ba')\"}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":\"ab\",\"op\":\"literal\"},{\"body\":\"ab\",\"op\":\"literal\"},{\"body\":\"ba\",\"op\":\"literal\"}],\"op\":\"translate\"}",
    )
  }
  {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":\"instr('banana','an')\"}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":\"banana\",\"op\":\"literal\"},{\"body\":\"an\",\"op\":\"literal\"}],\"op\":\"instr\"}",
    )
  }
  {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":\"instr('banana','an',1)\"}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":\"banana\",\"op\":\"literal\"},{\"body\":\"an\",\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"instr\"}",
    )
  }
  {
    let owner = expression_pipeline(
      ",{\"derive\":{\"value\":\"instr('banana','an',1,1)\"}}",
    )
    let expression = @lowering_relation.lower_expression(
      owner,
      1,
      0,
      expression_limits(),
    ).unwrap()
    assert_eq(
      expression_wire(expression),
      "{\"body\":[{\"body\":\"banana\",\"op\":\"literal\"},{\"body\":\"an\",\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"},{\"body\":1,\"op\":\"literal\"}],\"op\":\"instr\"}",
    )
  }
  let owner = expression_pipeline(
    ",{\"derive\":{\"value\":\"instr('aaaa','aa',-1,2)\"}}",
  )
  let expression = @lowering_relation.lower_expression(
    owner,
    1,
    0,
    expression_limits(),
  ).unwrap()
  assert_eq(
    expression_wire(expression),
    "{\"body\":[{\"body\":\"aaaa\",\"op\":\"literal\"},{\"body\":\"aa\",\"op\":\"literal\"},{\"body\":-1,\"op\":\"literal\"},{\"body\":2,\"op\":\"literal\"}],\"op\":\"instr\"}",
  )
}
