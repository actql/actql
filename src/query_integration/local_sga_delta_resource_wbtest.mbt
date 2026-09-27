///|
/// One graph_diff / apply_graph_delta resource case. Both graphs use
/// self-describing rows: each row is one node (`id`, `node_name`) and one
/// edge (`src` -> `dst`, `weight`). The expected numbers were measured on
/// this fixture and are pinned so any accounting change is visible.
priv struct DeltaResourceCase {
  name : String
  left_rows : String
  right_rows : String
  // Total control work the diff kernel reports to completion.
  diff_work : Int
  // Smallest admitted `ValueLimits.max_work`. The same ceiling also bounds
  // capture of the emitted delta row, which costs more than the kernel's
  // control work on these small graphs, so this is the binding value.
  diff_admitted_work : Int
  // Smallest admitted diff `max_workspace_slots` (combined snapshot,
  // action and update slots admitted by `@diff.prepare`).
  diff_workspace : Int
  // Rendered delta actions (CID fields omitted; apply re-verifies both
  // CIDs through its base and target snapshots).
  delta : String
  // Total control work the apply kernel reports to completion.
  apply_control_work : Int
  // Smallest admitted `Limits.max_work` for output-graph construction; the
  // kernel's control work has its own ceiling (`apply_control_work`).
  apply_work : Int
  // Smallest admitted `Limits.max_workspace_slots` (base snapshot, action
  // scratch, output storage and result snapshot share this budget).
  apply_workspace : Int
  // Rendered result graph content; equals the right-hand graph.
  graph : String
}

///|
fn delta_resource_row(
  id : Int,
  src : Int,
  dst : Int,
  name : String,
  weight : Int,
) -> String {
  "{\"id\":" +
  id.to_string() +
  ",\"src\":" +
  src.to_string() +
  ",\"dst\":" +
  dst.to_string() +
  ",\"node_name\":\"" +
  name +
  "\",\"weight\":" +
  weight.to_string() +
  "}"
}

///|
fn delta_resource_rows(rows : Array[String]) -> String {
  let mut text = "["
  for index, row in rows {
    if index > 0 {
      text += ","
    }
    text += row
  }
  text + "]"
}

