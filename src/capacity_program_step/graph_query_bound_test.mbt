///|
fn query_fixture(
  body : String,
  n : Int,
  s : Int,
  t : Int,
) -> (@pipeline.CheckedPipeline, Array[@capacity_program_step.StepBound]) {
  let p = graph_measure_pipeline(
    "[" +
    graph_seed("n", n) +
    ",{\"graph\":{\"nodes\":{\"from\":\"n\",\"id\":\"src\",\"fields\":[]},\"edges\":{\"from\":\"n\",\"source\":\"src\",\"target\":\"dst\",\"fields\":[]}},\"as\":\"g\"}," +
    graph_seed("s", s) +
    "," +
    graph_seed("t", t) +
    "," +
    body +
    "]",
  )
  let seed = @capacity_program_step.check(
    p,
    0,
    proof("actql.bound.values", n.to_int64(), "{\"op\":\"source\"}"),
  ).unwrap()
  let graph = @capacity_program_step.check_with_inputs(
    p,
    1,
    measure_proof(1, "actql.bound.graph-nodes", "nodes", n.to_int64(), seed),
    [seed],
  ).unwrap()
  let starts = @capacity_program_step.check(
    p,
    2,
    proof(
      "actql.bound.values",
      s.to_int64(),
      "{\"op\":\"source\"}",
      reference="checked-step:2",
    ),
  ).unwrap()
  let targets = @capacity_program_step.check(
    p,
    3,
    proof(
      "actql.bound.values",
      t.to_int64(),
      "{\"op\":\"source\"}",
      reference="checked-step:3",
    ),
  ).unwrap()
  (p, [seed, graph, starts, targets])
}

///|
fn query_proof(
  law : String,
  value : Int64,
  apps : Array[@capacity_program_step.StepBound],
) -> @wire.ProgramProofClaim {
  proof(
    law,
    value,
    "{\"op\":\"source\"}",
    reference="checked-step:4",
    inputs=apps.map(app => {
      @wire.cid(
        @wire.program_proof_witness(@capacity_program_step.checked_proof(app)),
      )
    }),
  )
}

///|
test "traversal node proofs use actual selector and Graph measures, not path counts" {
  for n in [0, 2, 3] {
    for
      (selector, kind, starts) in [
        ("{\"ids\":[1,1]}", 0, 2),
        ("{\"where\":\"true\"}", 1, n),
        ("{\"from\":\"s\",\"id\":\"src\"}", 2, 2),
      ] {
      for emission in ["nodes", "paths"] {
        let body = "{\"from\":\"g\",\"traverse\":{\"start\":" +
          selector +
          ",\"direction\":\"out\",\"min_hops\":0,\"max_hops\":3,\"emit\":\"" +
          emission +
          "\"}}"
        let (p, all) = query_fixture(body, n, 2, 2)
        let inputs = if kind == 2 { [all[1], all[2]] } else { [all[1]] }
        let expected = (n * (if starts < n { starts } else { n })).to_int64()
        let proof = query_proof("actql.bound.traverse-nodes", expected, inputs)
        let result = @capacity_program_step.check_with_inputs(
          p, 4, proof, inputs,
        )
        if emission == "paths" {
          assert_true(result is Err(UnsupportedOperation))
          continue
        }
        let app = result.unwrap()
        assert_true(
          physical_equal(
            @capacity_program_step.input_at(app, 0).unwrap(),
            all[1],
          ),
        )
        assert_true(
          @capacity_program_step.check_with_inputs(
            p,
            4,
            query_proof("actql.bound.traverse-nodes", expected + 1L, inputs),
            inputs,
          )
          is Err(ValueMismatch),
        )
        if kind == 2 {
          let swapped = [all[1], all[3]]
          assert_true(
            @capacity_program_step.check_with_inputs(
              p,
              4,
              query_proof("actql.bound.traverse-nodes", expected, swapped),
              swapped,
            )
            is Err(InputTargetMismatch(1)),
          )
        }
        let proofs = all.map(a => @capacity_program_step.checked_proof(a))
        proofs.push(@capacity_program_step.checked_proof(app))
        let registered = all.copy()
        registered.push(app)
        assert_true(
          @capacity_program_step.check_applications(
            program_claims(proofs),
            registered,
            max_work=100,
          )
          is Ok(_),
        )
      }
    }
  }
}
