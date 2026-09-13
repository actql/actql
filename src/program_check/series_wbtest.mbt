///|
// Build input proof material from the source law, not from compiler output.
fn series_test_claim(count : Int) -> @wire.ProgramProofClaim {
  let proof = "{\"inputs\":[],\"law_id\":\"actql.bound.time-series\",\"semantic_ref\":\"checked-step:0\",\"unit\":\"rows\",\"value\":" +
    count.to_string() +
    ",\"version\":\"actql-bound-proof/0.1\"}"
  let proof_cid = "sha256:" + @sha.hex(@utf8.encode(proof))
  let body = "{\"dependencies\":[\"" +
    proof_cid +
    "\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.bound.time-series\",\"role\":\"proven_upper_bound\",\"source\":{\"kind\":\"program\",\"proof_cid\":\"" +
    proof_cid +
    "\",\"semantic_ref\":\"checked-step:0\"},\"unit\":\"rows\",\"value\":" +
    count.to_string() +
    ",\"version\":\"actql-bound-witness/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  let limits : @wire.Limits = {
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 30,
  }
  let witness = @wire.admit(
    @utf8.encode(
      body.unsafe_substring(start=0, end=body.length() - 1) +
      ",\"witness_cid\":\"" +
      cid +
      "\"}",
    ),
    cid,
    limits,
  ).unwrap()
  @wire.bind_program_proof(@utf8.encode(proof), witness, limits).unwrap()
}

///|
fn series_test_steps(end : String, parameter : Bool) -> String {
  "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"" +
  end +
  "\",\"step\":" +
  (if parameter { "{\"$param\":\"n\"}" } else { "3" }) +
  "},\"as\":\"grid\"},{\"select\":[{\"id\":\"time\"},{\"value\":\"time\"}],\"as\":\"selected\"}]"
}

///|
test "formal time series binds exact counts to Unit-owned publication proofs" {
  for
    (end, expected) in [
      ("2000-01-01T00:00:00.000Z", 0),
      ("2000-01-01T00:00:00.010Z", 4),
    ] {
    for parameter in [false, true] {
      let programs : Array[CheckedProgram] = []
      let _ = local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        tea=true,
        parameters=parameter,
        supplied=if parameter {
          Some(supplied_fixture("{\"n\":3}"))
        } else {
          None
        },
        second_steps=series_test_steps(end, parameter),
        second_result_from="selected",
        extra_step_budget=2,
        generated_proofs=[series_test_claim(expected)],
        generated_proof_stage=1,
      )
      let p = programs[0]
      let publication = unit_publication_at(p, 1, 0).unwrap()
      assert_eq(
        @context.publication_row_limit_maximum(publication.selection),
        expected.to_int64(),
      )
      assert_true(publication_proof_count(publication) > 0)
      for i in 0..<publication_proof_count(publication) {
        let proof = publication_proof_at(publication, i).unwrap()
        let source = proof_source(proof)
        assert_eq(
          source.unit_definition_cid,
          unit_definition_cid(p, 1).unwrap(),
        )
        assert_eq(source.source_ordinal, 0)
        assert_true(
          physical_equal(source.pipeline, unit_pipeline(p, 1).unwrap()),
        )
        assert_eq(
          @wire.value(@wire.program_proof_witness(proof_claim(proof))),
          expected.to_int64(),
        )
      }
      let out = @encode.writer(100000, 10000, 100)
      @wire.emit_limit(publication_rows(publication), out)
      let text = @encode.finish(out)
      assert_false(text.contains("checked-step:"))
      assert_true(
        text.contains(
          "unit:" + unit_definition_cid(p, 1).unwrap() + "#/steps/0",
        ),
      )
      assert_false(
        text.contains(
          "unit:" + unit_definition_cid(p, 0).unwrap() + "#/steps/0",
        ),
      )
      let closure = @context.stage_requirement_operations(requirements(p))
      let mut generators = 0
      for i in 0..<@context.operation_closure_count(closure) {
        guard @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(SeriesExecution(check))) else {
          continue
        }
        assert_true(
          physical_equal(check.site.pipeline, unit_pipeline(p, 1).unwrap()),
        )
        assert_true(check.step.input is None)
        assert_eq(check.row_count, expected.to_int64())
        if check.rule is GenerateTimeGrid {
          generators += 1
        }
      }
      assert_eq(generators, 1)
    }
  }
}

///|
test "formal time series rejects incorrect counts without a partial Program" {
  for count in [0, 3, 5] {
    let programs : Array[CheckedProgram] = []
    try
      local_construction_fixture(
        { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
        through_check=true,
        checked_results=programs,
        second_stage=true,
        tea=true,
        parameters=true,
        supplied=Some(supplied_fixture("{\"n\":3}")),
        second_steps=series_test_steps("2000-01-01T00:00:00.010Z", true),
        second_result_from="selected",
        extra_step_budget=2,
        generated_proofs=[series_test_claim(count)],
        generated_proof_stage=1,
      )
    catch {
      Source(
        SourceView(
          Context(
            Stages(
              Capacity(stage, visit, Program(Application(_, ValueMismatch)))
            )
          )
        )
      ) => {
        assert_eq(stage, 1)
        assert_eq(visit, 0)
      }
      error => raise error
    } noraise {
      _ => fail("incorrect exact count accepted")
    }
    assert_true(programs.is_empty())
  }
}

///|
test "formal time series validates bound steps even for empty ranges" {
  for end in ["2000-01-01T00:00:00.000Z", "2000-01-01T00:00:00.010Z"] {
    for value in ["0", "-1", "0.5", "9007199254740992"] {
      let programs : Array[CheckedProgram] = []
      try
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          through_check=true,
          checked_results=programs,
          second_stage=true,
          tea=true,
          parameters=true,
          supplied=Some(supplied_fixture("{\"n\":" + value + "}")),
          second_steps=series_test_steps(end, true),
          second_result_from="selected",
          extra_step_budget=2,
        )
      catch {
        Closure(
          Operations(
            Scalars(InvalidValue(_, @pipeline.Milliseconds("n", signed=false)))
          )
        ) => ()
        error => raise error
      } noraise {
        _ => fail("invalid bound step accepted")
      }
      assert_true(programs.is_empty())
    }
  }
}
