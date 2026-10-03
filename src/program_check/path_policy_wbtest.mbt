///|
test "Source-backed current TRAIL retains selector sources and independent search limits" {
  for mode in 0..<3 {
    for patterned in [false, true] {
      let relation = mode != 0
      let path_step = if relation { 4 } else { 3 }
      let graph_body =
        #|{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"remote","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}OTHER_NODE],"edges":[{"name":"E","from":"remote","key":["id"],"source":{"definition":"N","key":["id"]},"target":{"definition":"N","key":["extra"]},"labels":[{"name":"R","properties":{"mode":"all_columns"}}]}]}
      let graph_body = graph_body.replace(
        old="OTHER_NODE",
        new=if mode == 2 {
          "," +
          (
            #|{"name":"M","from":"right","key":["id"],"labels":[{"name":"Node","properties":{"mode":"all_columns"}}]}
          )
        } else {
          ""
        },
      )
      // Independent Source domain preimage is recorded by the MATCH policy test.
      let selector = if relation {
        "{\"from\":\"starts\",\"id\":\"element\"}"
      } else {
        "{\"ids\":[{\"definition\":\"N\",\"domain\":\"sha256:e95f67084a112ecd81cf96752d7dcffc731922c81ee7946fcf8ab2ef11a5b4a5\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}]}"
      }
      let steps = "{\"from\":\"remote\",\"derive\":{\"value\":\"extra\"}},{\"filter\":\"id = id\"},{\"property_graph\":" +
        graph_body +
        ",\"as\":\"g\"}" +
        (if relation {
          ",{\"match_nodes\":{\"definition\":\"" +
          (if mode == 2 { "M" } else { "N" }) +
          "\",\"bindings\":{\"identity\":\"element\"},\"where\":{\"literal\":true},\"fields\":[\"element\"]},\"as\":\"starts\"}"
        } else {
          ""
        }) +
        ",{\"from\":\"g\",\"traverse\":{\"start\":" +
        selector +
        ",\"path_mode\":\"trail\",\"emit\":\"paths\"," +
        (if patterned {
          "\"hops\":[{\"direction\":\"out\",\"edge_types\":[\"R\"]}]"
        } else {
          "\"direction\":\"out\",\"min_hops\":0,\"max_hops\":2"
        }) +
        "}},{\"select\":[{\"id\":\"hop_count\"}]}"
      let program = checked_direct_program_fixture(
        graph_steps=steps,
        graph_right=mode == 2,
        graph_traversal="traverse",
        graph_traversal_step=path_step,
        graph_step_limit=if relation { 7 } else { 6 },
        property_graph=true,
      ) catch {
        Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
          fail(
            "Source TRAIL pipeline: " +
            @debug.to_string(issue.kind) +
            " at " +
            @debug.to_string(issue.path),
          )
        Source(SourceView(Context(Stages(Capacity(stage, visit, issue))))) =>
          fail(
            "Source TRAIL capacity " +
            stage.to_string() +
            "/" +
            visit.to_string() +
            ": " +
            @debug.to_string(issue),
          )
        error => fail("Source TRAIL admission: " + @debug.to_string(error))
      }
      let unit = program.units[0]
      let policy = publication_source_policy(unit.publications[0]).unwrap()
      assert_eq(
        publication_policy_source_count(policy),
        if mode == 2 {
          2
        } else {
          1
        },
      )
      let mut selected = None
      for index in 0..<publication_policy_carrier_step_count(policy) {
        let candidate = publication_policy_carrier_step_at(policy, index).unwrap()
        if candidate.step == path_step {
          assert_true(selected is None)
          selected = Some(candidate)
        }
      }
      let retained = selected.unwrap()
      assert_eq(retained.step, path_step)
      // Literal identities, finite bounds and static hop labels have no
      // external value provenance. Do not invent the retired predicate's proof.
      assert_true(retained.unknown_provenance)
      let step = @pipeline.step_at(unit.pipeline, path_step).unwrap()
      match (retained.operation, step.operation) {
        (Traverse(checked=a, selector=target), Traverse(checked=b, ..)) => {
          assert_true(physical_equal(a, b))
          assert_eq(
            target,
            if relation {
              Some(@pipeline.Step(3))
            } else {
              None
            },
          )
        }
        _ => fail("current path operation lost")
      }
      let mut edges = 0
      for i in 0..<publication_policy_edge_count(policy) {
        let edge = publication_policy_edge_at(policy, i).unwrap()
        if edge.step == path_step {
          assert_eq(
            edge.occurrence.target,
            if edges == 0 {
              @pipeline.Step(2)
            } else {
              @pipeline.Step(3)
            },
          )
          assert_eq(
            edge.occurrence.role,
            if edges == 0 {
              @pipeline.Primary
            } else {
              @pipeline.Right
            },
          )
          edges += 1
        }
      }
      assert_eq(edges, if relation { 2 } else { 1 })
      let limit = unit_traversal_limit_at(program, 0, 0).unwrap()
      assert_true(physical_equal(traversal_limit_selection(limit).step, step))
      for scope in [@step_bounds.SearchPaths, @step_bounds.OutputRows] {
        assert_eq(
          @derivation.minimum_value(
            @wire.limit_minimum(traversal_limit_claim(limit, scope)),
          ),
          1000L,
        )
      }
    }
  }
}
