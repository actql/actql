///|
test "reach expansion is an owned static recipe without fabricated traversal evidence" {
  let fields = @carrier.rows(
    [],
    field_set=Closed,
    max_fields=0,
    max_name_bytes=0,
  ).unwrap()
  let names = @carrier.graph_row_names(
    Unqualified("entity"),
    Unqualified("source"),
    Unqualified("target"),
    None,
    max_name_bytes=100,
  ).unwrap()
  let graph = @carrier.graph(
    @contract.primitive(NumberType, nullable=false),
    fields,
    fields,
    labels=None,
    max_labels=0,
    max_label_bytes=0,
    row_names=Some(names),
  ).unwrap()
  for
    (direction, expected) in [
      ("in", @graph.Incoming),
      ("out", @graph.Outgoing),
      ("both", @graph.Both),
    ] {
    for
      (depth, expected_depth) in [
        ("1", 1.0),
        ("3", 3.0),
        ("9007199254740992", 9007199254740992.0),
      ] {
      let pipeline = @pipeline.check_carriers(
        asof_test_cursor(
          "[{\"reach\":{\"start\":10,\"direction\":\"" +
          direction +
          "\",\"max_depth\":" +
          depth +
          "}}]",
        ),
        [("g", graph)],
        None,
        None,
        {
          max_steps: 1,
          max_work: 100000,
          max_text_bytes: 100000,
          max_nodes: 10000,
          max_tokens: 10000,
          max_depth: 100,
        },
      ).unwrap()
      let step = @pipeline.step_at(pipeline, 0).unwrap()
      guard step.operation is @pipeline.Reach(operation) else { fail("reach") }
      let obligations = @pipeline.operation_obligation_group_at(
        step.operation,
        0,
      ).unwrap()
      let mut expansions = 0
      let mut remaining = 0
      for index in 0..<@pipeline.operation_obligations_count(obligations) {
        let site : OperationRequirementSite = {
          stage: 0,
          producer_visit: 0,
          step: 0,
          group: 0,
          index,
          pipeline,
          obligations,
          requirement: @pipeline.operation_obligations_at(obligations, index).unwrap(),
        }
        match reach_expansion(site, index).unwrap() {
          None => remaining += 1
          Some(expansion) => {
            expansions += 1
            assert_true(physical_equal(expansion.site, site))
            assert_true(physical_equal(expansion.step, step))
            assert_true(physical_equal(expansion.operation, operation))
            assert_true(
              physical_equal(expansion.start, @graph.reach_start(operation)),
            )
            assert_true(expansion.start.value is Number(10.0))
            assert_eq(expansion.input, @pipeline.Input(0))
            assert_eq(expansion.direction, expected)
            assert_eq(expansion.minimum_hops, 0.0)
            assert_eq(expansion.maximum_hops, expected_depth)
            assert_eq(expansion.emission, @graph.TraversedNodes)
            let output = @carrier.relation_rows(
              @graph.reach_output(expansion.operation),
            ).unwrap()
            assert_eq(@carrier.field_count(output), 4)
            for
              (i, name) in [
                (0, "depth"),
                (1, "entity"),
                (2, "node_id"),
                (3, "start_id"),
              ] {
              assert_eq(
                @carrier.field_at(output, i).unwrap().name,
                Unqualified(name),
              )
            }
            let resolution = ReachExpansion(expansion)
            assert_eq(resolution_occurrence(resolution).0, index)
            assert_true(
              physical_equal(resolution_occurrence(resolution).1, site),
            )
            for
              invalid in [
                { ..site, step: 99, },
                { ..site, group: 1, },
                { ..site, index: 0, },
              ] {
              assert_true(reach_expansion(invalid, index) is Err(_))
            }
            assert_true(reach_expansion(site, -1) is Err(ForeignOccurrence(0)))
          }
        }
      }
      assert_eq(expansions, 1)
      // Admission, membership, traversal semantics, order, resources and profile
      // do not become resolved merely because a macro recipe has been selected.
      assert_eq(remaining, 6)
    }
  }
}
