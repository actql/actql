///|
test "Graph presence projection fragments long names and nested values under one row owner" {
  let name = "Z".repeat(513)
  let payload = "[" + Array::make(128, "1").join(",") + "]"
  let nodes = keyed_source_owner(
    "{\"person_key\":{\"type\":\"number\",\"nullable\":false},\"" +
    name +
    "\":{\"type\":\"array\",\"items\":{\"type\":\"number\",\"nullable\":false},\"nullable\":false}}",
    "[{\"person_key\":1,\"" + name + "\":" + payload + "}]",
  )
  let empty = keyed_source_owner(
    "{\"person_key\":{\"type\":\"number\",\"nullable\":false}}", "[]",
  )
  let graph_owner = keyed_bridge_owner(
    nodes,
    empty,
    body=Some(
      "[{\"property_graph\":{\"version\":\"actql-property-graph-constructor/0.1\",\"nodes\":[{\"name\":\"N\",\"from\":\"nodes\",\"key\":[\"person_key\"],\"labels\":[{\"name\":\"P\",\"properties\":{\"mode\":\"columns\",\"columns\":[{\"from\":\"" +
      name +
      "\",\"to\":\"" +
      name +
      "\"}]}}]},{\"name\":\"M\",\"from\":\"edges\",\"key\":[\"person_key\"],\"labels\":[]}],\"edges\":[]},\"as\":\"g\"}]",
    ),
  )
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, empty),
    {
      ..carrier_graph_storage_limits(),
      max_value_nodes: 200,
      max_contract_work: 10000,
      max_work: 100000,
    },
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("long-name Graph construction")
  }
  let owner = keyed_graph_receiver(graph_owner, body="[{\"node_rows\":true}]")
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let start = (control, work, slots, limits) => {
    @local_bridge.start_graph_to_rows(
      control,
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      input,
      1,
      limits,
      slots,
      10000,
      [],
      control_work_limit=Some(work),
    )
  }
  // Order 2; initialize 4; field reads 5 (including label P); match probes
  // 2+3+4+9=18; recheck 24+6+2+259=291; verify 4; start row 1 = 325.
  // Label P construction adds two Text recheck polls to setup: 327.
  // Shared row: load/recheck 295; charge start 1; names 13 (one long-name
  // setup plus nine fragments and three short names); ID 18; label/key 2;
  // array 258; commit 1 = 588. Total 915 polls. The final Array recheck
  // includes an empty-stack poll; measurement has no final container sentinel.
  let exact_work = 915
  // Order 4 + matched cells 4 + borrowed depth/custody 23 + row scope 5
  // + measurement frames 2 + the provisional label P = 39, independent of
  // the 128 borrowed immutable property elements.
  let exact_slots = 39
  // Row + full ID + labels/P + scalar key + Array/128 elements = 141 nodes.
  // Names id/labels/person_key/long name = 531 bytes; ID = 110; P = 1.
  let limits : @execution.ValueLimits = {
    max_nodes: 141,
    max_text_bytes: 642,
    max_depth: 20,
    max_work: 783,
  }
  let mut expected_wire = None
  for quantum in [1, 7, 256] {
    let active = start(@bounded.control(), exact_work, exact_slots, limits).unwrap()
    let mut terminal = false
    let mut cumulative = 0L
    for _ in 0..<1000 {
      match @local_bridge.advance_events_to_rows(active, quantum).unwrap() {
        @local_bridge.Continue(work~, ..) => {
          assert_true(
            work >= cumulative && work - cumulative <= quantum.to_int64(),
          )
          cumulative = work
        }
        @local_bridge.Complete(output, work~, ..) => {
          assert_eq(work, exact_work.to_int64())
          assert_eq(@execution.completed_row_count(output), 1)
          let column = property_rows_column(output, name)
          guard @execution.completed_presence_cell(output, 0, column)
            is Ok(@execution.Present(@admitted.Array(values))) else {
            fail("nested Graph property disappeared")
          }
          assert_eq(@admitted.element_count(values), 128)
          for index in 0..<128 {
            assert_true(
              @admitted.element_at(values, index) is Some(@admitted.Number(1)),
            )
          }
          let wire = @execution.completed_output_row_wire(
            output, 0, 10000, 1000, 20,
          ).unwrap()
          assert_true(
            wire.has_prefix("{\"" + name + "\":" + payload + ",\"id\":"),
          )
          assert_true(wire.has_suffix(",\"labels\":[\"P\"],\"person_key\":1}"))
          if expected_wire is Some(expected) {
            assert_eq(wire, expected)
          }
          expected_wire = Some(wire)
          terminal = true
          break
        }
        _ => fail("Graph projection stopped before its exact boundary")
      }
    }
    assert_true(terminal)
    assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
    assert_true(@graphs.completed_available(graph))
  }
  for shortage in [0, 1, 2] {
    let active = start(
      @bounded.control(),
      exact_work - (if shortage == 0 { 1 } else { 0 }),
      exact_slots - (if shortage == 1 { 1 } else { 0 }),
      { ..limits, max_work: if shortage == 2 { 782 } else { 783 }, },
    ).unwrap()
    let mut rejected = false
    for _ in 0..<1000 {
      match @local_bridge.advance_events_to_rows(active, 1).unwrap() {
        @local_bridge.Continue(..) => ()
        @local_bridge.Failed(issue, ..) => {
          assert_eq(
            issue,
            if shortage == 0 {
              @local_bridge.ControlWorkLimit
            } else {
              @local_bridge.RelationOutput(@execution.CaptureLimit)
            },
          )
          rejected = true
          break
        }
        _ => fail("one-short Graph projection exposed an output")
      }
    }
    assert_true(rejected)
    assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
    assert_false(@local_bridge.cleanup_events_to_rows(active).unwrap())
    assert_true(@graphs.completed_available(graph))
  }
  // Long field matching begins after the first three fields (51 polls).
  // 54 falls inside its nine fragments. 128 and 400 are nested rechecks;
  // 800 is nested output measurement, after the second borrowed row starts.
  for barrier in [54, 128, 400, 800] {
    let control = @bounded.control()
    let active = start(control, exact_work, exact_slots, limits).unwrap()
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
    assert_true(@graphs.completed_available(graph))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
