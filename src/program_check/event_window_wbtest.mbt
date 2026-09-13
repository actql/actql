///|
test "formal Event windows preserve membership limits and producer Units through projection" {
  for
    (kind, factor, drop_start) in [
      ("fixed", 1L, false),
      ("sliding", 4L, false),
      ("fixed", 1L, true),
      ("sliding", 4L, true),
    ] {
    let programs : Array[CheckedProgram] = []
    let _ = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      through_check=true,
      checked_results=programs,
      second_stage=true,
      tea=true,
      generated_rows=Some("[{\"id\":1}]"),
      generated_proofs=[keyed_sourceview_claim()],
      generated_proof_stage=0,
      producer_suffix=",{\"to_events\":{\"id\":\"id\",\"time\":\"value\"}},{\"window_events\":{\"kind\":\"" +
        kind +
        "\",\"size\":10,\"step\":3}},{\"events\":true,\"as\":\"windowed\"}" +
        (if drop_start {
          ",{\"drop\":[\"window_start_ms\"],\"as\":\"projected\"}"
        } else {
          ""
        }),
      producer_result_from=if drop_start { "projected" } else { "windowed" },
      extra_step_budget=4,
    )
    let p = programs[0]
    assert_eq(unit_window_limit_count(p, 0), Some(1))
    assert_eq(unit_window_limit_count(p, 1), Some(0))
    let limit = unit_window_limit_at(p, 0, 0).unwrap()
    let selection = window_limit_selection(limit)
    assert_eq(selection.maximum, factor)
    assert_eq(@policy.ceiling_field(selection.host), "max_temporal_output_rows")
    assert_eq(
      @wire.limit_subject(window_limit_claim(limit)),
      "unit:" + unit_definition_cid(p, 0).unwrap() + "#/steps/3",
    )
    assert_true(window_limit_proof_count(limit) > 0)
    for i in 0..<window_limit_proof_count(limit) {
      let proof = window_limit_proof_at(limit, i).unwrap()
      assert_eq(
        @wire.value(
          @wire.program_proof_witness(window_input_proof_claim(proof)),
        ),
        factor,
      )
      assert_eq(
        window_input_proof_source(proof).unit_definition_cid,
        unit_definition_cid(p, 0).unwrap(),
      )
    }
    let writer = @encode.writer(100000, 10000, 100)
    @wire.emit_limit(window_limit_claim(limit), writer)
    let text = @encode.finish(writer)
    assert_false(text.contains("checked-step:"))
    assert_true(text.contains("\"role\":\"proven_upper_bound\""))
    let pipeline = unit_pipeline(p, 0).unwrap()
    assert_true(@pipeline.window_evidence_at(pipeline, Step(4)) is Some(_))
    let keys = @pipeline.candidate_keys(pipeline, Step(4)).unwrap()
    assert_true(@evidence.key_witness_count(keys) > 0)
    for i in 0..<@evidence.key_witness_count(keys) {
      let key = @evidence.key_witness_at(keys, i).unwrap()
      assert_eq(
        @evidence.key_field_count(key),
        if kind == "fixed" {
          1
        } else {
          2
        },
      )
      if kind == "sliding" {
        assert_true(@evidence.key_window_producer(key) is Some(_))
        assert_true(@evidence.key_window_input(key) is Some(_))
        let fields = [
          @evidence.key_field_at(key, 0).unwrap().name,
          @evidence.key_field_at(key, 1).unwrap().name,
        ]
        assert_true(fields.contains(@schema.Unqualified("id")))
        assert_true(fields.contains(@schema.Unqualified("window_start_ms")))
      }
    }
    if drop_start {
      assert_true(@pipeline.window_evidence_at(pipeline, Step(5)) is None)
      assert_eq(
        @evidence.key_witness_count(
          @pipeline.candidate_keys(pipeline, Step(5)).unwrap(),
        ),
        if kind == "fixed" {
          @evidence.key_witness_count(keys)
        } else {
          0
        },
      )
      assert_true(@pipeline.logical_order(pipeline, Step(5)) is Some(_))
    }
    assert_eq(unit_publication_count(p, 0), Some(1))
    assert_eq(unit_publication_count(p, 1), Some(1))
  }
}
