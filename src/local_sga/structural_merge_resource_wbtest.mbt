// Independent resource proofs for the nonempty structural Graph merge routes:
// graft_graph (start_graft), finite-list union_graphs and subtract_graphs
// (start_graft_views) and mean_graphs (start_mean_views). One variant table
// drives one runner for every resource dimension.

///|
priv enum SmrRun {
  SmrGraft(GraftExecution)
  SmrMean(MeanExecution)
}

///|
/// Kernel-neutral view of the terminal issue that a limit produces.
priv enum SmrIssue {
  SmrWorkLimit
  SmrWorkspaceLimit
  SmrOutput(@graph.Issue)
  SmrOther
} derive(Eq, Debug)

///|
priv enum SmrPoll {
  SmrContinue(Int64)
  SmrComplete(@graph.Completed, Int64)
  SmrFailed(SmrIssue, Int64)
  SmrStopped(Bool, Int64)
}

///|
/// Output-side budgets enforced by the shared Graph output builder.
priv enum SmrBudget {
  SmrNodes
  SmrEdges
  SmrInputRows
  SmrRetainedBytes
  SmrValueBytes
}

///|
priv struct SmrVariant {
  name : String
  // Cumulative kernel control work reported at completion.
  control_work : Int
  // Output builder construction work. The same `max_work` field bounds it, so
  // the admitted `max_work` is the larger of the two ceilings.
  storage_work : Int
  work_short : SmrIssue
  // Cumulative control work reported by the one-short `max_work` failure.
  work_failed_at : Int
  // Smallest `max_workspace_slots` that completes.
  workspace : Int
  // Slots retained by the completed output builder.
  storage_slots : Int
  workspace_short : SmrIssue
  workspace_failed_at : Int
  // (budget, exact limit, one-short issue, control work at the failure).
  budgets : Array[(SmrBudget, Int, SmrIssue, Int)]
  content : String
  start : (@bounded.Control, @storage.Limits) -> Result[SmrRun, SmrIssue]
}

///|
fn smr_graft_issue(issue : GraftIssue) -> SmrIssue {
  match issue {
    GraftWorkLimit => SmrWorkLimit
    GraftWorkspaceLimit => SmrWorkspaceLimit
    GraftOutput(output) => SmrOutput(output)
    _ => SmrOther
  }
}

///|
fn smr_mean_issue(issue : MeanIssue) -> SmrIssue {
  match issue {
    MeanWorkLimit => SmrWorkLimit
    MeanWorkspaceLimit => SmrWorkspaceLimit
    MeanOutput(output) => SmrOutput(output)
    _ => SmrOther
  }
}

///|
fn smr_advance(run : SmrRun, quantum : Int) -> SmrPoll {
  match run {
    SmrGraft(execution) =>
      match advance_graft(execution, quantum).unwrap() {
        GraftContinue(work~, ..) => SmrContinue(work)
        GraftComplete(output, work~, ..) => SmrComplete(output, work)
        GraftFailed(issue, work~, ..) => SmrFailed(smr_graft_issue(issue), work)
        GraftStopped(reason, work~, ..) =>
          SmrStopped(reason is @bounded.Cancelled, work)
      }
    SmrMean(execution) =>
      match advance_mean(execution, quantum).unwrap() {
        MeanContinue(work~, ..) => SmrContinue(work)
        MeanComplete(output, work~, ..) => SmrComplete(output, work)
        MeanFailed(issue, work~, ..) => SmrFailed(smr_mean_issue(issue), work)
        MeanStopped(reason, work~, ..) =>
          SmrStopped(reason is @bounded.Cancelled, work)
      }
  }
}

///|
fn smr_terminal_rejected(run : SmrRun) -> Bool {
  match run {
    SmrGraft(execution) => advance_graft(execution, 1) is Err(_)
    SmrMean(execution) => advance_mean(execution, 1) is Err(_)
  }
}

///|
fn smr_stopped(run : SmrRun) -> Bool {
  match run {
    SmrGraft(execution) => graft_stopped(execution)
    SmrMean(execution) => mean_stopped(execution)
  }
}

///|
fn smr_cleanup_pending(run : SmrRun) -> Bool {
  match run {
    SmrGraft(execution) => graft_cleanup_pending(execution)
    SmrMean(execution) => mean_cleanup_pending(execution)
  }
}