///|
fn delta_resource_cases() -> Array[DeltaResourceCase] {
  let base = delta_resource_rows([
    delta_resource_row(1, 1, 1, "a", 10),
    delta_resource_row(2, 2, 2, "b", 20),
  ])
  [
    {
      name: "node property update",
      left_rows: base,
      right_rows: delta_resource_rows([
        delta_resource_row(1, 1, 1, "A", 10),
        delta_resource_row(2, 2, 2, "b", 20),
      ]),
      // One node update: equal work and workspace to the edge update.
      diff_work: 85,
      diff_admitted_work: 402,
      diff_workspace: 72,
      delta: "{edges:{add:[],remove:[],update:[]},nodes:{add:[],remove:[],update:[{after:{id:1,props:{node_name:\"A\"}},before:{id:1,props:{node_name:\"a\"}}}]},version:\"actql-graph-delta/0.1\"}",
      apply_control_work: 72,
      apply_work: 32,
      apply_workspace: 77,
      graph: "nodes[1,\"A\";2,\"b\"] edges[1->1,10;2->2,20]",
    },
    {
      name: "edge property update",
      left_rows: base,
      right_rows: delta_resource_rows([
        delta_resource_row(1, 1, 1, "a", 11),
        delta_resource_row(2, 2, 2, "b", 20),
      ]),
      // One edge update: same action width as the node update.
      diff_work: 85,
      diff_admitted_work: 412,
      diff_workspace: 72,
      delta: "{edges:{add:[],remove:[],update:[{after:{dst:1,props:{weight:11},rel:null,src:1},before:{dst:1,props:{weight:10},rel:null,src:1}}]},nodes:{add:[],remove:[],update:[]},version:\"actql-graph-delta/0.1\"}",
      apply_control_work: 72,
      apply_work: 32,
      apply_workspace: 77,
      graph: "nodes[1,\"a\";2,\"b\"] edges[1->1,11;2->2,20]",
    },
    {
      name: "edge rewire",
      left_rows: base,
      right_rows: delta_resource_rows([
        delta_resource_row(1, 1, 2, "a", 10),
        delta_resource_row(2, 2, 2, "b", 20),
      ]),
      // Edge remove + add: two edge actions cost two more apply units and
      // six more apply slots (remove keeps a temporary actual record).
      diff_work: 85,
      diff_admitted_work: 400,
      diff_workspace: 72,
      delta: "{edges:{add:[{dst:2,props:{weight:10},rel:null,src:1}],remove:[{dst:1,props:{weight:10},rel:null,src:1}],update:[]},nodes:{add:[],remove:[],update:[]},version:\"actql-graph-delta/0.1\"}",
      apply_control_work: 74,
      apply_work: 32,
      apply_workspace: 83,
      graph: "nodes[1,\"a\";2,\"b\"] edges[2->2,20;1->2,10]",
    },
    {
      name: "node and edge addition with removal",
      left_rows: base,
      right_rows: delta_resource_rows([
        delta_resource_row(1, 1, 1, "a", 10),
        delta_resource_row(3, 3, 3, "c", 30),
      ]),
      // Node and edge remove + add: three more diff units for the extra
      // action entries; apply needs 17 more slots than one update.
      diff_work: 88,
      diff_admitted_work: 442,
      diff_workspace: 72,
      delta: "{edges:{add:[{dst:3,props:{weight:30},rel:null,src:3}],remove:[{dst:2,props:{weight:20},rel:null,src:2}],update:[]},nodes:{add:[{id:3,props:{node_name:\"c\"}}],remove:[{id:2,props:{node_name:\"b\"}}],update:[]},version:\"actql-graph-delta/0.1\"}",
      apply_control_work: 77,
      apply_work: 32,
      apply_workspace: 94,
      graph: "nodes[1,\"a\";3,\"c\"] edges[1->1,10;3->3,30]",
    },
  ]
}

///|
/// Built inputs for one case: two source relations, their graphs and the
/// diff owner. `close` releases every construction and checks the source
/// relations survive.
priv struct DeltaResourceFixture {
  diff_owner : @lower.BoundPrepared
  sequence : @lower.PreparedSequence
  inputs : Array[@execution.ProducerRead]
  left_rows : @execution.CompletedOutput
  right_rows : @execution.CompletedOutput
  left_execution : @local_bridge.RowsToGraphExecution
  right_execution : @local_bridge.RowsToGraphExecution
  left : @graphs.Completed
  right : @graphs.Completed
}

///|
fn delta_resource_fixture(
  case : DeltaResourceCase,
) -> DeltaResourceFixture raise {
  let left_owner = carrier_graph_source_owner_with_rows(case.left_rows)
  let right_owner = carrier_graph_source_owner_with_rows(case.right_rows)
  let left_rows = carrier_events_source_output(left_owner)
  let right_rows = carrier_events_source_output(right_owner)
  let diff_owner = carrier_graph_delta_owner(left_owner, right_owner)
  let sequence = prepared_sequence(diff_owner)
  let left_input = @execution.prepare_producer_read(
    diff_owner,
    @execution.bind_completed_input(diff_owner, 0, left_owner, left_rows).unwrap(),
    100,
    1000,
  ).unwrap()
  let right_input = @execution.prepare_producer_read(
    diff_owner,
    @execution.bind_completed_input(diff_owner, 1, right_owner, right_rows).unwrap(),
    100,
    1000,
  ).unwrap()
  let left_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [left_input, left_input],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let left = finish_rows_to_graph(left_execution)
  let right_execution = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    1,
    [right_input, right_input],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let right = finish_rows_to_graph(right_execution)
  {
    diff_owner,
    sequence,
    inputs: [left_input, right_input],
    left_rows,
    right_rows,
    left_execution,
    right_execution,
    left,
    right,
  }
}

