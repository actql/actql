///|
test "Property Graph MATCH derives quantity bounds through Result imports" {
  for
    (nodes, empty) in [
      (true, false),
      (false, false),
      (true, true),
      (false, true),
    ] {
    let (text, _, base, _, limits) = public_input_fixture(
      generated=true,
      graph_policy=true,
    )
    let environment = @program_check.checking_environment(
      @program_check.checking_environment_wire(base),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      property_graph=true,
    )
    let projection = if nodes {
      "{\"match_nodes\":{\"definition\":\"N\",\"label\":\"Node\",\"where\":\"true\",\"fields\":[\"id\",\"value\"]},\"as\":\"projected\"}"
    } else {
      "{\"match_edges\":{\"definition\":\"E\",\"label\":\"R\",\"where\":\"true\",\"fields\":[\"id\",\"value\"]},\"as\":\"projected\"}"
    }
    let source = text
      .replace(
        old="\"as\":\"derived\"}]",
        new="\"as\":\"derived\"},{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"derived\",\"key\":[\"id\"],\"labels\":[{\"name\":\"Node\",\"properties\":{\"mode\":\"all_columns\"}}]}],\"edges\":[{\"name\":\"E\",\"from\":\"derived\",\"key\":[\"id\"],\"source\":{\"definition\":\"N\",\"key\":[\"id\"]},\"target\":{\"definition\":\"N\",\"key\":[\"id\"]},\"labels\":[{\"name\":\"R\",\"properties\":{\"mode\":\"all_columns\"}}]}]},\"as\":\"g\"}," +
          projection +
          "]",
      )
      .replace(
        old="\"results\":{\"out\":{\"from\":\"derived\"",
        new="\"results\":{\"out\":{\"from\":\"projected\"",
      )
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
        } else {
          // One declared node and one independently keyed self-loop per row;
          // construction no longer invents nodes from endpoint values.
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
