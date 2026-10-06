///|
fn property_rows_terminal(
  active : @local_bridge.EventsToRowsExecution,
) -> @execution.CompletedOutput raise {
  for _ in 0..<1000 {
    match @local_bridge.advance_events_to_rows(active, 1).unwrap() {
      @local_bridge.Continue(..) => ()
      @local_bridge.Complete(output, ..) => return output
      _ => fail("Graph row bridge failed")
    }
  }
  fail("Graph row bridge exceeded fixture step bound")
}

///|
fn property_rows_column(
  output : @execution.CompletedOutput,
  name : String,
) -> Int {
  for column in 0..<@execution.completed_column_count(output) {
    if @execution.completed_column_name(output, column) == Some(name) {
      return column
    }
  }
  abort("missing output column " + name)
}

///|
fn property_rows_value_limits() -> @execution.ValueLimits {
  { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work: 10000, }
}

///|
fn property_rows_resource_boundary(
  edge : Bool,
  selected? : Bool = false,
  labelled? : Bool = false,
) -> Unit raise {
  let nodes = keyed_source_owner(
    "{\"person_key\":{\"type\":\"number\",\"nullable\":false}}", "[{\"person_key\":1}]",
  )
  let edges = keyed_source_owner(
    "{\"edge_key\":{\"type\":\"number\",\"nullable\":false},\"src\":{\"type\":\"number\",\"nullable\":false},\"dst\":{\"type\":\"number\",\"nullable\":false}}",
    "[{\"edge_key\":10,\"src\":1,\"dst\":1}]",
  )
  let graph_owner = keyed_bridge_owner(
    nodes,
    edges,
    body=Some(
      (
        #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key"],"labels":[]}],"edges":[{"name":"E","from":"edges","key":["edge_key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[]}]},"as":"g"}]
      ),
    ),
  )
  // Labelled variant puts Choice after A. Each of two labels adds a label read,
  // scalar validation, one TextUnits poll, container frame and selector
  // comparison (five work units per short label); cancellation
  // must also work while the first comparison leaves selection pending.
  let graph_owner = if labelled {
    keyed_bridge_owner(
      nodes,
      edges,
      body=Some(
        (
          #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key"],"labels":[{"name":"A","properties":{"mode":"no_properties"}},{"name":"Choice","properties":{"mode":"no_properties"}}]}],"edges":[{"name":"E","from":"edges","key":["edge_key"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"A","properties":{"mode":"no_properties"}},{"name":"Choice","properties":{"mode":"no_properties"}}]}]},"as":"g"}]
        ),
      ),
    )
  } else {
    graph_owner
  }
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("resource boundary Graph")
  }
  let owner = keyed_graph_receiver(
    graph_owner,
    body=if labelled {
      if edge {
        "[{\"edge_rows\":{\"label\":\"choice\"}}]"
      } else {
        "[{\"node_rows\":{\"label\":\"choice\"}}]"
      }
    } else if selected {
      if edge {
        "[{\"edge_rows\":{\"definition\":\"E\"}}]"
      } else {
        "[{\"node_rows\":{\"definition\":\"N\"}}]"
      }
    } else if edge {
      "[{\"edge_rows\":true}]"
    } else {
      "[{\"node_rows\":true}]"
    },
  )
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  let completion = task_test_completion(owner)
  // Independent one-row ledger: key collection + sort initialization = 2.
  // Rechecking each typed identity takes 8 nodes, 11 container/child frames,
  // four TextUnits polls (definition 1, 71-unit domain 2, kind 1), and the
  // final empty-stack poll = 24. Empty labels cost 3; scalar key = 2.
  // Original scan/match/verification/start = 3+6+3+1 or 5+15+5+1.
  // Cell initialization adds schema width (3 / 5). Shared row admission adds
  // reads/rechecks 32 / 82, charge start 1, names 3 / 5, identity measurement
  // 19 / 57, two small cells 2, and commit 1: 58 / 148 polls.
  // The JsonData identity marker adds one measurement poll per identity,
  // without logical node/text charges or another live measurement frame.
  // Totals are 105 / 258, not sampled from a successful product run.
  // Workspace: order 4, matched width, borrowed depth+3 (23), provisional
  // row width+1, and two nested measurement frames: 36 / 40 slots.
  // An explicit definition checks each candidate once before producing it.
  // Two short labels add six row recheck polls as well as the original ten
  // construction/selection polls; their bounded small-value charge is one poll.
  let exact_work = (if edge { 258 } else { 105 }) +
    (if labelled { 16 } else if selected { 1 } else { 0 })
  let exact_slots = if edge { 40 } else { 36 }
  for viewed in [false, true] {
    let start = fn(control, work, slots) {
      if viewed {
        @local_bridge.start_graph_view_to_rows(
          control,
          completion,
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          1,
          property_rows_value_limits(),
          slots,
          1000,
          control_work_limit=Some(work),
        )
      } else {
        @local_bridge.start_graph_to_rows(
          control,
          completion,
          prepared_sequence(owner),
          0,
          input,
          1,
          property_rows_value_limits(),
          slots,
          1000,
          [],
          control_work_limit=Some(work),
        )
      }
    }
    for boundary in [0, 1, 2] {
      let short = boundary == 1
      let short_workspace = boundary == 2
      let active = start(
        @bounded.control(),
        exact_work - (if short { 1 } else { 0 }),
        exact_slots - (if short_workspace { 1 } else { 0 }),
      ).unwrap()
      let mut terminal = false
      let mut cumulative = 0L
      for _ in 0..<300 {
        match @local_bridge.advance_events_to_rows(active, 1).unwrap() {
          @local_bridge.Continue(work~, ..) => {
            assert_true(work >= cumulative && work - cumulative <= 1L)
            cumulative = work
          }
          @local_bridge.Complete(output, work~, ..) => {
            assert_false(short)
            assert_false(short_workspace)
            assert_eq(work, exact_work.to_int64())
            assert_eq(@execution.completed_row_count(output), 1)
            terminal = true
            break
          }
          @local_bridge.Failed(@local_bridge.ControlWorkLimit, work~, ..) => {
            assert_true(short)
            assert_eq(work, (exact_work - 1).to_int64())
            terminal = true
            break
          }
          @local_bridge.Failed(
            @local_bridge.RelationOutput(@execution.CaptureLimit),
            ..
          ) => {
            assert_true(short_workspace)
            terminal = true
            break
          }
          _ => fail("unexpected Graph rows resource result")
        }
      }
      assert_true(terminal)
      assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
      assert_true(@graphs.completed_available(graph))
    }
    // Stop at every charged private phase, including nested identity recheck,
    // ordering and the final append. No partial completion may escape.
    for stop_after in 1..<exact_work {
      let control = @bounded.control()
      let active = start(control, exact_work, exact_slots).unwrap()
      for _ in 0..<stop_after {
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
      assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
      assert_true(@graphs.completed_available(graph))
    }
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
}

///|
test "node rows admit exact work and workspace and reclaim every private phase" {
  property_rows_resource_boundary(false)
}

///|
test "Graph row identity recheck has independent JSON Text frame costs" {
  // Fixed independent full identity: eight value nodes, root/child frames
  // 5+2+2+2, Text chunks 1+2+1, and one final empty-stack poll = 24.
  // Field names total 32 bytes, data Text 1+71+6 = 78; total Text is 110.
  let identity = @admitted.admit(
    @value_contract.primitive(@value_contract.JsonType, nullable=false),
    input_cursor(
      "{\"definition\":\"N\",\"domain\":\"sha256:" +
      String::make(64, '0') +
      "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}",
    ),
    { max_nodes: 8, max_text_bytes: 110, max_depth: 20, },
  ).unwrap()
  let cursor = @admitted.start_recheck_runtime_value(
    identity.value,
    identity.contract,
    { max_nodes: 8, max_text_bytes: 110, max_depth: 20, },
  ).unwrap()
  for _ in 0..<23 {
    assert_true(
      @admitted.advance_recheck_runtime_value(cursor)
      is @admitted.RecheckContinue,
    )
  }
  guard @admitted.advance_recheck_runtime_value(cursor)
    is @admitted.RecheckComplete(_, nodes, bytes) else {
    fail("typed identity did not complete at its independent frame boundary")
  }
  assert_eq(nodes, 8)
  assert_eq(bytes, 110)
}

///|
test "edge rows admit exact work and workspace and reclaim every private phase" {
  property_rows_resource_boundary(true)
}

///|
test "selected node and edge rows retain exact work workspace cancellation and cleanup" {
  property_rows_resource_boundary(false, selected=true)
  property_rows_resource_boundary(true, selected=true)
}

///|
test "label node and edge rows retain exact work workspace cancellation and cleanup" {
  property_rows_resource_boundary(false, labelled=true)
  property_rows_resource_boundary(true, labelled=true)
}

///|
fn property_rows_restore(
  owner : @lower.BoundPrepared,
  original : @graphs.Completed,
) -> @graphs.Completed raise {
  let (cid, body) = snapshot_capture(
    @graphs.completed_storage(original).unwrap(),
  )
  let reload = @local_bridge.start_property_snapshot_reload(
    @bounded.control(),
    owner,
    @pipeline.Step(0),
    input_cursor(body),
    cid,
    carrier_graph_storage_limits(),
    snapshot_caps(),
    8192L,
    1000,
    () => true,
    () => true,
  ).unwrap()
  guard snapshot_terminal(reload) is @local_bridge.Complete(restored, ..) else {
    fail("Graph row snapshot reload")
  }
  assert_eq(
    snapshot_capture(@graphs.completed_storage(restored).unwrap()),
    (cid, body),
  )
  assert_true(@local_bridge.cleanup_rows_to_graph(reload).unwrap())
  restored
}

///|
fn property_rows_retained_copy(
  output : @execution.CompletedOutput,
) -> @execution.CompletedOutput raise {
  let limits : @execution.RowWireLimits = {
    max_columns: 100,
    max_order_work: 10000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  let exporting = @execution.prepare_completed_output_export(
    output,
    10,
    property_rows_value_limits(),
    limits,
    10000,
  ).unwrap()
  let bytes = StringBuilder()
  for _ in 0..<100 {
    match @execution.next_completed_output_export(exporting).unwrap() {
      Some(part) => bytes.write_string(part)
      None => break
    }
  }
  let (receipt, tail) = @execution.finish_completed_output_export(exporting).unwrap()
  bytes.write_string(tail)
  let retained = @execution.retain_admitted_output_stream(
    @execution.completed_export_content(receipt),
    bytes.to_string(),
    () => true,
  )
  let source = @execution.bind_completed_output_export(
    receipt,
    @execution.retained_output_material(retained),
  ).unwrap()
  let importing = @execution.prepare_completed_output_import(
    source,
    10,
    property_rows_value_limits(),
    limits,
    10000,
  ).unwrap()
  for row in 0..<@execution.completed_row_count(output) {
    let wire = @execution.completed_output_row_wire(
      output, row, 10000, 1000, 20,
    ).unwrap()
    @execution.append_completed_output_import_wire(importing, wire, {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
      max_text_bytes: 10000,
    }).unwrap()
  }
  let restored = @execution.finish_completed_output_import(importing).unwrap()
  assert_true(@execution.completed_output_same_occurrence(output, restored))
  restored
}

///|
fn property_rows_project_identity(
  owner : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
) -> Unit raise {
  let selected = keyed_graph_receiver(owner, body="[{\"select\":[\"id\"]}]")
  let binding = @execution.bind_completed_input(selected, 0, owner, output).unwrap()
  let read = @execution.prepare_producer_read(selected, binding, 100, 1000).unwrap()
  let completed = @execution.execute_fixed_producer_input(
    task_test_generated(selected),
    read,
    { rows: run_limits(), max_work: 10000, max_frames: 100, },
  ).unwrap()
  let projected = @execution.completed_output(completed, @pipeline.Step(0)).unwrap()
  // Exercise the resource-admitted path as well as the synchronous evaluator.
  // Charging the input must inspect presence without ordinary access to p.
  let bounded = @execution.start_bounded_binding_rows(
    @bounded.control(),
    task_test_generated(selected),
    read,
    10,
    property_rows_value_limits(),
    property_rows_value_limits(),
    10000,
    100,
    1000,
    10000,
  ).unwrap()
  let mut bounded_output = None
  let mut cumulative = 0L
  for _ in 0..<10000 {
    match @execution.advance_bounded_binding_rows(bounded, 1).unwrap() {
      @execution.BoundedBindingRowsContinue(work~, ..) => {
        assert_true(work >= cumulative && work - cumulative <= 1L)
        cumulative = work
      }
      @execution.BoundedBindingRowsComplete(value, work~, ..) => {
        assert_true(work >= cumulative && work - cumulative <= 1L)
        bounded_output = Some(value)
        break
      }
      _ => fail("bounded guaranteed-column projection failed")
    }
  }
  let bounded_output = bounded_output.unwrap()
  assert_eq(
    @execution.completed_row_count(projected),
    @execution.completed_row_count(output),
  )
  assert_eq(@execution.completed_column_count(projected), 1)
  assert_eq(@execution.completed_column_name(projected, 0), Some("id"))
  for row in 0..<@execution.completed_row_count(projected) {
    // The common Relation projection reads only the guaranteed typed identity,
    // including when other columns in the retained input are absent.
    assert_true(
      @execution.completed_cell(projected, row, 0)
      is Some(@execution.Captured(@admitted.JsonData(@admitted.Object(_)))),
    )
    let wire = @execution.completed_output_row_wire(
      projected, row, 10000, 1000, 20,
    ).unwrap()
    assert_true(
      wire.contains("\"definition\":") && wire.contains("\"key_types\":"),
    )
    assert_eq(
      @execution.completed_output_row_wire(bounded_output, row, 10000, 1000, 20).unwrap(),
      wire,
    )
  }
  assert_eq(
    @execution.completed_row_count(bounded_output),
    @execution.completed_row_count(projected),
  )
  assert_true(@execution.cleanup_bounded_binding_rows(bounded).unwrap())
  assert_false(@execution.cleanup_bounded_binding_rows(bounded).unwrap())
  assert_false(@execution.bounded_binding_rows_cleanup_pending(bounded))
}

///|
fn property_rows_managed_admission(
  owner : @lower.BoundPrepared,
  output : @execution.CompletedOutput,
) -> Unit raise {
  let values = @execution.prepare_managed_output_values(
    owner,
    @pipeline.Step(0),
    10,
    property_rows_value_limits(),
    10000,
    { max_work: 10000, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
  ).unwrap()
  for row in 0..<@execution.completed_row_count(output) {
    @execution.append_completed_projection_managed_values(values, output, row).unwrap()
  }
  let receipt = @execution.finish_managed_output_values(values).unwrap()
  assert_true(
    @execution.managed_output_value_receipt_matches(
      receipt,
      owner,
      @pipeline.Step(0),
    ),
  )
  let usage = @execution.managed_output_value_usage(receipt)
  assert_true(usage.nodes > 0 && usage.work > 0)
  @execution.dispose_managed_output_values_scratch(values)
  assert_true(@execution.managed_output_values_scratch_released(values))
  @execution.dispose_managed_output_values_scratch(values)
  assert_true(@execution.managed_output_values_scratch_released(values))
}

///|
test "definition Graph node rows preserve numeric composite key aliases values NULL and omission" {
  let nodes = keyed_source_owner(
    (
      #|{"person_key":{"type":"number","nullable":false},"tenant_key":{"type":"string","nullable":false},"p":{"type":"number","nullable":true}}
    ),
    (
      #|[{"person_key":2,"tenant_key":"a","p":null},{"person_key":1,"tenant_key":"a","p":7}]
    ),
  )
  let companies = keyed_source_owner(
    (
      #|{"company_key":{"type":"number","nullable":false}}
    ),
    (
      #|[{"company_key":3}]
    ),
  )
  let graph_owner = keyed_bridge_owner(
    nodes,
    companies,
    body=Some(
      (
        #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key","tenant_key"],"labels":[{"name":"Person","properties":{"mode":"columns","columns":[{"from":"p","to":"p"}]}}]},{"name":"M","from":"edges","key":["company_key"],"labels":[]}],"edges":[]},"as":"g"}]
      ),
    ),
  )
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, companies),
    carrier_graph_storage_limits(),
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("Graph construction")
  }
  let restored = property_rows_restore(graph_owner, graph)
  let owner = keyed_graph_receiver(graph_owner, body="[{\"node_rows\":true}]")
  for current in [graph, restored] {
    let input = @graphs.prepare_producer_read(owner, 0, graph_owner, current).unwrap()
    let limits = property_rows_value_limits()
    for viewed in [false, true] {
      let active = if viewed {
        @local_bridge.start_graph_view_to_rows(
          @bounded.control(),
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          @graphs.producer_read_view(input).unwrap(),
          3,
          limits,
          100,
          1000,
        ).unwrap()
      } else {
        @local_bridge.start_graph_to_rows(
          @bounded.control(),
          task_test_completion(owner),
          prepared_sequence(owner),
          0,
          input,
          3,
          limits,
          100,
          1000,
          [],
        ).unwrap()
      }
      let output = property_rows_terminal(active)
      property_rows_managed_admission(owner, output)
      let output = property_rows_retained_copy(output)
      property_rows_project_identity(owner, output)
      assert_eq(@execution.completed_row_count(output), 3)
      let p = property_rows_column(output, "p")
      let person = property_rows_column(output, "person_key")
      let company = property_rows_column(output, "company_key")
      let labels = property_rows_column(output, "labels")
      assert_true(
        @execution.completed_presence_cell(output, 0, company)
        is Ok(@execution.Present(@admitted.Number(3))),
      )
      assert_true(
        @execution.completed_presence_cell(output, 1, person)
        is Ok(@execution.Present(@admitted.Number(1))),
      )
      assert_true(
        @execution.completed_presence_cell(output, 2, person)
        is Ok(@execution.Present(@admitted.Number(2))),
      )
      let mut numbers = 0
      let mut nulls = 0
      let mut omitted = 0
      for row in 0..<3 {
        match @execution.completed_presence_cell(output, row, p).unwrap() {
          @execution.Present(@admitted.Number(7)) => {
            numbers += 1
            assert_true(
              @execution.completed_presence_cell(output, row, person)
              is Ok(@execution.Present(@admitted.Number(1))),
            )
          }
          @execution.Present(@admitted.Null) => {
            nulls += 1
            assert_true(
              @execution.completed_presence_cell(output, row, person)
              is Ok(@execution.Present(@admitted.Number(2))),
            )
          }
          @execution.Absent => {
            omitted += 1
            assert_true(
              @execution.completed_presence_cell(output, row, company)
              is Ok(@execution.Present(@admitted.Number(3))),
            )
            guard @execution.completed_presence_cell(output, row, labels)
              is Ok(@execution.Present(@admitted.Array(items))) else {
              fail("labels array")
            }
            assert_eq(@admitted.element_count(items), 0)
          }
          _ => fail("unexpected property value")
        }
        // Presence does not permit the ordinary reader to sample optional values.
        assert_true(@execution.completed_cell(output, row, p) is None)
      }
      assert_eq((numbers, nulls, omitted), (1, 1, 1))
      assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
      assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
    }
  }
  let selected_owner = keyed_graph_receiver(
    graph_owner,
    body="[{\"node_rows\":{\"definition\":\"n\"}}]",
  )
  let input = @graphs.prepare_producer_read(
    selected_owner, 0, graph_owner, restored,
  ).unwrap()
  for viewed in [false, true] {
    let active = if viewed {
      @local_bridge.start_graph_view_to_rows(
        @bounded.control(),
        task_test_completion(selected_owner),
        prepared_sequence(selected_owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        2,
        property_rows_value_limits(),
        100,
        1000,
      ).unwrap()
    } else {
      @local_bridge.start_graph_to_rows(
        @bounded.control(),
        task_test_completion(selected_owner),
        prepared_sequence(selected_owner),
        0,
        input,
        2,
        property_rows_value_limits(),
        100,
        1000,
        [],
      ).unwrap()
    }
    // The third (Company) input still costs ordering/filter work but does not
    // consume a produced-row slot. Preserve ordinary access after real retention.
    let output = property_rows_retained_copy(property_rows_terminal(active))
    assert_eq(@execution.completed_row_count(output), 2)
    assert_eq(@execution.completed_column_count(output), 5)
    let p = property_rows_column(output, "p")
    let person = property_rows_column(output, "person_key")
    assert_true(
      @execution.completed_cell(output, 0, p) is Some(@execution.Number(7)),
    )
    assert_true(
      @execution.completed_cell(output, 1, p) is Some(@execution.Null),
    )
    assert_true(
      @execution.completed_cell(output, 0, person) is Some(@execution.Number(1)),
    )
    assert_true(
      @execution.completed_cell(output, 1, person) is Some(@execution.Number(2)),
    )
    assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
    assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
  assert_true(@graphs.discard_completed(restored))
}

///|
test "edge rows preserve parallel identities endpoints and composite raw key components after reload" {
  let nodes = keyed_source_owner(
    "{\"node_key\":{\"type\":\"number\",\"nullable\":false}}", "[{\"node_key\":1}]",
  )
  let edges = keyed_source_owner(
    "{\"edge_key\":{\"type\":\"number\",\"nullable\":false},\"tenant\":{\"type\":\"string\",\"nullable\":false},\"source_key\":{\"type\":\"number\",\"nullable\":false},\"target_key\":{\"type\":\"number\",\"nullable\":false}}",
    "[{\"edge_key\":10,\"tenant\":\"a\",\"source_key\":1,\"target_key\":1},{\"edge_key\":11,\"tenant\":\"a\",\"source_key\":1,\"target_key\":1}]",
  )
  let graph_owner = keyed_bridge_owner(
    nodes,
    edges,
    body=Some(
      (
        #|[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["node_key"],"labels":[]}],"edges":[{"name":"E","from":"edges","key":["edge_key","tenant"],"source":{"definition":"N","key":["source_key"]},"target":{"definition":"N","key":["target_key"]},"labels":[{"name":"R","properties":{"mode":"no_properties"}}]}]},"as":"g"}]
      ),
    ),
  )
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("edge Graph construction")
  }
  let restored = property_rows_restore(graph_owner, graph)
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
  assert_true(@graphs.discard_completed(graph))
  assert_false(@graphs.completed_available(graph))
  let owner = keyed_graph_receiver(graph_owner, body="[{\"edge_rows\":true}]")
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, restored).unwrap()
  for viewed in [false, true] {
    let active = if viewed {
      @local_bridge.start_graph_view_to_rows(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        @graphs.producer_read_view(input).unwrap(),
        2,
        property_rows_value_limits(),
        100,
        1000,
      ).unwrap()
    } else {
      @local_bridge.start_graph_to_rows(
        @bounded.control(),
        task_test_completion(owner),
        prepared_sequence(owner),
        0,
        input,
        2,
        property_rows_value_limits(),
        100,
        1000,
        [],
      ).unwrap()
    }
    let output = property_rows_retained_copy(property_rows_terminal(active))
    property_rows_project_identity(owner, output)
    assert_eq(@execution.completed_row_count(output), 2)
    guard @pipeline.carrier_at(
        @lower.pipeline(@lower.bound_preparation(graph_owner)),
        @pipeline.Step(0),
      )
      is Some(@carrier_contract.GraphValue(carrier)) else {
      fail("Graph contract")
    }
    let domain = @carrier_contract.property_graph_domain(
      @carrier_contract.graph_property_definition(carrier),
    )
    // Independent identity preimages derive from the constructor's typed keys,
    // not from the stored element identities or Bridge output.
    let node_identity = "{\"definition\":\"N\",\"domain\":\"" +
      domain +
      "\",\"key\":[1],\"key_types\":[{\"kind\":\"number\"}]}"
    let key = property_rows_column(output, "edge_key")
    let mut ten = 0
    let mut eleven = 0
    for row in 0..<2 {
      let edge_key = match
        @execution.completed_cell(output, row, key).unwrap() {
        @execution.Number(10) => {
          ten += 1
          10
        }
        @execution.Number(11) => {
          eleven += 1
          11
        }
        _ => fail("raw edge key was replaced")
      }
      let edge_identity = "{\"definition\":\"E\",\"domain\":\"" +
        domain +
        "\",\"key\":[" +
        edge_key.to_string() +
        ",\"a\"],\"key_types\":[{\"kind\":\"number\"},{\"kind\":\"string\"}]}"
      assert_eq(
        @execution.completed_output_row_wire(output, row, 10000, 1000, 20).unwrap(),
        "{\"dst\":" +
        property_graph_expected_json_wire(node_identity) +
        ",\"edge_key\":" +
        edge_key.to_string() +
        ",\"id\":" +
        property_graph_expected_json_wire(edge_identity) +
        ",\"labels\":[\"R\"],\"src\":" +
        property_graph_expected_json_wire(node_identity) +
        ",\"tenant\":\"a\"}",
      )
    }
    assert_eq((ten, eleven), (1, 1))
    assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
    assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
  }
  assert_true(@graphs.discard_completed(restored))
}

///|
test "Graph row limits cancellation and input loss never expose partial Relation or lose cleanup" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let graph_owner = keyed_bridge_owner(nodes, edges)
  let construction = @local_bridge.start_rows_to_property_graph(
    @bounded.control(),
    prepared_sequence(graph_owner),
    0,
    keyed_bridge_inputs(graph_owner, nodes, edges),
    carrier_graph_storage_limits(),
    8192L,
    1000,
    () => true,
  ).unwrap()
  guard keyed_bridge_terminal(construction) is @local_bridge.Complete(graph, ..) else {
    fail("resource fixture Graph")
  }
  let owner = keyed_graph_receiver(graph_owner, body="[{\"edge_rows\":true}]")
  let input = @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap()
  for
    (rows, nodes, work, cancel, lost) in [
      (1, 1000, None, false, false),
      (2, 1, None, false, false),
      (2, 1000, Some(2), false, false),
      (2, 1000, None, true, false),
      (2, 1000, None, false, true),
    ] {
    let control = @bounded.control()
    let active = @local_bridge.start_graph_to_rows(
      control,
      task_test_completion(owner),
      prepared_sequence(owner),
      0,
      input,
      rows,
      { ..property_rows_value_limits(), max_nodes: nodes, },
      100,
      1000,
      [],
      control_work_limit=work,
    ).unwrap()
    guard @local_bridge.advance_events_to_rows(active, 1).unwrap()
      is @local_bridge.Continue(work=initial, ..) else {
      fail("initial bounded advance")
    }
    let mut cumulative = initial
    if cancel {
      assert_true(@bounded.request_cancel(control))
    }
    if lost {
      assert_true(@graphs.discard_completed(graph))
    }
    let mut rejected = false
    for _ in 0..<1000 {
      match @local_bridge.advance_events_to_rows(active, 1).unwrap() {
        @local_bridge.Continue(work~, ..) => {
          assert_true(work >= cumulative && work - cumulative <= 1L)
          cumulative = work
        }
        @local_bridge.Stopped(_, ..) => {
          assert_true(cancel)
          rejected = true
          break
        }
        @local_bridge.Failed(issue, ..) => {
          if lost {
            assert_eq(issue, @local_bridge.InputUnavailable)
          }
          if work is Some(_) {
            assert_eq(issue, @local_bridge.ControlWorkLimit)
          }
          rejected = true
          break
        }
        @local_bridge.Complete(_, ..) =>
          fail("partial Graph row result escaped failure")
      }
    }
    assert_true(rejected)
    assert_true(@local_bridge.cleanup_events_to_rows(active).unwrap())
    assert_false(@local_bridge.events_to_rows_cleanup_pending(active))
    assert_false(@local_bridge.cleanup_events_to_rows(active).unwrap())
  }
  assert_true(@local_bridge.cleanup_rows_to_graph(construction).unwrap())
}
