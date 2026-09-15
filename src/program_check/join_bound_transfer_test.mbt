///|
test "join composition falls back to admitted non-expanding input transfer" {
  for imported in [false, true] {
    for kind in ["semi", "anti", "cross_join", "inner", "cross_unbounded"] {
      let can_forward = kind != "inner" && kind != "cross_unbounded"
      let (text, _, environment, evidence, limits) = public_input_fixture(
        temporal_join_step=Some(1),
      )
      let text = if imported {
        text
        .replace(
          old="\"as\":\"derived\"}]",
          new="\"as\":\"derived\"},{\"take\":1,\"as\":\"bounded\"}]",
        )
        .replace(old="\"from\":\"derived\"", new="\"from\":\"bounded\"")
        .replace(
          old="\"inputs\":{\"rows\":{\"result\":",
          new="\"inputs\":{\"unbounded\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}}},\"rows\":{\"result\":",
        )
      } else {
        text
      }
      let right = if imported { "unbounded" } else { "rows" }
      let join = if kind == "cross_join" || kind == "cross_unbounded" {
        "\"cross_join\":{\"with\":\"" +
        right +
        "\"" +
        (if kind == "cross_join" { ",\"right_rows\":\"one\"" } else { "" }) +
        ",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}}"
      } else {
        "\"join\":{\"with\":\"" +
        right +
        "\",\"kind\":\"" +
        kind +
        "\",\"on\":\"id\",\"select\":{\"id\":\"left.id\",\"value\":\"left.value\"}}"
      }
      let source = text.replace(
        old="{\"take\":1,\"as\":\"selected\"}",
        new=(if imported {
            "{\"from\":\"rows\",\"select\":[\"id\",\"value\"],\"as\":\"left_rows\"},"
          } else {
            "{\"take\":1,\"as\":\"left_rows\"},"
          }) +
          "{" +
          join +
          "},{\"append\":{\"with\":\"left_rows\"}},{\"distinct\":true,\"as\":\"selected\"}",
      )
      let limits = {
        ..limits,
        compilation: {
          ..limits.compilation,
          structure: { ..limits.compilation.structure, steps: 12, },
        },
      }
      let parsed = @syntax.parse(source, limits.input, format=Json).unwrap()
      let outcome = @program_check.check_parsed_with_evidence(
        parsed,
        environment,
        None,
        evidence,
        limits,
      )
      let checked = public_checked(outcome)
      let publication = @program_check.unit_publication_at(checked, 1, 0).unwrap()
      assert_eq(
        @context.publication_row_limit_maximum(
          @program_check.publication_selection(publication),
        ),
        if can_forward {
          2L
        } else {
          1000L
        },
      )
      if can_forward {
        let root = @program_check.publication_proof_at(publication, 0).unwrap()
        assert_eq(@program_check.proof_input_count(root), 2)
        let left = @program_check.proof_input_at(root, 0).unwrap()
        assert_true(
          physical_equal(left, @program_check.proof_input_at(root, 1).unwrap()),
        )
        assert_eq(
          @program_check.proof_source(left).unit_definition_cid,
          @program_check.unit_definition_cid(
            checked,
            if imported {
              0
            } else {
              1
            },
          ).unwrap(),
        )
        let other = public_checked(
          @program_check.check_parsed_with_evidence(
            parsed,
            environment,
            None,
            evidence,
            limits,
          ),
        )
        assert_true(
          @step_bounds.check_target_rows(
            @program_check.unit_pipeline(other, 1).unwrap(),
            Step(2),
            @program_check.proof_application(root),
            10000,
          )
          is Err(_),
        )
      }
      if kind == "cross_join" {
        let operations = @context.stage_requirement_operations(
          @program_check.requirements(checked),
        )
        let mut right_check = false
        for i in 0..<@context.operation_closure_count(operations) {
          if @context.operation_closure_at(operations, i)
            is Some(ExecutionCheck(CrossJoinRows(check))) &&
            check.rule == @context.RequireExactlyOneRightRow {
            assert_eq(check.site.stage, 1)
            assert_eq(check.site.step, 1)
            assert_true(
              physical_equal(
                check.site.pipeline,
                @program_check.unit_pipeline(checked, 1).unwrap(),
              ),
            )
            right_check = true
          }
        }
        assert_true(right_check)
      }
      if kind == "semi" {
        let invalid = source.replace(
          old="\"on\":\"id\"",
          new="\"on\":[{\"left\":\"id\",\"right\":\"missing\"}]",
        )
        assert_true(
          @program_check.check_document_with_evidence(
            invalid,
            environment,
            None,
            evidence,
            limits,
            format=Json,
          )
          is Rejected(_),
        )
        if imported {
          assert_transfer_work_boundary(parsed, environment, evidence, limits)
        }
      }
      assert_true(
        @program_check.check_parsed_with_evidence(
          parsed,
          environment,
          None,
          evidence,
          { ..limits, compilation: { ..limits.compilation, work: 0, }, },
        )
        is Rejected(_),
      )
    }
  }
}
