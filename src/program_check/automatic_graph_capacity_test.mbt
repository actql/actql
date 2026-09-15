///|
test "standard Graph projection derives quantity bounds through Result imports" {
  for
    (nodes, empty) in [
      (true, false),
      (false, false),
      (true, true),
      (false, true),
    ] {
    let (text, _, environment, _, limits) = public_input_fixture(
      generated=true,
      graph_policy=true,
    )
    let projection = if nodes {
      "{\"node_rows\":true},{\"derive\":{\"value\":\"id\"},\"as\":\"projected\"}"
    } else {
      "{\"edge_rows\":true},{\"select\":[{\"id\":\"src\"},{\"value\":\"dst\"}],\"as\":\"projected\"}"
    }
    let source = text
      .replace(
        old="\"as\":\"derived\"}]",
        new="\"as\":\"derived\"},{\"graph\":{\"source\":\"id\",\"target\":\"value\"}}," +
          projection +
          "]",
      )
      .replace(old="\"from\":\"derived\"", new="\"from\":\"projected\"")
      .replace(old="{\"take\":1,\"as\":\"selected\"}", new="")
      .replace(old="\"from\":\"selected\"", new="\"from\":\"rows\"")
      .replace(
        old="\"rows\":[{\"id\":1}]",
        new=if empty { "\"rows\":[]" } else { "\"rows\":[{\"id\":1}]" },
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
    let parsed = @syntax.parse(source, limits.input, format=Json).unwrap()
    let reused = public_checked(
      @program_check.check_parsed(parsed, environment, None, limits),
    )
    for stage in [0, 1] {
      assert_eq(
        @program_check.unit_definition_cid(program, stage),
        @program_check.unit_definition_cid(reused, stage),
      )
      let publication = @program_check.unit_publication_at(program, stage, 0).unwrap()
      assert_eq(
        @context.publication_row_limit_maximum(
          @program_check.publication_selection(publication),
        ),
        if empty {
          0L
        } else if nodes {
          2L
        } else {
          1L
        },
      )
      assert_true(@program_check.publication_proof_count(publication) > 0)
      for index in 0..<@program_check.publication_proof_count(publication) {
        let proof = @program_check.publication_proof_at(publication, index).unwrap()
        assert_eq(
          @program_check.proof_source(proof).unit_definition_cid,
          @program_check.unit_definition_cid(program, 0).unwrap(),
        )
      }
    }
  }
}
