///|
test "Graph label output resumes Text and array construction with exact limits" {
  for
    (many, edge) in [(false, false), (false, true), (true, false), (true, true)] {
    let labels = if many {
      Array::makei(128, index => {
        "L" +
        (if index < 10 { "00" } else if index < 100 { "0" } else { "" }) +
        index.to_string()
      })
    } else {
      ["L".repeat(513)]
    }
    let declarations = labels
      .map(label => {
        "{\"name\":\"" +
        label +
        "\",\"properties\":{\"mode\":\"no_properties\"}}"
      })
      .join(",")
    let nodes = keyed_source_owner(
      "{\"person_key\":{\"type\":\"number\",\"nullable\":false}}", "[{\"person_key\":1}]",
    )
    let empty = if edge {
      keyed_source_owner(
        "{\"edge_key\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"edge_key\":10,\"src\":1,\"dst\":1}]",
      )
    } else {
      keyed_source_owner(
        "{\"person_key\":{\"type\":\"number\",\"nullable\":false}}", "[]",
      )
    }
    let graph_owner = keyed_bridge_owner(
      nodes,
      empty,
      body=Some(
        "[{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"person_key\"],\"labels\":[" +
        (if edge {
          "]}],\"edges\":[{\"name\":\"E\",\"from\":\"edges\",\"key\":[\"edge_key\"],\"source\":{\"definition\":\"N\",\"key\":[\"src\"]},\"target\":{\"definition\":\"N\",\"key\":[\"dst\"]},\"labels\":[" +
          declarations +
          "]}]}"
        } else {
          declarations +
          "]},{\"name\":\"M\",\"from\":\"edges\",\"key\":[\"person_key\"],\"labels\":[]}],\"edges\":[]}"
        }) +
        ",\"as\":\"g\"}]",
      ),
    )
    let construction = @local_bridge.start_rows_to_property_graph(
      @bounded.control(),
      prepared_sequence(graph_owner),
      0,
      keyed_bridge_inputs(graph_owner, nodes, empty),
      { ..carrier_graph_storage_limits(), max_work: 1000000, },
      8192L,
      10000,
      () => true,
    ).unwrap()
    guard keyed_bridge_terminal(construction)
      is @local_bridge.Complete(graph, ..) else {
      fail("label fixture construction")
    }
    let owner = keyed_graph_receiver(
      graph_owner,
      body=if edge {
        "[{\"edge_rows\":true}]"
      } else {
        "[{\"node_rows\":true}]"
      },
    )
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
    // Empty labels cost 105 / 258 polls, retaining the JSON identity
    // measurement marker without a logical charge. One 513-unit Text adds 11 construction,
    // 11 first recheck, 11 row recheck and 12 stepped measurement polls.
    // 128 four-unit labels add 384 construction, 384 per recheck and 257
    // measurement polls. No successful execution supplies these allowances.
    let work = (if edge { 258 } else { 105 }) + (if many { 1409 } else { 45 })
    // Existing order/matched/recheck custody = 4+3+23 (node), 4+5+23 (edge).
    // Provisional labels remain reserved while row scope and two measurement
    // frames overlap: add label count and 6 (node) / 8 (edge).
    let slots = if many {
      if edge {
        168
      } else {
        164
      }
    } else if edge {
      41
    } else {
      37
    }
    let limits : @execution.ValueLimits = {
      max_nodes: (if edge { 27 } else { 11 }) + (if many { 128 } else { 1 }),
      max_text_bytes: (if edge { 352 } else { 128 }) +
      (if many { 512 } else { 513 }),
      max_depth: 20,
      max_work: (if edge { 379 } else { 139 }) + (if many { 640 } else { 514 }),
    }
    let start = (control, allowance, workspace, value_limits) => {
      @local_bridge.start_graph_to_rows(
        control,
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        input,
        1,
        value_limits,
        workspace,
        10000,
        [],
        control_work_limit=Some(allowance),
      ).unwrap()
    }
    for quantum in [1, 7, 256] {
      let active = start(@bounded.control(), work, slots, limits)
      let mut done = false
      let mut previous = 0L
      for _ in 0..<2000 {
        match @local_bridge.advance_events_to_rows(active, quantum).unwrap() {
          @local_bridge.Continue(work~, ..) => {
            assert_true(
              work >= previous && work - previous <= quantum.to_int64(),
            )
            previous = work
          }
          @local_bridge.Complete(output, work~, ..) => {
            assert_eq(
              work,
              ((if edge { 258 } else { 105 }) + (if many { 1409 } else { 45 })).to_int64(),
            )
            assert_eq(@execution.completed_row_count(output), 1)
            let column = property_rows_column(output, "labels")
            guard @execution.completed_cell(output, 0, column)
              is Some(@execution.Captured(@admitted.Array(values))) else {
              fail("Graph labels missing")
            }
            assert_eq(@admitted.element_count(values), labels.length())
            for index in 0..<labels.length() {
              guard @admitted.element_at(values, index)
                is Some(@admitted.Text(actual)) else {
                fail("Graph label type")
              }
              assert_eq(actual, labels[index])
            }
            done = true
            break
          }
          _ => fail("exact label boundary")
        }
      }
      assert_true(done)
      assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_true(@graphs.completed_available(graph))
    }
    for short in [0, 1, 2, 3] {
      let active = start(
        @bounded.control(),
        work - (if short == 0 { 1 } else { 0 }),
        slots - (if short == 1 { 1 } else { 0 }),
        {
          ..limits,
          max_work: limits.max_work - (if short == 2 { 1 } else { 0 }),
          max_text_bytes: limits.max_text_bytes -
          (if short == 3 { 1 } else { 0 }),
        },
      )
      let mut rejected = false
      for _ in 0..<2000 {
        match @local_bridge.advance_events_to_rows(active, 1).unwrap() {
          @local_bridge.Continue(..) => ()
          @local_bridge.Failed(issue, ..) => {
            assert_eq(
              issue,
              if short == 0 {
                @local_bridge.ControlWorkLimit
              } else {
                @local_bridge.RelationOutput(@execution.CaptureLimit)
              },
            )
            rejected = true
            break
          }
          _ => fail("short label boundary exposed output")
        }
      }
      assert_true(rejected)
      assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_true(@graphs.completed_available(graph))
    }
    // Poll 34 is within Text construction, not after the whole labels field.
    // The wide variant also stops midway through the provisional label array.
    for
      barrier in (if many {
        if edge {
          [94, 200, 400]
        } else {
          [34, 200, 400]
        }
      } else if edge {
        [94, 100]
      } else {
        [34, 40]
      }) {
      let control = @bounded.control()
      let active = start(control, work, slots, limits)
      for _ in 0..<barrier {
        assert_true(
          @local_bridge.advance_events_to_rows(active, 1).unwrap()
          is @local_bridge.Continue(..),
        )
      }
      assert_true(@bounded.request_cancel(control))
      assert_true(
        @local_bridge.advance_events_to_rows(active, 1).unwrap()
        is @local_bridge.Stopped(_, ..),
      )
      assert_true(@graphs.completed_available(graph))
      assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
    }
    assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
    assert_true(@graphs.discard_completed(graph))
  }
}
