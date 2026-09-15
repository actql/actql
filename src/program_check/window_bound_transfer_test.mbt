///|
fn assert_transfer_work_boundary(
  parsed : @syntax.Program,
  environment : @program_check.CheckEnvironment,
  evidence : Array[@context.StageCapacityInput],
  limits : @program_check.CheckLimits,
) -> Unit raise {
  // This checks atomic budget admission, not an independent expected work count.
  let mut low = 0
  let mut high = limits.compilation.work
  while high - low > 1 {
    let middle = low + (high - low) / 2
    match
      @program_check.check_parsed_with_evidence(
        parsed,
        environment,
        None,
        evidence,
        { ..limits, compilation: { ..limits.compilation, work: middle, }, },
      ) {
      Checked(_) => high = middle
      Rejected(_) => low = middle
      NeedsInputs(_) => fail("compile budget became an external requirement")
    }
  }
  assert_true(
    @program_check.check_parsed_with_evidence(
      parsed,
      environment,
      None,
      evidence,
      { ..limits, compilation: { ..limits.compilation, work: high, }, },
    )
    is Checked(_),
  )
  assert_true(
    @program_check.check_parsed_with_evidence(
      parsed,
      environment,
      None,
      evidence,
      { ..limits, compilation: { ..limits.compilation, work: high - 1, }, },
    )
    is Rejected(_),
  )
}

///|
test "window bound reuse requires an applicable transfer through the checked operation" {
  for imported in [true, false] {
    for
      (kind, step, factor, parameterized) in [
        ("sliding", 10, 1L, false),
        ("sliding", 20, 1L, false),
        ("sliding", 5, 2L, false),
        ("sliding", 3, 4L, false),
        ("fixed", 10, 1L, false),
        ("sliding", 10, 1L, true),
        ("sliding", 20, 1L, true),
        ("sliding", 3, 4L, true),
      ] {
      let (text, _, environment, _, limits) = public_input_fixture(
        generated=true,
      )
      let local_seed = if imported {
        ""
      } else {
        "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"value\":2}]},\"as\":\"local_seed\"},"
      }
      let source = text.replace(
        old="{\"take\":1,\"as\":\"selected\"}",
        new=local_seed +
          "{\"row_window\":{\"time\":\"id\",\"kind\":\"" +
          kind +
          "\",\"size\":10,\"step\":" +
          step.to_string() +
          "},\"as\":\"windowed\"},{\"append\":{\"with\":\"windowed\"}},{\"distinct\":true,\"as\":\"selected\"}",
      )
      let limits = {
        ..limits,
        compilation: {
          ..limits.compilation,
          structure: {
            ..limits.compilation.structure,
            steps: 12,
            parameters: 3,
          },
        },
      }
      let source = if parameterized {
        source
        .replace(
          old="\"params\":{",
          new="\"params\":{\"window_size\":{\"type\":\"number\",\"nullable\":false,\"default\":10},\"window_step\":{\"type\":\"number\",\"nullable\":false},",
        )
        .replace(
          old="\"size\":10,\"step\":" + step.to_string(),
          new="\"size\":{\"$param\":\"window_size\"},\"step\":{\"$param\":\"window_step\"}",
        )
      } else {
        source
      }
      let supplied = if parameterized {
        Some(
          @decode.admit(
            @source.parse_json("{\"window_step\":" + step.to_string() + "}", {
              max_input_bytes: 100,
              max_nodes: 10,
              max_depth: 10,
            }).unwrap(),
            {
              max_nodes: 10,
              max_depth: 10,
              max_string_bytes: 100,
              max_total_string_bytes: 100,
            },
          ).unwrap(),
        )
      } else {
        None
      }
      let parsed = @syntax.parse(source, limits.input, format=Json).unwrap()
      let outcome = @program_check.check_parsed(
        parsed, environment, supplied, limits,
      )
      let checked = public_checked(outcome)
      let publication = @program_check.unit_publication_at(checked, 1, 0).unwrap()
      assert_eq(
        @context.publication_row_limit_maximum(
          @program_check.publication_selection(publication),
        ),
        2L * factor,
      )
      let root = @program_check.publication_proof_at(publication, 0).unwrap()
      assert_eq(@program_check.proof_input_count(root), 2)
      let left = @program_check.proof_input_at(root, 0).unwrap()
      assert_true(
        physical_equal(left, @program_check.proof_input_at(root, 1).unwrap()),
      )
      if kind == "sliding" {
        assert_eq(
          @program_check.proof_source(left).unit_definition_cid,
          @program_check.unit_definition_cid(checked, 1).unwrap(),
        )
        assert_eq(
          @program_check.proof_source(left).source_ordinal,
          if imported {
            0
          } else {
            1
          },
        )
      }
      let other = public_checked(
        @program_check.check_document(
          source,
          environment,
          supplied,
          limits,
          format=Json,
        ),
      )
      for unit in 0..<2 {
        assert_eq(
          @program_check.unit_definition_cid(checked, unit),
          @program_check.unit_definition_cid(other, unit),
        )
      }
      assert_true(
        @step_bounds.check_target_rows(
          @program_check.unit_pipeline(other, 1).unwrap(),
          Step(if imported { 1 } else { 2 }),
          @program_check.proof_application(root),
          10000,
        )
        is Err(_),
      )
      assert_true(
        @program_check.check_parsed(parsed, environment, supplied, {
          ..limits,
          compilation: { ..limits.compilation, work: 0, },
        })
        is Rejected(_),
      )
      if imported && kind == "sliding" && step == 10 && !parameterized {
        assert_transfer_work_boundary(parsed, environment, [], limits)
      }
    }
  }
}
