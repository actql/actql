///|
test "Graph capacity additions reject overflow without saturating and retain long repetitions" {
  let refs = Array::make(32, "\"g\"").join(",")
  for maximum in [1L, 9007199254740991L] {
    let p = graph_measure_pipeline(
      "[" +
      graph_seed("seed", 1) +
      ",{\"take\":" +
      maximum.to_string() +
      "},{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"},{\"union_graphs\":{\"with\":[" +
      refs +
      "]}}]",
    )
    let selected = @capacity_program_step.check(
      p,
      1,
      proof(
        "actql.bound.take",
        maximum,
        "{\"maximum\":" + maximum.to_string() + ",\"op\":\"clamp\"}",
        reference="checked-step:1",
      ),
    ).unwrap()
    let edges = @capacity_program_step.check_with_inputs(
      p,
      2,
      measure_proof(2, "actql.bound.graph-edges", "edges", maximum, selected),
      [selected],
    ).unwrap()
    let operands = Array::make(33, edges)
    let ids = operands.map(v => {
      @wire.cid(
        @wire.program_proof_witness(@capacity_program_step.checked_proof(v)),
      )
    })
    let count = if maximum == 1L { 33L } else { 0L }
    let claim = proof(
      "actql.bound.graph-edges",
      count,
      "{\"op\":\"source\"}",
      reference="checked-step:3",
      unit="edges",
      inputs=ids,
    )
    let result = @capacity_program_step.check_with_inputs(
      p,
      3,
      claim,
      operands,
      max_operand_work=165,
    )
    if maximum == 1L {
      let app = result.unwrap()
      assert_eq(@capacity_program_step.input_count(app), 33)
      assert_eq(@capacity_program_step.operand_work(app), 165)
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          3,
          claim,
          operands,
          max_operand_work=164,
        )
        is Err(OperandWorkLimit),
      )
    } else {
      assert_true(result is Err(BoundOverflow))
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          2,
          measure_proof(2, "actql.bound.graph-nodes", "nodes", 0L, selected),
          [selected],
        )
        is Err(BoundOverflow),
      )
    }
  }
}

///|
test "structural Graph applications retain directional and repeated measure dependencies" {
  for n in [0, 1, 3] {
    for m in [0, 1, 3] {
      for
        (operation, refs, repeated, subtract) in [
          ("union_graphs", "\"r\"", false, false),
          ("graft_graph", "\"r\"", false, false),
          ("subtract_graphs", "\"r\"", false, true),
          ("union_graphs", "[\"r\",\"l\",\"r\"]", true, false),
        ] {
        let p = graph_measure_pipeline(
          "[" +
          graph_seed("a", n) +
          ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"l\"}," +
          graph_seed("b", m) +
          ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"r\"},{\"from\":\"l\",\"" +
          operation +
          "\":{\"with\":" +
          refs +
          "},\"as\":\"combined\"},{\"node_rows\":true},{\"from\":\"combined\",\"edge_rows\":true}]",
        )
        let a = @capacity_program_step.check(
          p,
          0,
          proof("actql.bound.values", n.to_int64(), "{\"op\":\"source\"}"),
        ).unwrap()
        let b = @capacity_program_step.check(
          p,
          2,
          proof(
            "actql.bound.values",
            m.to_int64(),
            "{\"op\":\"source\"}",
            reference="checked-step:2",
          ),
        ).unwrap()
        for
          (unit, law, factor, bridge, bridge_law) in [
            (
              "nodes", "actql.bound.graph-nodes", 2L, 5, "actql.bound.graph-node-rows",
            ),
            (
              "edges", "actql.bound.graph-edges", 1L, 6, "actql.bound.graph-edge-rows",
            ),
          ] {
          let left = @capacity_program_step.check_with_inputs(
            p,
            1,
            measure_proof(1, law, unit, n.to_int64() * factor, a),
            [a],
          ).unwrap()
          let right = @capacity_program_step.check_with_inputs(
            p,
            3,
            measure_proof(3, law, unit, m.to_int64() * factor, b),
            [b],
          ).unwrap()
          let operands = if subtract {
            [left]
          } else if repeated {
            [left, right, left, right]
          } else {
            [left, right]
          }
          let ids = operands.map(v => {
            @wire.cid(
              @wire.program_proof_witness(
                @capacity_program_step.checked_proof(v),
              ),
            )
          })
          let expected = (if subtract {
              n.to_int64()
            } else {
              (n + m).to_int64() * (if repeated { 2L } else { 1L })
            }) *
            factor
          let claim = proof(
            law,
            expected,
            "{\"op\":\"source\"}",
            reference="checked-step:4",
            unit~,
            inputs=ids,
          )
          let work = operands.length() * 5
          let app = @capacity_program_step.check_with_inputs(
            p,
            4,
            claim,
            operands,
            max_operand_work=work,
          ).unwrap()
          assert_eq(@capacity_program_step.operand_work(app), work)
          for i in 0..<operands.length() {
            assert_true(
              physical_equal(
                @capacity_program_step.input_at(app, i).unwrap(),
                operands[i],
              ),
            )
          }
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              4,
              claim,
              operands,
              max_operand_work=work - 1,
            )
            is Err(OperandWorkLimit),
          )
          let wrong = operands.copy()
          wrong[0] = right
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              4,
              claim,
              wrong,
              max_operand_work=work,
            )
            is Err(InputTargetMismatch(0)),
          )
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              4,
              proof(
                law,
                expected + 1L,
                "{\"op\":\"source\"}",
                reference="checked-step:4",
                unit~,
                inputs=ids,
              ),
              operands,
              max_operand_work=work,
            )
            is Err(ValueMismatch),
          )
          let rows = @capacity_program_step.check_with_inputs(
            p,
            bridge,
            measure_proof(bridge, bridge_law, "rows", expected, app),
            [app],
          ).unwrap()
          let all = [a, b, left, right, app, rows]
          let claims = program_claims(
            all.map(@capacity_program_step.checked_proof),
          )
          assert_eq(
            @capacity_program_step.remaining_source_count(
              @capacity_program_step.check_applications(
                claims,
                all,
                max_work=100,
              ).unwrap(),
            ),
            0,
          )
          operands.clear()
          assert_eq(
            @capacity_program_step.input_count(app),
            if subtract {
              1
            } else if repeated {
              4
            } else {
              2
            },
          )
        }
      }
    }
  }
}
