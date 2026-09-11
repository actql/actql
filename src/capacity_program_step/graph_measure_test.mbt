///|
fn graph_measure_pipeline(body : String) -> @pipeline.CheckedPipeline {
  @pipeline.check_carriers(cursor(body), [], None, None, {
    max_steps: 20,
    max_work: 100000,
    max_text_bytes: 100000,
    max_nodes: 100000,
    max_tokens: 100000,
    max_depth: 100,
  }).unwrap()
}

///|
fn measure_proof(
  index : Int,
  law : String,
  unit : String,
  value : Int64,
  input : @capacity_program_step.StepBound,
) -> @wire.ProgramProofClaim {
  proof(
    law,
    value,
    "{\"op\":\"source\"}",
    reference="checked-step:" + index.to_string(),
    unit~,
    inputs=[
      @wire.cid(
        @wire.program_proof_witness(@capacity_program_step.checked_proof(input)),
      ),
    ],
  )
}

///|
fn graph_seed(name : String, count : Int) -> String {
  "{\"values\":{\"schema\":{\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
  Array::makei(count, _ => "{\"src\":1,\"dst\":2}").join(",") +
  "]},\"as\":\"" +
  name +
  "\"}"
}

///|
test "Graph measures bind distinct units and actual node edge inputs through row bridges" {
  for n in [0, 1, 3] {
    for m in [0, 1, 3] {
      let p = graph_measure_pipeline(
        "[" +
        graph_seed("n", n) +
        "," +
        graph_seed("e", m) +
        ",{\"graph\":{\"nodes\":{\"from\":\"n\",\"id\":\"src\",\"fields\":[]},\"edges\":{\"from\":\"e\",\"source\":\"src\",\"target\":\"dst\",\"fields\":[]}},\"as\":\"g\"},{\"node_rows\":true},{\"from\":\"g\",\"edge_rows\":true},{\"take\":2}]",
      )
      let rows = [
        @capacity_program_step.check(
          p,
          0,
          proof("actql.bound.values", n.to_int64(), "{\"op\":\"source\"}"),
        ).unwrap(),
        @capacity_program_step.check(
          p,
          1,
          proof(
            "actql.bound.values",
            m.to_int64(),
            "{\"op\":\"source\"}",
            reference="checked-step:1",
          ),
        ).unwrap(),
      ]
      let graph = []
      let bridges = []
      for
        (i, unit, law, count, bridge, bridge_law) in [
          (
            0,
            "nodes",
            "actql.bound.graph-nodes",
            n.to_int64(),
            3,
            "actql.bound.graph-node-rows",
          ),
          (
            1,
            "edges",
            "actql.bound.graph-edges",
            m.to_int64(),
            4,
            "actql.bound.graph-edge-rows",
          ),
        ] {
        let claim = measure_proof(2, law, unit, count, rows[i])
        let app = @capacity_program_step.check_with_inputs(p, 2, claim, [
          rows[i],
        ]).unwrap()
        graph.push(app)
        assert_true(
          physical_equal(
            @capacity_program_step.input_at(app, 0).unwrap(),
            rows[i],
          ),
        )
        let bridge_claim = measure_proof(bridge, bridge_law, "rows", count, app)
        let exposed = @capacity_program_step.check_with_inputs(
          p,
          bridge,
          bridge_claim,
          [app],
        ).unwrap()
        bridges.push(exposed)
        assert_eq(
          @wire.unit(
            @wire.program_proof_witness(
              @capacity_program_step.checked_proof(exposed),
            ),
          ),
          @arithmetic.Rows,
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            2,
            measure_proof(2, law, unit, count, rows[1 - i]),
            [rows[1 - i]],
          )
          is Err(InputTargetMismatch(_)),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            2,
            measure_proof(2, law, unit, count + 1L, rows[i]),
            [rows[i]],
          )
          is Err(ValueMismatch),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            bridge,
            measure_proof(bridge, bridge_law, "rows", count, rows[i]),
            [rows[i]],
          )
          is Err(InputUnitMismatch(0)),
        )
      }
      for
        (index, law, wrong) in [
          (3, "actql.bound.graph-node-rows", graph[1]),
          (4, "actql.bound.graph-edge-rows", graph[0]),
        ] {
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            index,
            measure_proof(index, law, "rows", 0L, wrong),
            [wrong],
          )
          is Err(InputUnitMismatch(0)),
        )
      }
      let id = @wire.cid(
        @wire.program_proof_witness(
          @capacity_program_step.checked_proof(graph[1]),
        ),
      )
      let false_rows = proof(
        "actql.bound.take",
        0L,
        "{\"input\":\"" + id + "\",\"maximum\":2,\"op\":\"clamp\"}",
        reference="checked-step:5",
        inputs=[id],
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          5,
          false_rows,
          [graph[1]],
          max_input_work=10,
        )
        is Err(InputUnitMismatch(0)),
      )
      let bridge_id = @wire.cid(
        @wire.program_proof_witness(
          @capacity_program_step.checked_proof(bridges[1]),
        ),
      )
      let selected = if m < 2 { m.to_int64() } else { 2L }
      let take = proof(
        "actql.bound.take",
        selected,
        "{\"input\":\"" + bridge_id + "\",\"maximum\":2,\"op\":\"clamp\"}",
        reference="checked-step:5",
        inputs=[bridge_id],
      )
      let taken = @capacity_program_step.check_with_inputs(p, 5, take, [
        bridges[1],
      ]).unwrap()
      let all = [
        rows[0],
        rows[1],
        graph[0],
        graph[1],
        bridges[0],
        bridges[1],
        taken,
      ]
      let claims = program_claims(all.map(@capacity_program_step.checked_proof))
      let checked = @capacity_program_step.check_applications(
        claims,
        all,
        max_work=100,
      ).unwrap()
      assert_eq(@capacity_program_step.remaining_source_count(checked), 0)
    }
  }
}

