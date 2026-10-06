///|
fn property_measure_pipeline(
  edges : Int,
  mixed? : Bool = false,
) -> @pipeline.CheckedPipeline {
  let edge_definitions = if edges == 0 {
    ""
  } else {
    (
      #|{"name":"E","from":"edge_rows","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}},{"name":"F","from":"edge_rows","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}
    )
  }
  let body = (
      #|[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"node_rows"},{"values":{"schema":{"id":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false}},"rows":[{"id":10,"src":1,"dst":1},{"id":11,"src":1,"dst":1}]},"as":"edge_rows"},{"graph":{"version":"actql-graph-constructor/0.1","nodes":[{"name":"N","from":"node_rows","key":["id"]},{"name":"M","from":"node_rows","key":["id"]}],"edges":[
    ) +
    edge_definitions +
    "]},\"as\":\"g\"}]"
  let body = if mixed {
    body.replace(
      old="{\"name\":\"M\",\"from\":\"node_rows\",\"key\":[\"id\"]}",
      new="{\"name\":\"M\",\"from\":\"edge_rows\",\"key\":[\"id\"]},{\"name\":\"K\",\"from\":\"node_rows\",\"key\":[\"id\"]}",
    )
  } else {
    body
  }
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
test "Graph proof reference sorting does not reorder mixed definition premises" {
  let pipeline = property_measure_pipeline(2, mixed=true)
  let first = @capacity_program_step.derive_bound(
      pipeline,
      0,
      [],
      derive_limits(),
    ).unwrap().bound
  let second = @capacity_program_step.derive_bound(
      pipeline,
      1,
      [],
      derive_limits(),
    ).unwrap().bound
  let inputs = [
    @capacity_program_step.StepInput(first),
    StepInput(second),
    StepInput(first),
  ]
  let application = @capacity_program_step.derive_bound(
      pipeline,
      2,
      inputs,
      derive_limits(),
      unit=@arithmetic.Nodes,
    ).unwrap().bound
  let claim = @capacity_program_step.checked_proof(application)
  assert_eq(@wire.value(@wire.program_proof_witness(claim)), 4L)
  assert_eq(@wire.program_proof_input_count(claim), 3)
  ignore(
    @capacity_program_step.check_with_sources(
      pipeline,
      2,
      claim,
      inputs,
      max_input_work=100,
      max_operand_work=100,
    ).unwrap(),
  )
  assert_true(
    @capacity_program_step.check_with_sources(
      pipeline,
      2,
      claim,
      [StepInput(second), StepInput(first), StepInput(first)],
      max_input_work=100,
      max_operand_work=100,
    )
    is Err(InputTargetMismatch(0)),
  )
}

///|
test "Graph quantity proofs retain repeated definition operands and distinguish node and edge roles" {
  for edges in [0, 2] {
    let pipeline = property_measure_pipeline(edges)
    let rows = [
      @capacity_program_step.derive_bound(pipeline, 0, [], derive_limits()).unwrap().bound,
      @capacity_program_step.derive_bound(pipeline, 1, [], derive_limits()).unwrap().bound,
    ]
    for
      (unit, start, count, expected, law) in [
        (@arithmetic.Nodes, 0, 2, 2L, "actql.bound.graph-construction-nodes"),
        (
          @arithmetic.Edges,
          2,
          edges,
          if edges == 0 {
            0L
          } else {
            4L
          },
          "actql.bound.graph-construction-edges",
        ),
      ] {
      let request = @capacity_program_step.prepare_bound_derivation(
        pipeline,
        2,
        unit~,
      ).unwrap()
      assert_eq(request.input_count, count)
      for i in 0..<count {
        let operand = @capacity_program_step.bound_derivation_input_at(
          request, count, i,
        ).unwrap()
        assert_eq(operand.edge, start + i)
        assert_eq(operand.unit, @arithmetic.Rows)
        assert_eq(
          operand.target,
          @pipeline.Step(if start == 0 { 0 } else { 1 }),
        )
      }
      let inputs = Array::make(
        count,
        @capacity_program_step.StepInput(rows[if start == 0 { 0 } else { 1 }]),
      )
      let application = @capacity_program_step.derive_bound(
          pipeline,
          2,
          inputs,
          derive_limits(),
          unit~,
        ).unwrap().bound
      let claim = @capacity_program_step.checked_proof(application)
      let witness = @wire.program_proof_witness(claim)
      assert_eq(@law.name(@wire.law(witness)), law)
      assert_eq(@wire.value(witness), expected)
      assert_eq(@wire.program_proof_input_count(claim), count)
      ignore(
        @capacity_program_step.check_with_sources(
          pipeline,
          2,
          claim,
          inputs,
          max_input_work=100,
          max_operand_work=100,
        ).unwrap(),
      )
      let ids = Array::make(
        count,
        @wire.cid(
          @wire.program_proof_witness(
            @capacity_program_step.checked_proof(
              rows[if start == 0 { 0 } else { 1 }],
            ),
          ),
        ),
      )
      let wrong_law = proof(
        if unit == @arithmetic.Nodes {
          "actql.bound.graph-nodes"
        } else {
          "actql.bound.graph-edges"
        },
        expected,
        "{\"op\":\"source\"}",
        reference="checked-step:2",
        unit=if unit == @arithmetic.Nodes { "nodes" } else { "edges" },
        inputs=ids,
      )
      assert_true(
        @capacity_program_step.check_with_sources(
          pipeline,
          2,
          wrong_law,
          inputs,
          max_input_work=100,
          max_operand_work=100,
        )
        is Err(LawMismatch),
      )
      let wrong_value = proof(
        law,
        expected + 1L,
        "{\"op\":\"source\"}",
        reference="checked-step:2",
        unit=if unit == @arithmetic.Nodes { "nodes" } else { "edges" },
        inputs=ids,
      )
      assert_true(
        @capacity_program_step.check_with_sources(
          pipeline,
          2,
          wrong_value,
          inputs,
          max_input_work=100,
          max_operand_work=100,
        )
        is Err(ValueMismatch),
      )
      if count > 0 {
        let wrong = Array::make(
          count,
          @capacity_program_step.StepInput(rows[if start == 0 { 1 } else { 0 }]),
        )
        assert_true(
          @capacity_program_step.derive_bound(
            pipeline,
            2,
            wrong,
            derive_limits(),
            unit~,
          )
          is Err(Application(InputTargetMismatch(0))),
        )
        let foreign = property_measure_pipeline(edges)
        assert_true(
          @capacity_program_step.derive_bound(
            foreign,
            2,
            inputs,
            derive_limits(),
            unit~,
          )
          is Err(Application(InputOwnerMismatch(0))),
        )
        assert_true(
          @capacity_program_step.derive_bound(
            pipeline,
            2,
            inputs,
            derive_limits(),
            unit~,
            max_work=0,
          )
          is Err(_),
        )
      }
    }
  }
}