///|
fn delta_resource_close(fixture : DeltaResourceFixture) -> Unit raise {
  assert_eq(
    @local_bridge.cleanup_rows_to_graph(fixture.left_execution),
    Ok(true),
  )
  assert_eq(
    @local_bridge.cleanup_rows_to_graph(fixture.right_execution),
    Ok(true),
  )
  assert_true(@graphs.discard_completed(fixture.left))
  assert_true(@graphs.discard_completed(fixture.right))
  assert_true(@execution.completed_output_available(fixture.left_rows))
  assert_true(@execution.completed_output_available(fixture.right_rows))
}

///|
fn delta_resource_start_diff(
  fixture : DeltaResourceFixture,
  control : @bounded.Control,
  max_work : Int,
  workspace : Int,
) -> Result[@local_sga.GraphDiffExecution, @local_sga.GraphDiffIssue] raise {
  @local_sga.start_graph_diff(
    control,
    task_test_completion(fixture.diff_owner),
    fixture.sequence,
    2,
    @graphs.prepare_step_read(fixture.diff_owner, 2, 0, fixture.left).unwrap(),
    @graphs.prepare_step_read(fixture.diff_owner, 2, 1, fixture.right).unwrap(),
    1,
    { max_nodes: 1000, max_text_bytes: 10000, max_depth: 20, max_work, },
    workspace,
    1000,
    1000,
    fixture.inputs,
  )
}

///|
/// Drives a diff with quantum one. Returns the terminal outcome and the
/// cumulative work the kernel reported.
fn delta_resource_run_diff(
  execution : @local_sga.GraphDiffExecution,
) -> (Result[@execution.CompletedOutput, @local_sga.GraphDiffIssue], Int) raise {
  let mut polls = 0
  while true {
    polls += 1
    assert_true(polls < 10000)
    match @local_sga.advance_graph_diff(execution, 1).unwrap() {
      @local_sga.GraphDiffContinue(..) => ()
      @local_sga.GraphDiffComplete(output, work~, ..) =>
        return (Ok(output), work.to_int())
      @local_sga.GraphDiffFailed(issue, work~, ..) =>
        return (Err(issue), work.to_int())
      @local_sga.GraphDiffStopped(_, ..) => fail("graph diff stopped")
    }
  }
  abort("unreachable")
}

///|
fn delta_resource_apply_limits(
  max_work : Int,
  workspace : Int,
) -> @graph_storage.Limits {
  let limits = carrier_graph_storage_limits()
  {
    max_input_rows: limits.max_input_rows,
    max_nodes: limits.max_nodes,
    max_edges: limits.max_edges,
    max_value_bytes: limits.max_value_bytes,
    max_total_value_bytes: limits.max_total_value_bytes,
    max_retained_value_bytes: limits.max_retained_value_bytes,
    max_value_nodes: limits.max_value_nodes,
    max_value_depth: limits.max_value_depth,
    max_contract_work: limits.max_contract_work,
    max_work,
    max_workspace_slots: workspace,
  }
}

///|
fn delta_resource_start_apply(
  fixture : DeltaResourceFixture,
  delta : @execution.CompletedOutput,
  control : @bounded.Control,
  max_work : Int,
  workspace : Int,
  control_work? : Int = 1000000,
) -> Result[@local_sga.GraphApplyExecution, @local_sga.GraphApplyIssue] {
  let apply_owner = carrier_graph_apply_owner(fixture.diff_owner)
  @local_sga.start_graph_apply(
    control,
    prepared_sequence(apply_owner),
    0,
    @graphs.prepare_producer_read(
      apply_owner,
      0,
      fixture.diff_owner,
      fixture.left,
    ).unwrap(),
    @execution.prepare_producer_read(
      apply_owner,
      @execution.bind_completed_input(apply_owner, 1, fixture.diff_owner, delta).unwrap(),
      100,
      1000,
    ).unwrap(),
    delta_resource_apply_limits(max_work, workspace),
    4096L,
    fn() { true },
    control_work_limit=Some(control_work),
  )
}

