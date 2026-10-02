///|
test "normal Program admission rejects the retired graph constructor instead of silently upgrading it" {
  let old_graph =
    #|{"version":"actql/0.1","id":"retired-graph","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"nodes"},{"graph":{"nodes":{"from":"nodes","id":"id","fields":[]},"edges":{"from":"nodes","source":"id","target":"id","fields":[]}},"as":"g"},{"from":"g","node_rows":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let (_, _, base, _, limits) = public_input_fixture(
    generated=true,
    graph_policy=true,
  )
  for sga in [false, true] {
    let environment = @program_check.checking_environment(
      @program_check.checking_environment_wire(base),
      { text_time: false, veca: false, },
      { rela: true, sga, tea: false, calendar: false, text_rank: false, },
      property_graph=true,
    )
    let rejected = public_rejected(
      @program_check.check_document(
        old_graph,
        environment,
        None,
        limits,
        format=Json,
      ),
    )
    assert_true(
      @program_check.diagnostic_cause(rejected)
      is Units(UnsupportedStaticPath(_)),
    )
  }
}

///|
test "public Property Graph checking derives Result capacity without interpreting the legacy SGA profile" {
  for empty in [false, true] {
    let (text, _, legacy, _, limits) = public_input_fixture(
      generated=true,
      graph_policy=true,
    )
    let source = text
      .replace(
        old="\"as\":\"seed\"},{\"assert_rows\":{\"unique_by\":[\"id\"]}}",
        new="\"as\":\"raw_seed\"},{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"seed\"}",
      )
      .replace(
        old="\"as\":\"derived\"}]",
        new="\"as\":\"derived\"}," +
          (
            #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"seed","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}],"edges":[]},"as":"g"},{"match_nodes":{"definition":"N","label":"Node","where":"id > 0","fields":["id"]}},{"derive":{"value":"id"},"as":"projected"}]
          ),
      )
      .replace(old="\"from\":\"derived\"", new="\"from\":\"projected\"")
      .replace(
        old="\"rows\":[{\"id\":1}]",
        new=if empty { "\"rows\":[]" } else { "\"rows\":[{\"id\":1}]" },
      )
    let limits = {
      ..limits,
      compilation: {
        ..limits.compilation,
        structure: { ..limits.compilation.structure, steps: 7, },
      },
    }
    let rejected = public_rejected(
      @program_check.check_document(source, legacy, None, limits, format=Json),
    )
    assert_true(
      @program_check.diagnostic_cause(rejected)
      is Source(
        Checks(
          OperationProfiles(
            UnsupportedProfile(0, 0, 3, @pipeline.PropertyGraph)
          )
        )
      ),
    )
    let environment = @program_check.checking_environment(
      @program_check.checking_environment_wire(legacy),
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      property_graph=true,
    )
    let outcome = @program_check.check_document(
      source,
      environment,
      None,
      limits,
      format=Json,
    )
    if outcome is Rejected(diagnostic) {
      match @program_check.diagnostic_cause(diagnostic) {
        Closure(UnresolvedOperation(site)) =>
          fail(
            "unresolved Property Graph operation at step \{site.step}, obligation \{site.index}",
          )
        Closure(Requirements(_)) => fail("Property Graph requirements")
        Closure(Contracts(issue)) =>
          fail("Property Graph contracts: " + @debug.to_string(issue))
        Closure(Operations(_)) => fail("Property Graph resolution")
        _ => ()
      }
    }
    let program = public_checked(outcome)
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
          1L
        },
      )
      assert_true(@program_check.publication_proof_count(publication) > 0)
      for i in 0..<@program_check.publication_proof_count(publication) {
        let proof = @program_check.publication_proof_at(publication, i).unwrap()
        assert_eq(
          @program_check.proof_source(proof).unit_definition_cid,
          @program_check.unit_definition_cid(program, 0).unwrap(),
        )
      }
    }
  }
}