///|
/// Returns the cleanup result as `Some(reclaimed)` or `None` on an issue.
fn smr_cleanup(run : SmrRun) -> Bool? {
  match run {
    SmrGraft(execution) => cleanup_graft(execution).to_option()
    SmrMean(execution) => cleanup_mean(execution).to_option()
  }
}

///|
/// Drives one unit at a time until the run reaches a terminal poll.
fn smr_drive(run : SmrRun) -> SmrPoll {
  for _ in 0..<10000 {
    match smr_advance(run, 1) {
      SmrContinue(work) => if work < 1L { abort("run made no progress") }
      terminal => return terminal
    }
  }
  abort("run did not terminate")
}

///|
fn smr_base_limits() -> @storage.Limits {
  { ..storage_limits(), max_input_rows: 100, max_nodes: 100, max_edges: 100, }
}

///|
fn smr_with_budget(
  limits : @storage.Limits,
  budget : SmrBudget,
  value : Int,
) -> @storage.Limits {
  match budget {
    SmrNodes => { ..limits, max_nodes: value, }
    SmrEdges => { ..limits, max_edges: value, }
    SmrInputRows => { ..limits, max_input_rows: value, }
    SmrRetainedBytes => { ..limits, max_retained_value_bytes: value, }
    SmrValueBytes => { ..limits, max_total_value_bytes: value, }
  }
}

///|
fn smr_text(value : @value.CheckedValue) -> String {
  match @value.canonical_scalar_text(value, 64) {
    Some(text) => text
    None => "?"
  }
}

///|
/// Renders node identities and properties, then edge endpoints, labels and
/// properties, in retained storage order.
fn smr_content(storage : @storage.Storage) -> String {
  let parts : Array[String] = []
  for index in 0..<@storage.node_count(storage) {
    let values = []
    let mut field = 0
    while @storage.node_property(storage, index, field) is Some(value) {
      values.push(smr_text(value))
      field += 1
    }
    parts.push(
      "n" +
      smr_text(@storage.node_identity(storage, index).unwrap()) +
      "[" +
      values.join(",") +
      "]",
    )
  }
  for index in 0..<@storage.edge_count(storage) {
    let (source, target) = @storage.edge_endpoints(storage, index).unwrap()
    let label = match @storage.edge_label(storage, index) {
      Some(Some(value)) => ":" + smr_text(value)
      _ => ""
    }
    let values = []
    let mut field = 0
    while @storage.edge_property(storage, index, field) is Some(value) {
      values.push(smr_text(value))
      field += 1
    }
    parts.push(
      "e" +
      smr_text(@storage.node_identity(storage, source).unwrap()) +
      ">" +
      smr_text(@storage.node_identity(storage, target).unwrap()) +
      label +
      "[" +
      values.join(",") +
      "]",
    )
  }
  parts.join(" ")
}