///|
fn delta_resource_run_apply(
  execution : @local_sga.GraphApplyExecution,
) -> (Result[@graphs.Completed, @local_sga.GraphApplyIssue], Int) raise {
  let mut polls = 0
  while true {
    polls += 1
    assert_true(polls < 10000)
    match @local_sga.advance_graph_apply(execution, 1).unwrap() {
      @local_sga.GraphApplyContinue(..) => ()
      @local_sga.GraphApplyComplete(output, work~, ..) =>
        return (Ok(output), work.to_int())
      @local_sga.GraphApplyFailed(issue, work~, ..) =>
        return (Err(issue), work.to_int())
      @local_sga.GraphApplyStopped(_, ..) => fail("graph apply stopped")
    }
  }
  abort("unreachable")
}

///|
/// Produces the reference delta with generous limits and releases the diff
/// session; the returned output stays readable for apply.
fn delta_resource_reference_delta(
  fixture : DeltaResourceFixture,
) -> (@local_sga.GraphDiffExecution, @execution.CompletedOutput) raise {
  let execution = delta_resource_start_diff(
    fixture,
    @bounded.control(),
    100000,
    100000,
  ).unwrap()
  match delta_resource_run_diff(execution) {
    (Ok(output), _) => (execution, output)
    (Err(issue), _) => {
      ignore(issue)
      fail("reference graph diff failed")
    }
  }
}

///|
fn delta_resource_render(value : @admitted.Value) -> String {
  match value {
    Null => "null"
    Boolean(flag) => flag.to_string()
    Number(number) => number.to_string()
    Text(text) => "\"" + text + "\""
    Date(text) => "date(" + text + ")"
    Timestamp(text) => "timestamp(" + text + ")"
    Array(items) => {
      let mut text = "["
      for index, item in @admitted.elements(items) {
        if index > 0 {
          text += ","
        }
        text += delta_resource_render(item)
      }
      text + "]"
    }
    Object(fields) => {
      let mut text = "{"
      let mut first = true
      for field in @admitted.elements(fields) {
        let (name, item) = field
        // CIDs are hashes; apply re-verifies them through its snapshots.
        if name.has_suffix("_cid") {
          continue
        }
        if !first {
          text += ","
        }
        first = false
        text += name + ":" + delta_resource_render(item)
      }
      text + "}"
    }
    _ => "?"
  }
}

///|
fn delta_resource_delta_text(output : @execution.CompletedOutput) -> String {
  guard @execution.completed_row_count(output) == 1 &&
    @execution.completed_cell(output, 0, 0) is Some(Captured(value)) else {
    return "<missing delta>"
  }
  delta_resource_render(value)
}

///|
fn delta_resource_graph_text(storage : @graph_storage.Storage) -> String {
  let mut text = "nodes["
  for node in 0..<@graph_storage.node_count(storage) {
    if node > 0 {
      text += ";"
    }
    text += match @graph_storage.node_identity(storage, node) {
      Some(identity) => delta_resource_render(identity.value)
      None => "?"
    }
    let mut property = 0
    while @graph_storage.node_property(storage, node, property) is Some(value) {
      text += "," + delta_resource_render(value.value)
      property += 1
    }
  }
  text += "] edges["
  for edge in 0..<@graph_storage.edge_count(storage) {
    if edge > 0 {
      text += ";"
    }
    match @graph_storage.edge_endpoints(storage, edge) {
      Some((source, target)) =>
        text += delta_resource_render(
            @graph_storage.node_identity(storage, source).unwrap().value,
          ) +
          "->" +
          delta_resource_render(
            @graph_storage.node_identity(storage, target).unwrap().value,
          )
      None => text += "?"
    }
    let mut property = 0
    while @graph_storage.edge_property(storage, edge, property) is Some(value) {
      text += "," + delta_resource_render(value.value)
      property += 1
    }
  }
  text + "]"
}

