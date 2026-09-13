///|
test "graph row projection binds validation and restoration without discharging resources" {
  for complete in [false, true] {
    let properties = if complete {
      @carrier.rows([], field_set=Closed, max_fields=0, max_name_bytes=0).unwrap()
    } else {
      @carrier.unknown_rows()
    }
    let names = @carrier.graph_row_names(
      Unqualified("node"),
      Unqualified("source"),
      Unqualified("target"),
      Some(Unqualified("label")),
      max_name_bytes=100,
    ).unwrap()
    let graph = @carrier.graph(
      @contract.primitive(NumberType, nullable=false),
      properties,
      properties,
      labels=None,
      max_labels=0,
      max_label_bytes=0,
      row_names=Some(names),
    ).unwrap()
    for name in ["node_rows", "edge_rows"] {
      let pipeline = @pipeline.check_carriers(
        asof_test_cursor("[{\"" + name + "\":true}]"),
        [("g", graph)],
        None,
        None,
        {
          max_steps: 1,
          max_work: 10000,
          max_text_bytes: 10000,
          max_nodes: 1000,
          max_tokens: 1000,
          max_depth: 100,
        },
      ).unwrap()
      let step = @pipeline.step_at(pipeline, 0).unwrap()
      guard step.operation is @pipeline.Projection(operation) else {
        fail("projection")
      }
      let obligations = @pipeline.operation_obligation_group_at(
        step.operation,
        0,
      ).unwrap()
      assert_eq(@pipeline.operation_obligations_count(obligations), 4)
      let mut linked = 0
      for index in 0..<4 {
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
        match graph_projection_execution_check(site).unwrap() {
          Some(GraphProjection(check)) => {
            linked += 1
            assert_true(physical_equal(check.site, site))
            assert_true(physical_equal(check.operation, operation))
            assert_eq(check.input, @pipeline.Input(0))
            assert_true(
              physical_equal(@projection.input(check.operation), graph),
            )
            assert_eq(
              operation_execution_failure(GraphProjection(check)),
              RejectOperationOutput,
            )
            assert_eq(
              operation_execution_phase(GraphProjection(check)),
              if index == 0 {
                BeforeOperationInputUse
              } else {
                BeforeOperationOutput
              },
            )
            assert_true(
              graph_projection_execution_check({ ..site, index: 99, })
              is Err(ForeignOccurrence(0)),
            )
            assert_true(
              graph_projection_execution_check({ ..site, step: 99, })
              is Err(ForeignOccurrence(99)),
            )
            assert_true(
              direct_execution_candidate(
                site,
                sequence_limit_policy(false),
                Ok(None),
                Ok(None),
              )
              is Ok(Some(GraphProjection(_))),
            )
          }
          None => assert_eq(index, 3)
          _ => fail("wrong execution rule")
        }
      }
      assert_eq(linked, 3)
    }
  }
}
