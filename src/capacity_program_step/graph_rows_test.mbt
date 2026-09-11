///|
test "Graph row laws bind original entity measures without discharging guards or predicates" {
  for n in [0, 1, 3] {
    for
      (body, law, input_unit, output_unit) in [
        (
          "{\"degree\":{\"direction\":\"both\"}}", "actql.bound.graph-degree", "nodes",
          "rows",
        ),
        (
          "{\"components\":{\"kind\":\"weak\",\"max_output_rows\":1}}", "actql.bound.components-nodes",
          "nodes", "rows",
        ),
        (
          "{\"components\":{\"kind\":\"strong\"}}", "actql.bound.components-input-nodes",
          "nodes", "nodes",
        ),
        (
          "{\"match_nodes\":{\"where\":\"true\",\"fields\":[\"src\"]}}", "actql.bound.match-nodes",
          "nodes", "rows",
        ),
        (
          "{\"match_nodes\":{\"ids\":[1,1],\"fields\":[\"src\"]}}", "actql.bound.match-nodes",
          "nodes", "rows",
        ),
        (
          "{\"match_edges\":{\"where\":\"false\",\"fields\":[\"src\",\"dst\"]}}",
          "actql.bound.match-edges", "edges", "rows",
        ),
      ] {
      let p = graph_measure_pipeline(
        "[" +
        graph_seed("n", n) +
        ",{\"graph\":{\"nodes\":{\"from\":\"n\",\"id\":\"src\",\"fields\":[]},\"edges\":{\"from\":\"n\",\"source\":\"src\",\"target\":\"dst\",\"fields\":[]}},\"as\":\"g\"}," +
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
          "actql.bound.graph-" + input_unit,
          input_unit,
          count,
          seed,
        ),
        [seed],
      ).unwrap()
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
          "actql.bound.graph-" + other_unit,
          other_unit,
          count,
          seed,
        ),
        [seed],
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
      // Graph components' enforced output limit is a separate application.
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          measure_proof(
            2, "actql.bound.components-output", output_unit, count, input,
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