///|
/// Releases an apply session and checks its private action ledger and live
/// scratch reservation returned to zero.
fn delta_resource_cleanup_apply(
  execution : @local_sga.GraphApplyExecution,
) -> Unit raise {
  assert_eq(@local_sga.cleanup_graph_apply(execution), Ok(true))
  assert_eq(@local_sga.graph_apply_private_entry_count(execution), 0)
  let (live_slots, live_bytes, _, _) = @local_sga.graph_apply_private_scratch_usage(
    execution,
  )
  assert_eq((live_slots, live_bytes), (0, 0))
}

///|
/// Checks a completed apply result against the pinned content and the
/// right-hand graph shape, then discards it.
fn delta_resource_check_graph(
  case : DeltaResourceCase,
  fixture : DeltaResourceFixture,
  output : @graphs.Completed,
) -> Unit raise {
  let storage = @graphs.completed_storage(output).unwrap()
  let right = @graphs.completed_storage(fixture.right).unwrap()
  assert_eq(delta_resource_graph_text(storage), case.graph)
  assert_eq(
    @graph_storage.node_count(storage),
    @graph_storage.node_count(right),
  )
  assert_eq(
    @graph_storage.edge_count(storage),
    @graph_storage.edge_count(right),
  )
  assert_true(@graphs.discard_completed(output))
}

///|
test "Graph diff and apply admit exact work and reject one unit short" {
  for case in delta_resource_cases() {
    let fixture = delta_resource_fixture(case)
    // Diff: the exact total control work completes with the pinned delta.
    let exact = delta_resource_start_diff(
      fixture,
      @bounded.control(),
      case.diff_admitted_work,
      100000,
    ).unwrap()
    let delta = match delta_resource_run_diff(exact) {
      (Ok(output), work) => {
        assert_eq(work, case.diff_work)
        assert_eq(delta_resource_delta_text(output), case.delta)
        output
      }
      (Err(_), _) => fail(case.name + ": exact diff work was rejected")
    }
    // One unit short: the kernel finishes, but capturing the delta row
    // exceeds the shared ceiling at the emit step, before completion.
    let short = delta_resource_start_diff(
      fixture,
      @bounded.control(),
      case.diff_admitted_work - 1,
      100000,
    ).unwrap()
    match delta_resource_run_diff(short) {
      (Err(@local_sga.GraphDiffOutput(CaptureLimit)), work) =>
        assert_eq(work, case.diff_work - 1)
      _ => fail(case.name + ": diff ignored its capture work ceiling")
    }
    assert_eq(@local_sga.cleanup_graph_diff(short), Ok(true))
    // The control-work ceiling itself binds at the emit boundary: a ceiling
    // that covers only the kernel stops with no unit left to emit.
    let starved = delta_resource_start_diff(
      fixture,
      @bounded.control(),
      case.diff_work - 2,
      100000,
    ).unwrap()
    match delta_resource_run_diff(starved) {
      (Err(@local_sga.GraphDiffWorkLimit), work) =>
        assert_eq(work, case.diff_work - 2)
      _ => fail(case.name + ": diff ignored its control work ceiling")
    }
    assert_eq(@local_sga.cleanup_graph_diff(starved), Ok(true))
    // Apply: the kernel's control work has its own ceiling, and
    // `Limits.max_work` separately bounds output-graph construction work.
    let applied = delta_resource_start_apply(
      fixture,
      delta,
      @bounded.control(),
      case.apply_work,
      100000,
    ).unwrap()
    match delta_resource_run_apply(applied) {
      (Ok(output), work) => {
        assert_eq(work, case.apply_control_work)
        delta_resource_check_graph(case, fixture, output)
      }
      (Err(_), _) => fail(case.name + ": exact apply work was rejected")
    }
    delta_resource_cleanup_apply(applied)
    let starved = delta_resource_start_apply(
      fixture,
      delta,
      @bounded.control(),
      case.apply_work - 1,
      100000,
    ).unwrap()
    match delta_resource_run_apply(starved) {
      (Err(@local_sga.GraphApplyOutput(@graphs.Storage(WorkLimit))), work) =>
        assert_true(work > 0 && work < case.apply_control_work)
      _ => fail(case.name + ": apply ignored its work ceiling")
    }
    delta_resource_cleanup_apply(starved)
    let exact_control = delta_resource_start_apply(
      fixture,
      delta,
      @bounded.control(),
      100000,
      100000,
      control_work=case.apply_control_work,
    ).unwrap()
    match delta_resource_run_apply(exact_control) {
      (Ok(output), work) => {
        assert_eq(work, case.apply_control_work)
        delta_resource_check_graph(case, fixture, output)
      }
      (Err(_), _) => fail(case.name + ": exact apply control work was rejected")
    }
    delta_resource_cleanup_apply(exact_control)
    let short_control = delta_resource_start_apply(
      fixture,
      delta,
      @bounded.control(),
      100000,
      100000,
      control_work=case.apply_control_work - 1,
    ).unwrap()
    match delta_resource_run_apply(short_control) {
      (Err(@local_sga.GraphApplyWorkLimit), work) =>
        assert_eq(work, case.apply_control_work - 1)
      _ => fail(case.name + ": apply ignored its control work ceiling")
    }
    delta_resource_cleanup_apply(short_control)
    assert_eq(@local_sga.cleanup_graph_diff(exact), Ok(true))
    delta_resource_close(fixture)
  }
}

