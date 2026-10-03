///|
test "current Graph quantity bounds reject overflow and retain long repeated producer operands" {
  let definitions = Array::makei(33, index => {
    "{\"name\":\"N" +
    index.to_string() +
    "\",\"from\":\"rows\",\"key\":[\"id\"]}"
  }).join(",")
  for maximum in [1L, 9007199254740991L] {
    let pipeline = graph_measure_pipeline(
      "[" +
      keyed_measure_seed("seed", 1) +
      ",{\"take\":" +
      maximum.to_string() +
      ",\"as\":\"rows\"}" +
      ",{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[" +
      definitions +
      "],\"edges\":[]},\"as\":\"g\"}]",
    )
    let selected = @capacity_program_step.check(
      pipeline,
      1,
      proof(
        "actql.bound.take",
        maximum,
        "{\"maximum\":" + maximum.to_string() + ",\"op\":\"clamp\"}",
        reference="checked-step:1",
      ),
    ).unwrap()
    let operands = Array::make(33, selected)
    let ids = operands.map(operand => {
      @wire.cid(
        @wire.program_proof_witness(
          @capacity_program_step.checked_proof(operand),
        ),
      )
    })
    let claim = proof(
      "actql.bound.property-graph-nodes",
      if maximum == 1L {
        33L
      } else {
        0L
      },
      "{\"op\":\"source\"}",
      reference="checked-step:2",
      unit="nodes",
      inputs=ids,
    )
    let result = @capacity_program_step.check_with_inputs(
      pipeline,
      2,
      claim,
      operands,
      max_operand_work=165,
    )
    if maximum == 1L {
      let admitted = result.unwrap()
      assert_eq(@capacity_program_step.input_count(admitted), 33)
      assert_eq(@capacity_program_step.operand_work(admitted), 165)
      assert_true(
        @capacity_program_step.check_with_inputs(
          pipeline,
          2,
          claim,
          operands,
          max_operand_work=164,
        )
        is Err(OperandWorkLimit),
      )
      for index in 0..<33 {
        assert_true(
          physical_equal(
            @capacity_program_step.input_at(admitted, index).unwrap(),
            selected,
          ),
        )
      }
    } else {
      // Overflow must not turn into a normal zero-valued or saturated proof.
      assert_true(result is Err(BoundOverflow))
    }
  }
}
