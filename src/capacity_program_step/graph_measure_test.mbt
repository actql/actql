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
fn keyed_measure_seed(name : String, count : Int) -> String {
  "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
  Array::makei(count, index => {
    "{\"id\":" + index.to_string() + ",\"src\":0,\"dst\":0}"
  }).join(",") +
  "]},\"as\":\"" +
  name +
  "\"}"
}

///|
fn keyed_measure_constructor(nodes : String, edges : String) -> String {
  "{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"" +
  nodes +
  "\",\"key\":[\"id\"]}],\"edges\":[{\"name\":\"E\",\"from\":\"" +
  edges +
  "\",\"key\":[\"id\"],\"source\":{\"definition\":\"N\",\"key\":[\"src\"]},\"target\":{\"definition\":\"N\",\"key\":[\"dst\"]}}]},\"as\":\"g\"}"
}

///|
fn keyed_measure_match(unit : String) -> String {
  if unit == "nodes" {
    "{\"match_nodes\":{\"definition\":\"N\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}"
  } else {
    "{\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}}"
  }
}

///|
fn keyed_repeated_measure_pipeline() -> @pipeline.CheckedPipeline {
  graph_measure_pipeline(keyed_repeated_measure_steps())
}

///|
fn keyed_repeated_measure_steps() -> String {
  let node = "{\"name\":\"N\",\"from\":\"seed\",\"key\":[\"id\"]}"
  let edges = ["E", "F", "G"].map(name => {
    "{\"name\":\"" +
    name +
    "\",\"from\":\"seed\",\"key\":[\"id\"],\"source\":{\"definition\":\"N\",\"key\":[\"src\"]},\"target\":{\"definition\":\"N\",\"key\":[\"dst\"]}}"
  })
  "[" +
  keyed_measure_seed("seed", 1) +
  ",{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[" +
  node +
  "],\"edges\":[" +
  edges.join(",") +
  "]},\"as\":\"g\"}]"
}

///|
test "keyed Graph measures bind distinct units and original inputs through MATCH" {
  for n in [0, 1, 3] {
    for m in [0, 1, 3] {
      let p = graph_measure_pipeline(
        "[" +
        keyed_measure_seed("n", n) +
        "," +
        keyed_measure_seed("e", m) +
        "," +
        keyed_measure_constructor("n", "e") +
        "," +
        keyed_measure_match("nodes") +
        ",{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"key\"},\"where\":\"true\",\"fields\":[\"key\"]}},{\"take\":2}]",
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
      // These are conservative entity upper bounds from the original rows,
      // not observed counts. With no declared nodes, endpoint exclusion can
      // reduce actual edges to zero without invalidating the input-row bound.
      for
        (i, unit, law, count, bridge, bridge_law) in [
          (
            0,
            "nodes",
            "actql.bound.property-graph-nodes",
            n.to_int64(),
            3,
            "actql.bound.match-nodes",
          ),
          (
            1,
            "edges",
            "actql.bound.property-graph-edges",
            m.to_int64(),
            4,
            "actql.bound.match-edges",
          ),
        ] {
        let claim = measure_proof(2, law, unit, count, rows[i])
        let app = @capacity_program_step.check_with_inputs(
          p,
          2,
          claim,
          [rows[i]],
          max_operand_work=5,
        ).unwrap()
        assert_eq(@capacity_program_step.operand_work(app), 5)
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            2,
            claim,
            [rows[i]],
            max_operand_work=4,
          )
          is Err(OperandWorkLimit),
        )
        graph.push(app)
        assert_eq(
          @capacity_program_step.check_target_rows(
            p,
            @pipeline.Step(2),
            app,
            100,
          ).unwrap_err(),
          @capacity_program_step.WrongUnit,
        )
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
            max_operand_work=5,
          )
          is Err(InputTargetMismatch(_)),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            2,
            measure_proof(2, law, unit, count + 1L, rows[i]),
            [rows[i]],
            max_operand_work=5,
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
          (3, "actql.bound.match-nodes", graph[1]),
          (4, "actql.bound.match-edges", graph[0]),
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
test "imported keyed Graph measures retain their owner and exact input work" {
  // The retired concise constructor's 2 * endpoint-occurrence formula is not
  // a current guarantee. Explicit node keys instead have one row premise.
  for n in [0, 1, 3] {
    let p = graph_measure_pipeline(
      "[" +
      keyed_measure_seed("seed", n) +
      "," +
      keyed_measure_constructor("seed", "seed") +
      "]",
    )
    let input = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.values", n.to_int64(), "{\"op\":\"source\"}"),
    ).unwrap()
    for
      (law, unit, count) in [
        ("actql.bound.property-graph-nodes", "nodes", n.to_int64()),
        ("actql.bound.property-graph-edges", "edges", n.to_int64()),
      ] {
      let app = @capacity_program_step.check_with_inputs(
        p,
        1,
        measure_proof(1, law, unit, count, input),
        [input],
        max_operand_work=5,
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
          max_operand_work=5,
        )
        is Err(LawMismatch),
      )
      let bridge_law = if unit == "nodes" {
        "actql.bound.match-nodes"
      } else {
        "actql.bound.match-edges"
      }
      let receiver = @pipeline.check_with_evidence(
        cursor("[" + keyed_measure_match(unit) + "]"),
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