///|
test "Graph diff and apply admit exact workspace and reject one entry short" {
  for case in delta_resource_cases() {
    let fixture = delta_resource_fixture(case)
    // Diff admits its whole workspace (both snapshots, action and update
    // slots) up front, so one slot short is rejected at start.
    let exact = delta_resource_start_diff(
      fixture,
      @bounded.control(),
      100000,
      case.diff_workspace,
    ).unwrap()
    let delta = match delta_resource_run_diff(exact) {
      (Ok(output), work) => {
        assert_eq(work, case.diff_work)
        assert_eq(delta_resource_delta_text(output), case.delta)
        output
      }
      (Err(_), _) => fail(case.name + ": exact diff workspace was rejected")
    }
    match
      delta_resource_start_diff(
        fixture,
        @bounded.control(),
        100000,
        case.diff_workspace - 1,
      ) {
      Err(@local_sga.GraphDiffCore(WorkspaceLimit)) => ()
      Err(_) => fail(case.name + ": diff reported the wrong workspace issue")
      Ok(execution) => {
        assert_eq(@local_sga.cleanup_graph_diff(execution), Ok(true))
        fail(case.name + ": diff admitted one workspace slot short")
      }
    }
    // Apply shares one slot budget between the base snapshot, action
    // scratch, output storage and the result snapshot; the shortfall is
    // observed while running, after the base snapshot was admitted.
    let applied = delta_resource_start_apply(
      fixture,
      delta,
      @bounded.control(),
      100000,
      case.apply_workspace,
    ).unwrap()
    match delta_resource_run_apply(applied) {
      (Ok(output), work) => {
        assert_eq(work, case.apply_control_work)
        delta_resource_check_graph(case, fixture, output)
      }
      (Err(_), _) => fail(case.name + ": exact apply workspace was rejected")
    }
    delta_resource_cleanup_apply(applied)
    let short = delta_resource_start_apply(
      fixture,
      delta,
      @bounded.control(),
      100000,
      case.apply_workspace - 1,
    ).unwrap()
    match delta_resource_run_apply(short) {
      (Err(@local_sga.GraphApplyWorkspaceLimit), work) =>
        assert_true(work > 0 && work < case.apply_control_work)
      _ => fail(case.name + ": apply admitted one workspace slot short")
    }
    delta_resource_cleanup_apply(short)
    assert_eq(@local_sga.cleanup_graph_diff(exact), Ok(true))
    delta_resource_close(fixture)
  }
}