///|
test "concise Graph node bounds include both endpoint occurrences" {
  for n in [0, 1, 3] {
    let p = graph_measure_pipeline(
      "[" +
      graph_seed("e", n) +
      ",{\"graph\":{\"source\":\"src\",\"target\":\"dst\"},\"as\":\"g\"}]",
    )
    let input = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.values", n.to_int64(), "{\"op\":\"source\"}"),
    ).unwrap()
    for
      (law, unit, count) in [
        ("actql.bound.graph-nodes", "nodes", n.to_int64() * 2L),
        ("actql.bound.graph-edges", "edges", n.to_int64()),
      ] {
      let app = @capacity_program_step.check_with_inputs(
        p,
        1,
        measure_proof(1, law, unit, count, input),
        [input],
      ).unwrap()
      assert_eq(
        @wire.value(
          @wire.program_proof_witness(@capacity_program_step.checked_proof(app)),
        ),
        count,
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          p,
          1,
          measure_proof(1, law, "rows", count, input),
          [input],
        )
        is Err(LawMismatch),
      )
      let op = if unit == "nodes" { "node_rows" } else { "edge_rows" }
      let bridge_law = if unit == "nodes" {
        "actql.bound.graph-node-rows"
      } else {
        "actql.bound.graph-edge-rows"
      }
      let receiver = @pipeline.check_with_evidence(
        cursor("[{\"" + op + "\":true}]"),
        [
          (
            "g",
            @pipeline.ProducedInput(
              @pipeline.produced_input(p, Step(1)).unwrap(),
            ),
          ),
        ],
        None,
        None,
        {
          max_steps: 1,
          max_work: 100000,
          max_text_bytes: 100000,
          max_nodes: 100000,
          max_tokens: 100000,
          max_depth: 100,
        },
      ).unwrap()
      let claim = measure_proof(0, bridge_law, "rows", count, app)
      let imported = @capacity_program_step.check_with_inputs(
        receiver,
        0,
        claim,
        [app],
        max_input_work=1,
      ).unwrap()
      assert_eq(@capacity_program_step.input_work(imported), 1)
      assert_true(
        physical_equal(
          @capacity_program_step.input_at(imported, 0).unwrap(),
          app,
        ),
      )
      assert_true(
        @capacity_program_step.check_with_inputs(
          receiver,
          0,
          claim,
          [app],
          max_input_work=0,
        )
        is Err(InputWorkLimit),
      )
    }
  }
}
