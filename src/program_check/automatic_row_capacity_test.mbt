///|
test "standard row capacity uses bound counts with and without input evidence" {
  for generated in [false, true] {
    let (text, _, environment, _, limits) = public_input_fixture(generated~)
    let text = text.replace(old="\"default\":1", new="\"default\":3")
    for
      operation in [
        "\"take\":{\"$param\":\"n\"}", "\"top_k\":{\"k\":{\"$param\":\"n\"},\"by\":[{\"id\":\"asc\"}]}",
        "\"top_k_by\":{\"partition_by\":[],\"k\":{\"$param\":\"n\"},\"by\":[{\"id\":\"asc\"}]}",
      ] {
      let source = text.replace(old="\"take\":1", new=operation)
      let program = public_checked(
        @program_check.check_document(
          source,
          environment,
          None,
          limits,
          format=Json,
        ),
      )
      let publication = @program_check.unit_publication_at(program, 1, 0).unwrap()
      assert_eq(
        @context.publication_row_limit_maximum(
          @program_check.publication_selection(publication),
        ),
        if generated {
          1L
        } else {
          3L
        },
      )
      // An already tighter values bound is transferred, not rebuilt as a
      // redundant clamp. Without that premise the authored bound is generated.
      if generated {
        assert_eq(
          @context.program_identity_capacity_metadata_usage(
            @program_check.source_identity(program),
          ),
          (606, 22),
        )
      }
    }
  }
}

///|
test "standard row capacity composes expansion and additive bounds through Result demand" {
  let (text, _, environment, _, limits) = public_input_fixture(
    generated=true,
    repeated=true,
  )
  for
    (operation, expected) in [
      (
        "\"unpivot\":{\"columns\":[\"value\",\"value\"],\"keep\":[\"id\"],\"name_column\":\"name\",\"value_column\":\"value\"}",
        4L,
      ),
      (
        "\"row_window\":{\"kind\":\"sliding\",\"time\":\"id\",\"size\":5,\"step\":2}",
        6L,
      ),
    ] {
    let source = text.replace(
      old="{\"append\":{\"with\":\"rows\"}}",
      new="{\"append\":{\"with\":\"rows\"}},{" + operation + "}",
    )
    let limits = {
      ..limits,
      compilation: {
        ..limits.compilation,
        structure: { ..limits.compilation.structure, steps: 6, },
      },
    }
    let program = public_checked(
      @program_check.check_document(
        source,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
    let publication = @program_check.unit_publication_at(program, 1, 0).unwrap()
    assert_eq(
      @context.publication_row_limit_maximum(
        @program_check.publication_selection(publication),
      ),
      expected,
    )
    let proof = @program_check.publication_proof_at(publication, 0).unwrap()
    assert_eq(@program_check.proof_source(proof).source_ordinal, 1)
    assert_eq(@program_check.proof_input_count(proof), 1)
    assert_eq(
      @program_check.proof_input_count(
        @program_check.proof_input_at(proof, 0).unwrap(),
      ),
      2,
    )
  }
}

///|
test "bound count document and parsed rejection preserves its typed input cause" {
  for generated in [false, true] {
    let (text, _, environment, _, limits) = public_input_fixture(generated~)
    let source = text
      .replace(old="\"take\":1", new="\"take\":{\"$param\":\"n\"}")
      .replace(
        old="\"type\":\"number\",\"default\":1",
        new="\"type\":\"number\",\"nullable\":true,\"default\":1",
      )
    for value in ["0", "-1", "1.5", "9007199254740992", "null"] {
      let supplied = Some(request_values("{\"n\":" + value + "}"))
      for parsed in [false, true] {
        let outcome = if parsed {
          @program_check.check_parsed(
            @syntax.parse(source, limits.input, format=Json).unwrap(),
            environment,
            supplied,
            limits,
          )
        } else {
          @program_check.check_document(
            source,
            environment,
            supplied,
            limits,
            format=Json,
          )
        }
        guard outcome is Rejected(diagnostic) else {
          fail("invalid bound count passed checking")
        }
        assert_true(
          @program_check.diagnostic_cause(diagnostic)
          is @program_check.LocalConstructionFailure::Source(
            SourceView(
              Context(
                Stages(
                  RowCapacity(
                    Construction(_, _, Application(InvalidBoundCount))
                  )
                )
              )
            )
          ),
        )
        assert_eq(@program_check.diagnostic_category(diagnostic), InvalidInput)
        assert_true(@program_check.diagnostic_location(diagnostic) is None)
      }
    }
    for value in ["1", "3"] {
      assert_true(
        @program_check.check_document(
          source,
          environment,
          Some(request_values("{\"n\":" + value + "}")),
          limits,
          format=Json,
        )
        is Checked(_),
      )
    }
  }
}