///|
test "Graph diff and apply cancel after bounded work and clean up" {
  for case in delta_resource_cases() {
    let fixture = delta_resource_fixture(case)
    let (reference, delta) = delta_resource_reference_delta(fixture)
    // Cancel after the first charged unit and on the last unit before
    // completion (diff: after the delta row was staged; apply: after the
    // result graph was built, before its snapshot is verified).
    for cancel_at in [1, case.diff_work - 1] {
      let control = @bounded.control()
      let execution = delta_resource_start_diff(
        fixture, control, 100000, 100000,
      ).unwrap()
      let mut charged = 0
      while charged < cancel_at {
        match @local_sga.advance_graph_diff(execution, 1).unwrap() {
          @local_sga.GraphDiffContinue(work~, ..) => charged = work.to_int()
          _ => fail(case.name + ": diff finished before cancellation")
        }
      }
      assert_eq(charged, cancel_at)
      assert_true(@bounded.request_cancel(control))
      match @local_sga.advance_graph_diff(execution, 1).unwrap() {
        @local_sga.GraphDiffStopped(Cancelled, work~, ..) =>
          assert_eq(work.to_int(), cancel_at)
        _ => fail(case.name + ": diff did not stop on cancellation")
      }
      assert_true(@local_sga.graph_diff_stopped(execution))
      assert_true(@local_sga.graph_diff_cleanup_pending(execution))
      assert_eq(@local_sga.cleanup_graph_diff(execution), Ok(true))
      assert_false(@local_sga.graph_diff_cleanup_pending(execution))
      assert_eq(@local_sga.cleanup_graph_diff(execution), Ok(false))
      // A stopped session publishes nothing and cannot be resumed.
      assert_true(
        @local_sga.advance_graph_diff(execution, 1)
        is Err(@local_sga.GraphDiffExecutionIssue(Terminal)),
      )
    }
    for cancel_at in [1, case.apply_control_work - 1] {
      let control = @bounded.control()
      let execution = delta_resource_start_apply(
        fixture, delta, control, 100000, 100000,
      ).unwrap()
      let mut charged = 0
      while charged < cancel_at {
        match @local_sga.advance_graph_apply(execution, 1).unwrap() {
          @local_sga.GraphApplyContinue(work~, ..) => charged = work.to_int()
          _ => fail(case.name + ": apply finished before cancellation")
        }
      }
      assert_eq(charged, cancel_at)
      assert_true(@bounded.request_cancel(control))
      match @local_sga.advance_graph_apply(execution, 1).unwrap() {
        @local_sga.GraphApplyStopped(Cancelled, work~, ..) =>
          assert_eq(work.to_int(), cancel_at)
        _ => fail(case.name + ": apply did not stop on cancellation")
      }
      assert_true(@local_sga.graph_apply_stopped(execution))
      assert_true(@local_sga.graph_apply_cleanup_pending(execution))
      delta_resource_cleanup_apply(execution)
      assert_false(@local_sga.graph_apply_cleanup_pending(execution))
      assert_eq(@local_sga.cleanup_graph_apply(execution), Ok(false))
      assert_true(
        @local_sga.advance_graph_apply(execution, 1)
        is Err(@local_sga.GraphApplyExecutionIssue(Terminal)),
      )
    }
    // The reference delta and both source graphs remain intact.
    assert_eq(delta_resource_delta_text(delta), case.delta)
    assert_true(@execution.completed_output_available(delta))
    assert_eq(@local_sga.cleanup_graph_diff(reference), Ok(true))
    delta_resource_close(fixture)
  }
}
