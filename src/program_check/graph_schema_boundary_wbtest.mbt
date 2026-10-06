///|
test "current Program admission requires MATCH definitions and explicit traversal path modes" {
  let edges = formal_property_suffix()
    .replace(
      old="\"edges\":[]",
      new="\"edges\":[{\"name\":\"E\",\"from\":\"seed\",\"key\":[\"id\"],\"source\":{\"definition\":\"N\",\"key\":[\"id\"]},\"target\":{\"definition\":\"N\",\"key\":[\"id\"]},\"labels\":[{\"name\":\"Link\",\"properties\":{\"mode\":\"all_columns\"}}]}]",
    )
    .replace(
      old="\"match_nodes\":{\"definition\":\"N\",\"label\":\"Node\"",
      new="\"match_edges\":{\"definition\":\"E\",\"label\":\"Link\"",
    )
  for
    (suffix, required_member, expected) in [
      (
        formal_property_suffix(),
        "\"definition\":\"N\",\"label\":\"Node\",",
        @pipeline.GraphMatch(
          @graph.Structure(@graph.Decode(@decode.MissingField)),
        ),
      ),
      (
        edges,
        "\"definition\":\"E\",\"label\":\"Link\",",
        @pipeline.GraphMatch(
          @graph.Structure(@graph.Decode(@decode.MissingField)),
        ),
      ),
      (
        current_trail_resources_suffix("out", "1"),
        "\"path_mode\":\"trail\",",
        @pipeline.GraphMatch(@graph.Structure(@graph.UnsupportedGraphProfile)),
      ),
    ] {
    for current in [true, false] {
      let programs : Array[CheckedProgram] = []
      try
        local_construction_fixture(
          { work: 100000000, bytes: 10000000, nodes: 1000000, depth: 100, },
          through_check=true,
          checked_results=programs,
          graph=true,
          graph_construction_limit=Some(1000),
          traversal_capacity=required_member == "\"path_mode\":\"trail\",",
          generated_rows=Some("[{\"id\":1},{\"id\":2}]"),
          producer_expression="id",
          producer_suffix=if current {
            suffix
          } else {
            suffix.replace(old=required_member, new="")
          },
          producer_result_from="projected",
          extra_step_budget=3,
        )
      catch {
        Source(SourceView(Program(Program(Pipeline(_, issue))))) => {
          assert_false(current)
          assert_eq(issue.kind, expected)
          assert_eq(programs.length(), 0)
        }
        error => raise error
      } noraise {
        _ => {
          assert_true(current)
          assert_eq(programs.length(), 1)
          assert_true(unit_publication_at(programs[0], 0, 0) is Some(_))
        }
      }
    }
  }
}