///|
fn smr_owner(
  step : String,
  inputs : Array[(String, @lower.BoundPrepared)],
) -> @lower.BoundPrepared {
  bind(
    @pipeline.check_with_evidence(
      cursor(step),
      inputs.map(input => {
        (
          input.0,
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(input.1)),
              @pipeline.Step(0),
            ).unwrap(),
          ),
        )
      }),
      None,
      None,
      {
        max_steps: 10,
        max_work: 10000,
        max_text_bytes: 10000,
        max_nodes: 1000,
        max_tokens: 1000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
/// Builds a one-property (`score`) Graph without labels.
fn smr_graph(
  owner : @lower.BoundPrepared,
  nodes : Array[(Double, Double)],
  edges : Array[(Double, Double, Double)],
  score : (Double) -> @value.CheckedValue,
) -> @graph.Completed {
  let output = @graph.prepare_output(
    owner,
    @pipeline.Step(0),
    @storage.DeclaredNodes,
    storage_limits(),
    4096L,
    fn() { true },
  ).unwrap()
  for node in nodes {
    @graph.append_node(output, number(node.0), [score(node.1)]).unwrap()
  }
  for edge in edges {
    @graph.append_edge(output, number(edge.0), number(edge.1), None, [
      score(edge.2),
    ]).unwrap()
  }
  @graph.finish_output(output).unwrap()
}

///|
fn smr_views(
  owner : @lower.BoundPrepared,
  positioned : Array[(Int, @lower.BoundPrepared, @graph.Completed)],
) -> Array[@lifecycle.ProducerView] {
  positioned.map(input => {
    @graph.producer_read_view(
      @graph.prepare_producer_read(owner, input.0, input.1, input.2).unwrap(),
    ).unwrap()
  })
}

///|
fn smr_start_views(
  owner : @lower.BoundPrepared,
  views : Array[@lifecycle.ProducerView],
) -> (@bounded.Control, @storage.Limits) -> Result[SmrRun, SmrIssue] {
  fn(control, limits) {
    start_graft_views(control, sequence(owner), 0, views, limits, 65536L, fn() {
      true
    })
    .map(run => SmrGraft(run))
    .map_err(smr_graft_issue)
  }
}

///|
fn smr_variants() -> Array[SmrVariant] {
  // Graft: shared node 1/2 and edge 1>2 carry equal payloads (no merge rule).
  let graft_left_owner = numeric_graph_owner()
  let graft_right_owner = numeric_graph_owner()
  let graft = smr_owner(
    "[{\"from\":\"left\",\"graft_graph\":{\"with\":\"right\"}}]",
    [("left", graft_left_owner), ("right", graft_right_owner)],
  )
  let graft_left = smr_graph(
    graft_left_owner,
    [(1.0, 2.0), (2.0, 3.0)],
    [(1.0, 2.0, 5.0)],
    number,
  )
  let graft_right = smr_graph(
    graft_right_owner,
    [(1.0, 2.0), (2.0, 3.0), (3.0, 4.0)],
    [(1.0, 2.0, 5.0), (2.0, 3.0, 6.0)],
    number,
  )
  let graft_reads = [
    @graph.prepare_producer_read(graft, 0, graft_left_owner, graft_left).unwrap(),
    @graph.prepare_producer_read(graft, 1, graft_right_owner, graft_right).unwrap(),
  ]

  // Union over [left, right, left, right]: node sum and edge max per fold.
  let union_left_owner = numeric_graph_owner()
  let union_right_owner = numeric_graph_owner()
  let union = smr_owner(
    "[{\"from\":\"left\",\"union_graphs\":{" +
    "\"with\":[\"right\",\"left\",\"right\"],\"merge\":{" +
    "\"node_properties\":{\"score\":\"number_sum\"}," +
    "\"edge_properties\":{\"score\":\"number_max\"}}}}]",
    [("left", union_left_owner), ("right", union_right_owner)],
  )
  let union_left = smr_graph(
    union_left_owner,
    [(1.0, 2.0), (2.0, 3.0)],
    [(1.0, 2.0, 5.0)],
    number,
  )
  let union_right = smr_graph(
    union_right_owner,
    [(1.0, 10.0), (2.0, 4.0), (3.0, 1.0)],
    [(1.0, 2.0, 7.0), (2.0, 3.0, 6.0)],
    number,
  )
  let union_views = smr_views(union, [
    (0, union_left_owner, union_left),
    (1, union_right_owner, union_right),
    (0, union_left_owner, union_left),
    (1, union_right_owner, union_right),
  ])

  // Subtraction with node min and edge sum retains merged shared identities.
  let subtract_left_owner = numeric_graph_owner()
  let subtract_right_owner = numeric_graph_owner()
  let subtract = smr_owner(
    "[{\"from\":\"left\",\"subtract_graphs\":{\"with\":\"right\"," +
    "\"merge\":{\"node_properties\":{\"score\":\"number_min\"}," +
    "\"edge_properties\":{\"score\":\"number_sum\"}}}}]",
    [("left", subtract_left_owner), ("right", subtract_right_owner)],
  )
  let subtract_left = smr_graph(
    subtract_left_owner,
    [(1.0, 2.0), (2.0, 3.0), (3.0, 9.0)],
    [(1.0, 2.0, 5.0), (2.0, 3.0, 4.0)],
    number,
  )
  let subtract_right = smr_graph(
    subtract_right_owner,
    [(1.0, 6.0), (2.0, 1.0), (4.0, 8.0)],
    [(1.0, 2.0, 7.0), (2.0, 4.0, 3.0)],
    number,
  )
  let subtract_views = smr_views(subtract, [
    (0, subtract_left_owner, subtract_left),
    (1, subtract_right_owner, subtract_right),
  ])

  // Mean with weights [1,2,3], node support 0.5 with a weighted score mean,
  // and edge support 1 with an exact-equal score.
  let mean_owners = [
    mean_numeric_source_owner(),
    mean_numeric_source_owner(),
    mean_numeric_source_owner(),
  ]
  let mean = mean_numeric_policy_owner(
    mean_owners[0],
    mean_owners[1],
    mean_owners[2],
    "exclude",
    "exclude",
  )
  let nullable = (value : Double) => mean_numeric_value(value.to_string())
  let mean_graphs = [
    smr_graph(
      mean_owners[0],
      [(1.0, 6.0), (2.0, 2.0)],
      [(1.0, 2.0, 5.0)],
      nullable,
    ),
    smr_graph(
      mean_owners[1],
      [(1.0, 3.0), (2.0, 2.0), (3.0, 4.0)],
      [(1.0, 2.0, 5.0)],
      nullable,
    ),
    smr_graph(
      mean_owners[2],
      [(1.0, 0.0), (2.0, 8.0), (3.0, 1.0)],
      [(1.0, 2.0, 5.0), (2.0, 3.0, 9.0)],
      nullable,
    ),
  ]
  let mean_views = mean_numeric_views(mean, mean_owners, mean_graphs)

  [
    // Graft: 2 + 3 node records, 1 + 2 edge records, 2 source advances and
    // completion give 11 control units; the builder's 58 construction units
    // bind `max_work` first. 29 slots = 3 nodes x 5 + 2 edges x 7.
    {
      name: "graft",
      control_work: 11,
      storage_work: 58,
      work_short: SmrOutput(@graph.Storage(@storage.WorkLimit)),
      work_failed_at: 8,
      workspace: 29,
      storage_slots: 29,
      workspace_short: SmrOutput(@graph.Storage(@storage.WorkspaceLimit)),
      workspace_failed_at: 8,
      budgets: [
        (SmrNodes, 3, SmrOutput(@graph.Storage(@storage.NodeLimit)), 6),
        (SmrEdges, 2, SmrOutput(@graph.Storage(@storage.EdgeLimit)), 8),
        (SmrInputRows, 8, SmrOutput(@graph.Storage(@storage.InputRowLimit)), 8),
        (
          SmrRetainedBytes,
          44,
          SmrOutput(@graph.Storage(@storage.RetainedValueLimit)),
          8,
        ),
        (SmrValueBytes, 87, SmrOutput(@graph.Storage(@storage.ValueLimit)), 8),
      ],
      content: "n1[2] n2[3] n3[4] e1>2[5] e2>3[6]",
      start: fn(control, limits) {
        start_graft(control, sequence(graft), 0, graft_reads, limits, 65536L, fn() {
          true
        })
        .map(run => SmrGraft(run))
        .map_err(smr_graft_issue)
      },
    },
    // Union over four positions: 16 records, 4 source advances and completion
    // give 21 control units; 116 construction units bind `max_work`. The
    // repeated right position contributes twice: node 1 = 2 + 10 + 2 + 10.
    {
      name: "union",
      control_work: 21,
      storage_work: 116,
      work_short: SmrOutput(@graph.Storage(@storage.WorkLimit)),
      work_failed_at: 18,
      workspace: 29,
      storage_slots: 29,
      workspace_short: SmrOutput(@graph.Storage(@storage.WorkspaceLimit)),
      workspace_failed_at: 8,
      budgets: [
        (SmrNodes, 3, SmrOutput(@graph.Storage(@storage.NodeLimit)), 6),
        (SmrEdges, 2, SmrOutput(@graph.Storage(@storage.EdgeLimit)), 8),
        (
          SmrInputRows,
          16,
          SmrOutput(@graph.Storage(@storage.InputRowLimit)),
          18,
        ),
        (
          SmrRetainedBytes,
          46,
          SmrOutput(@graph.Storage(@storage.RetainedValueLimit)),
          8,
        ),
        (SmrValueBytes, 178, SmrOutput(@graph.Storage(@storage.ValueLimit)), 18),
      ],
      content: "n1[24] n2[14] n3[2] e1>2[7] e2>3[6]",
      start: smr_start_views(union, union_views),
    },
    // Subtraction: 5 left records merged or retained, 5 right records passed
    // through the observed shared path, 2 phase ends and completion give 13
    // control units; 58 construction units bind `max_work`. Node 4 is
    // right-only and never admitted; edge 2>4 closes on a missing endpoint.
    {
      name: "subtract",
      control_work: 13,
      storage_work: 58,
      work_short: SmrOutput(@graph.Storage(@storage.WorkLimit)),
      work_failed_at: 4,
      workspace: 29,
      storage_slots: 29,
      workspace_short: SmrOutput(@graph.Storage(@storage.WorkspaceLimit)),
      workspace_failed_at: 4,
      budgets: [
        (SmrNodes, 3, SmrOutput(@graph.Storage(@storage.NodeLimit)), 2),
        (SmrEdges, 2, SmrOutput(@graph.Storage(@storage.EdgeLimit)), 4),
        (SmrInputRows, 8, SmrOutput(@graph.Storage(@storage.InputRowLimit)), 4),
        (
          SmrRetainedBytes,
          45,
          SmrOutput(@graph.Storage(@storage.RetainedValueLimit)),
          4,
        ),
        (SmrValueBytes, 88, SmrOutput(@graph.Storage(@storage.ValueLimit)), 4),
      ],
      content: "n1[2] n2[1] n3[9] e1>2[12] e2>3[4]",
      start: smr_start_views(subtract, subtract_views),
    },
    // Mean: 73 control units exceed the builder's 26 construction units, so
    // `max_work` rejects with the kernel's own work limit. The kernel's
    // workspace counter peaks at 25 (3 inputs + 1 property, 3 slots per
    // node, 5 per edge and sort buffers) above the builder's 22 slots.
    // Node 3 = (4 x 2 + 1 x 3) / 5; edge 2>3 misses the full edge support.
    {
      name: "mean",
      control_work: 73,
      storage_work: 26,
      work_short: SmrWorkLimit,
      work_failed_at: 72,
      workspace: 25,
      storage_slots: 22,
      workspace_short: SmrWorkspaceLimit,
      workspace_failed_at: 57,
      budgets: [
        (SmrNodes, 3, SmrOutput(@graph.Storage(@storage.NodeLimit)), 49),
        (SmrEdges, 1, SmrOutput(@graph.Storage(@storage.EdgeLimit)), 68),
        (SmrInputRows, 4, SmrOutput(@graph.Storage(@storage.InputRowLimit)), 68),
        (
          SmrRetainedBytes,
          33,
          SmrOutput(@graph.Storage(@storage.RetainedValueLimit)),
          68,
        ),
        (SmrValueBytes, 39, SmrOutput(@graph.Storage(@storage.ValueLimit)), 68),
      ],
      content: "n1[2] n2[5] n3[2.2] e1>2[5]",
      start: fn(control, limits) {
        start_mean_views(
          control,
          sequence(mean),
          0,
          mean_views,
          limits,
          65536L,
          4096,
          fn() { true },
        )
        .map(run => SmrMean(run))
        .map_err(smr_mean_issue)
      },
    },
  ]
}

///|
fn smr_start(variant : SmrVariant, limits : @storage.Limits) -> SmrRun {
  match (variant.start)(@bounded.control(), limits) {
    Ok(run) => run
    Err(_) => abort(variant.name + " did not start")
  }
}

///|
/// Asserts that the run completes with the variant's exact Graph content and
/// cleans up, returning the observed amount of `budget` before discarding.
fn smr_expect_complete(
  variant : SmrVariant,
  limits : @storage.Limits,
  budget? : SmrBudget = SmrNodes,
) -> Int raise {
  let run = smr_start(variant, limits)
  guard smr_drive(run) is SmrComplete(output, work) else {
    fail(variant.name + " did not complete at its exact limit")
  }
  assert_eq(work, variant.control_work.to_int64())
  let storage = @graph.completed_storage(output).unwrap()
  assert_eq(smr_content(storage), variant.content)
  assert_eq(@storage.construction_work(storage), variant.storage_work)
  assert_eq(@storage.retained_workspace_slots(storage), variant.storage_slots)
  let observed = match budget {
    SmrNodes => @storage.node_count(storage)
    SmrEdges => @storage.edge_count(storage)
    SmrInputRows => @storage.input_row_count(storage)
    SmrRetainedBytes => @storage.retained_value_bytes(storage)
    SmrValueBytes => @storage.measured_input_value_bytes(storage)
  }
  assert_true(smr_stopped(run))
  assert_eq(smr_cleanup(run), Some(true))
  assert_true(@graph.discard_completed(output))
  observed
}

///|
fn smr_expect_failure(
  variant : SmrVariant,
  limits : @storage.Limits,
  issue : SmrIssue,
  failed_at : Int,
) -> Unit raise {
  let run = smr_start(variant, limits)
  guard smr_drive(run) is SmrFailed(actual, work) else {
    fail(variant.name + " completed one unit short")
  }
  assert_eq(actual, issue)
  assert_eq(work, failed_at.to_int64())
  assert_true(smr_stopped(run))
  assert_eq(smr_cleanup(run), Some(true))
  assert_false(smr_cleanup_pending(run))
}

///|
test "structural Graph merges admit exact work and reject one unit short" {
  for variant in smr_variants() {
    let exact = Int::max(variant.control_work, variant.storage_work)
    ignore(
      smr_expect_complete(variant, { ..smr_base_limits(), max_work: exact, }),
    )
    smr_expect_failure(
      variant,
      { ..smr_base_limits(), max_work: exact - 1, },
      variant.work_short,
      variant.work_failed_at,
    )
    // Control work is also exact on its own: a single poll one unit short
    // continues, and the next unit completes.
    let run = smr_start(variant, smr_base_limits())
    guard smr_advance(run, variant.control_work - 1) is SmrContinue(work) else {
      fail(variant.name + " completed one control unit short")
    }
    assert_eq(work, (variant.control_work - 1).to_int64())
    guard smr_advance(run, 1) is SmrComplete(output, work) else {
      fail(variant.name + " did not complete on its last control unit")
    }
    assert_eq(work, variant.control_work.to_int64())
    assert_eq(
      smr_content(@graph.completed_storage(output).unwrap()),
      variant.content,
    )
    assert_eq(smr_cleanup(run), Some(true))
    assert_true(@graph.discard_completed(output))
  }
}

///|
test "structural Graph merges admit exact workspace and reject one entry short" {
  for variant in smr_variants() {
    ignore(
      smr_expect_complete(variant, {
        ..smr_base_limits(),
        max_workspace_slots: variant.workspace,
      }),
    )
    smr_expect_failure(
      variant,
      { ..smr_base_limits(), max_workspace_slots: variant.workspace - 1, },
      variant.workspace_short,
      variant.workspace_failed_at,
    )
  }
}

///|
test "structural Graph merges admit exact output budgets and reject one short" {
  for variant in smr_variants() {
    assert_eq(variant.budgets.length(), 5)
    for budget in variant.budgets {
      let (kind, exact, issue, failed_at) = budget
      let observed = smr_expect_complete(
        variant,
        smr_with_budget(smr_base_limits(), kind, exact),
        budget=kind,
      )
      assert_eq(observed, exact)
      smr_expect_failure(
        variant,
        smr_with_budget(smr_base_limits(), kind, exact - 1),
        issue,
        failed_at,
      )
    }
  }
}

///|
test "structural Graph merges cancel after bounded work and clean up" {
  for variant in smr_variants() {
    let control = @bounded.control()
    let run = match (variant.start)(control, smr_base_limits()) {
      Ok(run) => run
      Err(_) => fail(variant.name + " did not start")
    }
    let before = variant.control_work / 2
    assert_true(before > 0)
    for unit in 1..<=before {
      guard smr_advance(run, 1) is SmrContinue(work) else {
        fail(variant.name + " stopped before cancellation")
      }
      assert_eq(work, unit.to_int64())
    }
    assert_false(smr_stopped(run))
    assert_true(@bounded.request_cancel(control))
    guard smr_advance(run, variant.control_work) is SmrStopped(cancelled, work) else {
      fail(variant.name + " did not stop after cancellation")
    }
    assert_true(cancelled)
    assert_eq(work, before.to_int64())
    // Nothing is published: the session is terminal and rejects further polls.
    assert_true(smr_stopped(run))
    assert_true(smr_terminal_rejected(run))
    assert_true(smr_cleanup_pending(run))
    assert_eq(smr_cleanup(run), Some(true))
    assert_false(smr_cleanup_pending(run))
    assert_eq(smr_cleanup(run), Some(false))
  }
}
