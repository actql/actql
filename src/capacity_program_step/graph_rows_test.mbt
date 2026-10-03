///|
test "keyed MATCH row laws bind original entity measures without discharging guards or predicates" {
  for n in [0, 1, 3] {
    for
      (body, law, input_unit, output_unit) in [
        (
          "{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}",
          "actql.bound.match-nodes", "nodes", "rows",
        ),
        (
          "{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"false\",\"fields\":[\"key\"]}}",
          "actql.bound.match-nodes", "nodes", "rows",
        ),
        (
          "{\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"edge_key\"},\"where\":\"false\",\"fields\":[\"edge_key\"]}}",
          "actql.bound.match-edges", "edges", "rows",
        ),
      ] {
      let p = graph_measure_pipeline(
        "[" +
        "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
        Array::makei(n, index => "{\"id\":" + index.to_string() + "}").join(",") +
        " ]},\"as\":\"n\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"n\",\"key\":[\"id\"]}],\"edges\":[{\"name\":\"E\",\"from\":\"n\",\"key\":[\"id\"],\"source\":{\"definition\":\"N\",\"key\":[\"id\"]},\"target\":{\"definition\":\"N\",\"key\":[\"id\"]}}]},\"as\":\"g\"}," +
        body +
        "]",
      )
      let count = n.to_int64()
      let seed = @capacity_program_step.check(
        p,
        0,
        proof("actql.bound.values", count, "{\"op\":\"source\"}"),
      ).unwrap()
      let input = @capacity_program_step.check_with_inputs(
        p,
        1,
        measure_proof(
          1,
          "actql.bound.property-graph-" + input_unit,
          input_unit,
          count,
          seed,
        ),
        [seed],
        max_operand_work=5,
      ).unwrap()
      // The constructor's single retained premise requires the existing five
      // bounded operand passes; the old unary tuple rule had no such passes.
      assert_eq(@capacity_program_step.operand_work(input), 5)
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          1,
          @capacity_program_step.checked_proof(input),
          [seed],
          max_operand_work=4,
        )
        is Err(OperandWorkLimit),
      )
      let output = @capacity_program_step.check_with_inputs(
        p,
        2,
        measure_proof(2, law, output_unit, count, input),
        [input],
      ).unwrap()
      assert_eq(
        @wire.value(
          @wire.program_proof_witness(
            @capacity_program_step.checked_proof(output),
          ),
        ),
        count,
      )
      assert_true(
        physical_equal(
          @capacity_program_step.input_at(output, 0).unwrap(),
          input,
        ),
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          measure_proof(2, law, output_unit, count + 1L, input),
          [input],
        )
        is Err(ValueMismatch),
      )
      let other_unit = if input_unit == "nodes" { "edges" } else { "nodes" }
      let other = @capacity_program_step.check_with_inputs(
        p,
        1,
        measure_proof(
          1,
          "actql.bound.property-graph-" + other_unit,
          other_unit,
          count,
          seed,
        ),
        [seed],
        max_operand_work=5,
      ).unwrap()
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          measure_proof(2, law, output_unit, count, other),
          [other],
        )
        is Err(InputUnitMismatch(0)),
      )
      // A different quantity law cannot substitute for the selected MATCH
      // bound, even with an equal witness value and the same retained owner.
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          measure_proof(
            2, "actql.bound.graph-node-rows", output_unit, count, input,
          ),
          [input],
        )
        is Err(LawMismatch),
      )
      let proofs = [seed, input, output].map(v => {
        @capacity_program_step.checked_proof(v)
      })
      assert_true(
        @capacity_program_step.check_applications(
          program_claims(proofs),
          [seed, input, output],
          max_work=100,
        )
        is Ok(_),
      )
    }
  }
}
