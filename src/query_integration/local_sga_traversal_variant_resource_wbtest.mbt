// Fixed exact/one-short WORK and WORKSPACE proofs, plus cancellation and
// cleanup proofs, for the registered SGA `traverse` (start_traverse) and
// `shortest_path` (start_shortest) variants the Local provider executes.
// One variant table drives one runner; each test selects one family.
//
// Work ceilings. `start_shortest` takes a separate `control_work_limit`, so
// its ceiling is exactly the charged control work. `start_traverse` has one
// ceiling, `ValueLimits.max_work`, which seeds three independent counters:
// control work, predicate evaluation work and output capture work. Where
// predicate or capture work is the binding counter the minimal admitting
// ceiling exceeds the charged control work, and one unit short fails in that
// counter; the table records both the ceiling and the charged control work.
//
// Workspace. The path kernel keeps a private ledger whose peak equals the
// exact workspace. The node (reach) kernel and the shortest kernel admit one
// fixed reservation before allocation and expose no private ledger, so one
// slot short is refused by admission, except when endpoint or start
// predicates need binding slots beyond that reservation: those bindings are
// reserved on first evaluation and fail as a predicate workspace issue.

///|
priv enum SgaVariantKind {
  SgaTraverse
  SgaShortest
} derive(Eq)

///|
priv enum SgaVariantIssue {
  SgaTraverseIssue(@local_sga.TraverseIssue)
  SgaShortestIssue(@local_sga.ShortestIssue)
} derive(Eq, Debug)

///|
priv struct SgaVariant {
  name : String
  kind : SgaVariantKind
  // Source rows. Each row contributes one node (`id`) and one edge.
  rows : String
  // Labeled sources carry an edge `rel` column instead of `node_name`.
  labeled : Bool
  // Selector Relations as (input name, `key` rows), bound after `rows`.
  selectors : Array[(String, String)]
  // The operation body placed after `"from":"graph",`.
  operation : String
  // Exact canonical output rows.
  expected : Array[String]
  // Minimal admitting work ceiling and the control work it charges.
  ceiling : Int
  work : Int
  // Issue and charged control work one ceiling unit short.
  work_short : SgaVariantIssue
  work_short_at : Int
  // Exact workspace slots and the issue one slot short, raised either by
  // admission (`workspace_short_at_start`) or during execution.
  workspace : Int
  workspace_short : SgaVariantIssue
  workspace_short_at_start : Bool
  // True when the kernel exposes a private entry and slot ledger.
  ledger : Bool
}

///|
let sga_variant_long : String = "w".repeat(200)

///|
/// Five nodes: 1->2, 2->3, 1->3, 3->4, 4->5. The 1->3 weight makes the
/// weighted shortest path differ from the fewest-hop path.
fn sga_variant_chain_rows(prefix? : String = "") -> String {
  "[{\"id\":1,\"src\":1,\"dst\":2,\"node_name\":\"" +
  prefix +
  "one\",\"weight\":10}," +
  "{\"id\":2,\"src\":2,\"dst\":3,\"node_name\":\"" +
  prefix +
  "two\",\"weight\":20}," +
  "{\"id\":3,\"src\":1,\"dst\":3,\"node_name\":\"" +
  prefix +
  "three\",\"weight\":35}," +
  "{\"id\":4,\"src\":3,\"dst\":4,\"node_name\":\"" +
  prefix +
  "four\",\"weight\":40}," +
  "{\"id\":5,\"src\":4,\"dst\":5,\"node_name\":\"" +
  prefix +
  "five\",\"weight\":50}]"
}

///|
/// Five nodes where the start named `second` reaches two `first` nodes and
/// one filtered `third` node through edges heavier than ten.
fn sga_variant_pattern_rows() -> String {
  "[{\"id\":1,\"src\":1,\"dst\":2,\"node_name\":\"first\",\"weight\":10}," +
  "{\"id\":2,\"src\":2,\"dst\":1,\"node_name\":\"second\",\"weight\":20}," +
  "{\"id\":3,\"src\":2,\"dst\":3,\"node_name\":\"third\",\"weight\":30}," +
  "{\"id\":4,\"src\":3,\"dst\":4,\"node_name\":\"fourth\",\"weight\":40}," +
  "{\"id\":5,\"src\":2,\"dst\":5,\"node_name\":\"first\",\"weight\":50}]"
}

///|
/// The chain topology with typed edges; 1->3 and 4->5 are `blocks`.
fn sga_variant_labeled_rows() -> String {
  "[{\"id\":1,\"src\":1,\"dst\":2,\"rel\":\"owns\",\"weight\":10}," +
  "{\"id\":2,\"src\":2,\"dst\":3,\"rel\":\"owns\",\"weight\":20}," +
  "{\"id\":3,\"src\":1,\"dst\":3,\"rel\":\"blocks\",\"weight\":30}," +
  "{\"id\":4,\"src\":3,\"dst\":4,\"rel\":\"owns\",\"weight\":40}," +
  "{\"id\":5,\"src\":4,\"dst\":5,\"rel\":\"blocks\",\"weight\":50}]"
}

///|
fn sga_variant_traverse_body(
  start : String,
  emission : String,
  minimum : Int,
  maximum : Int,
  extra? : String = "",
) -> String {
  "\"traverse\":{\"start\":" +
  start +
  ",\"direction\":\"out\",\"min_hops\":" +
  minimum.to_string() +
  ",\"max_hops\":" +
  maximum.to_string() +
  extra +
  ",\"emit\":\"" +
  emission +
  "\",\"max_output_rows\":10}"
}

///|
fn sga_variant_pattern_body(emission : String) -> String {
  "\"traverse\":{\"start\":{\"where\":\"node_name = 'second'\"}," +
  "\"hops\":[{\"direction\":\"out\",\"edge_where\":\"weight > 10\"," +
  "\"node_where\":\"node_name = 'first'\"}],\"emit\":\"" +
  emission +
  "\",\"max_output_rows\":10}"
}

///|
fn sga_variant_shortest_body(
  source : String,
  target : String,
  extra? : String = "",
  direction? : String = "out",
) -> String {
  "\"shortest_path\":{\"source\":" +
  source +
  ",\"target\":" +
  target +
  extra +
  ",\"direction\":\"" +
  direction +
  "\",\"max_hops\":3,\"max_output_rows\":10}"
}

///|
fn sga_variant_node_row(start : Int, node : Int, depth : Int) -> String {
  "{\"depth\":" +
  depth.to_string() +
  ",\"node_id\":" +
  node.to_string() +
  ",\"start_id\":" +
  start.to_string() +
  "}"
}

///|
/// Edge identities along a forward path, as the kernels encode them.
fn sga_variant_edges(nodes : Array[Int], labeled : Bool) -> String {
  let edges = StringBuilder()
  for index in 1..<nodes.length() {
    if index > 1 {
      edges.write_string(",")
    }
    edges.write_string(
      "{\"dst\":" +
      nodes[index].to_string() +
      ",\"rel\":" +
      (if labeled { "\"owns\"" } else { "null" }) +
      ",\"src\":" +
      nodes[index - 1].to_string() +
      "}",
    )
  }
  "[" + edges.to_string() + "]"
}

///|
fn sga_variant_path_row(nodes : Array[Int], labeled? : Bool = false) -> String {
  "{\"edge_ids\":" +
  sga_variant_edges(nodes, labeled) +
  ",\"end_id\":" +
  nodes[nodes.length() - 1].to_string() +
  ",\"hop_count\":" +
  (nodes.length() - 1).to_string() +
  ",\"node_ids\":[" +
  nodes.map(value => value.to_string()).join(",") +
  "],\"start_id\":" +
  nodes[0].to_string() +
  "}"
}

///|
fn sga_variant_shortest_row(
  nodes : Array[Int],
  cost? : Int = nodes.length() - 1,
  labeled? : Bool = false,
) -> String {
  "{\"edge_ids\":" +
  sga_variant_edges(nodes, labeled) +
  ",\"hop_count\":" +
  (nodes.length() - 1).to_string() +
  ",\"node_ids\":[" +
  nodes.map(value => value.to_string()).join(",") +
  "],\"source_id\":" +
  nodes[0].to_string() +
  ",\"target_id\":" +
  nodes[nodes.length() - 1].to_string() +
  ",\"total_cost\":" +
  cost.to_string() +
  "}"
}

///|
fn sga_traverse_variant(
  name : String,
  rows : String,
  operation : String,
  expected : Array[String],
  ceiling~ : Int,
  work~ : Int,
  work_short~ : @local_sga.TraverseIssue,
  work_short_at~ : Int,
  workspace~ : Int,
  workspace_short~ : @local_sga.TraverseIssue,
  workspace_short_at_start~ : Bool,
  ledger~ : Bool,
  labeled? : Bool = false,
  selectors? : Array[(String, String)] = [],
) -> SgaVariant {
  {
    name,
    kind: SgaTraverse,
    rows,
    labeled,
    selectors,
    operation,
    expected,
    ceiling,
    work,
    work_short: SgaTraverseIssue(work_short),
    work_short_at,
    workspace,
    workspace_short: SgaTraverseIssue(workspace_short),
    workspace_short_at_start,
    ledger,
  }
}

///|
/// The shortest ceiling is the charged control work, and one unit short
/// always fails in the control counter one unit before completion.
fn sga_shortest_variant(
  name : String,
  rows : String,
  operation : String,
  expected : Array[String],
  work~ : Int,
  workspace~ : Int,
  workspace_short? : @local_sga.ShortestIssue = @local_sga.ShortestWorkspaceLimit,
  workspace_short_at_start? : Bool = true,
  labeled? : Bool = false,
  selectors? : Array[(String, String)] = [],
) -> SgaVariant {
  {
    name,
    kind: SgaShortest,
    rows,
    labeled,
    selectors,
    operation,
    expected,
    ceiling: work,
    work,
    work_short: SgaShortestIssue(@local_sga.ShortestWorkLimit),
    work_short_at: work - 1,
    workspace,
    workspace_short: SgaShortestIssue(workspace_short),
    workspace_short_at_start,
    ledger: false,
  }
}

///|
/// The single variant table. Every number was measured on the fixed graphs
/// above and is identical on JS, Wasm and native.
fn sga_variants() -> Array[SgaVariant] {
  let chain = sga_variant_chain_rows()
  let wide = sga_variant_chain_rows(prefix=sga_variant_long)
  let pattern = sga_variant_pattern_rows()
  let labeled = sga_variant_labeled_rows()
  let reach_work = @local_sga.TraverseReachIssue(@local_sga.ReachWorkLimit)
  let reach_space = @local_sga.TraverseReachIssue(
    @local_sga.ReachWorkspaceLimit,
  )
  let reach_predicate_work = @local_sga.TraverseReachIssue(
    @local_sga.ReachPredicate(@execution.ControlLimit),
  )
  let reach_predicate_space = @local_sga.TraverseReachIssue(
    @local_sga.ReachPredicate(@execution.WorkspaceLimit),
  )
  let paths_work = @local_sga.TraversePathIssue(
    @local_sga.TraversePathsWorkLimit,
  )
  let paths_space = @local_sga.TraversePathIssue(
    @local_sga.TraversePathsWorkspaceLimit,
  )
  let paths_capture = @local_sga.TraversePathIssue(
    @local_sga.TraversePathsOutput(@execution.CaptureLimit),
  )
  let paths_predicate_work = @local_sga.TraversePathIssue(
    @local_sga.TraversePathsPredicate(@execution.ControlLimit),
  )
  let literal = "{\"ids\":[1]}"
  let relation = "{\"from\":\"selected\",\"id\":\"key\"}"
  let starts = [("selected", "[{\"key\":3},{\"key\":2},{\"key\":3}]")]
  let predicate = "{\"where\":\"node_name = 'two'\"}"
  let wide_predicate = "{\"where\":\"node_name = '" +
    sga_variant_long +
    "two'\"}"
  let types = ",\"edge_types\":[\"owns\"]"
  let each_pair = ",\"selection\":\"each_pair\""
  let predicate_rows = [
    sga_variant_node_row(2, 3, 1),
    sga_variant_node_row(2, 4, 2),
  ]
  let predicate_paths = [
    sga_variant_path_row([2, 3]),
    sga_variant_path_row([2, 3, 4]),
  ]
  [
    // Reach kernel: control work is the binding counter; 80 slots admitted.
    sga_traverse_variant(
      "literal start node emission",
      chain,
      sga_variant_traverse_body(literal, "nodes", 1, 2),
      [
        sga_variant_node_row(1, 2, 1),
        sga_variant_node_row(1, 3, 1),
        sga_variant_node_row(1, 4, 2),
      ],
      ceiling=84,
      work=84,
      work_short=reach_work,
      work_short_at=83,
      workspace=80,
      workspace_short=reach_space,
      workspace_short_at_start=true,
      ledger=false,
    ),
    // Path kernel: four path rows make output capture the binding counter.
    sga_traverse_variant(
      "literal start path emission",
      chain,
      sga_variant_traverse_body(literal, "paths", 1, 2),
      [
        sga_variant_path_row([1, 2]),
        sga_variant_path_row([1, 3]),
        sga_variant_path_row([1, 2, 3]),
        sga_variant_path_row([1, 3, 4]),
      ],
      ceiling=268,
      work=101,
      work_short=paths_capture,
      work_short_at=100,
      workspace=26,
      workspace_short=paths_space,
      workspace_short_at_start=false,
      ledger=true,
    ),
    // Minimum depth two runs node emission through the path kernel.
    sga_traverse_variant(
      "literal start minimum-depth node emission",
      chain,
      sga_variant_traverse_body(literal, "nodes", 2, 2),
      [sga_variant_node_row(1, 3, 2), sga_variant_node_row(1, 4, 2)],
      ceiling=77,
      work=77,
      work_short=paths_work,
      work_short_at=76,
      workspace=30,
      workspace_short=paths_space,
      workspace_short_at_start=false,
      ledger=true,
    ),
    // Duplicate selector keys are deduplicated into starts 2 and 3.
    sga_traverse_variant(
      "Relation start node emission",
      chain,
      sga_variant_traverse_body(relation, "nodes", 1, 2),
      [
        sga_variant_node_row(2, 3, 1),
        sga_variant_node_row(2, 4, 2),
        sga_variant_node_row(3, 4, 1),
        sga_variant_node_row(3, 5, 2),
      ],
      ceiling=98,
      work=98,
      work_short=reach_work,
      work_short_at=97,
      workspace=80,
      workspace_short=reach_space,
      workspace_short_at_start=true,
      ledger=false,
      selectors=starts,
    ),
    sga_traverse_variant(
      "Relation start path emission",
      chain,
      sga_variant_traverse_body(relation, "paths", 1, 2),
      [
        sga_variant_path_row([2, 3]),
        sga_variant_path_row([2, 3, 4]),
        sga_variant_path_row([3, 4]),
        sga_variant_path_row([3, 4, 5]),
      ],
      ceiling=268,
      work=105,
      work_short=paths_capture,
      work_short_at=104,
      workspace=21,
      workspace_short=paths_space,
      workspace_short_at_start=false,
      ledger=true,
      selectors=starts,
    ),
    // Start predicate evaluation work binds before control work.
    sga_traverse_variant(
      "predicate start node emission",
      chain,
      sga_variant_traverse_body(predicate, "nodes", 1, 2),
      predicate_rows,
      ceiling=109,
      work=103,
      work_short=reach_predicate_work,
      work_short_at=45,
      workspace=83,
      workspace_short=reach_predicate_space,
      workspace_short_at_start=false,
      ledger=false,
    ),
    sga_traverse_variant(
      "predicate start path emission",
      chain,
      sga_variant_traverse_body(predicate, "paths", 1, 2),
      predicate_paths,
      ceiling=134,
      work=96,
      work_short=paths_capture,
      work_short_at=95,
      workspace=22,
      workspace_short=paths_space,
      workspace_short_at_start=false,
      ledger=true,
    ),
    // Hop node and edge predicates keep 1 and 5 and filter node 3.
    sga_traverse_variant(
      "hop node and edge predicate node emission",
      pattern,
      sga_variant_pattern_body("nodes"),
      [sga_variant_node_row(2, 1, 1), sga_variant_node_row(2, 5, 1)],
      ceiling=243,
      work=153,
      work_short=reach_predicate_work,
      work_short_at=136,
      workspace=84,
      workspace_short=reach_predicate_space,
      workspace_short_at_start=false,
      ledger=false,
    ),
    sga_traverse_variant(
      "hop node and edge predicate path emission",
      pattern,
      sga_variant_pattern_body("paths"),
      [sga_variant_path_row([2, 1]), sga_variant_path_row([2, 5])],
      ceiling=243,
      work=140,
      work_short=paths_predicate_work,
      work_short_at=114,
      workspace=20,
      workspace_short=paths_space,
      workspace_short_at_start=false,
      ledger=true,
    ),
    // 203-byte names: predicate work grows with width (109 -> 2109) while
    // control work and workspace match the narrow predicate variants.
    sga_traverse_variant(
      "long-text predicate start node emission",
      wide,
      sga_variant_traverse_body(wide_predicate, "nodes", 1, 2),
      predicate_rows,
      ceiling=2109,
      work=103,
      work_short=reach_predicate_work,
      work_short_at=45,
      workspace=83,
      workspace_short=reach_predicate_space,
      workspace_short_at_start=false,
      ledger=false,
    ),
    sga_traverse_variant(
      "long-text predicate start path emission",
      wide,
      sga_variant_traverse_body(wide_predicate, "paths", 1, 2),
      predicate_paths,
      ceiling=2109,
      work=96,
      work_short=paths_predicate_work,
      work_short_at=45,
      workspace=22,
      workspace_short=paths_space,
      workspace_short_at_start=false,
      ledger=true,
    ),
    // The `blocks` edge 1->3 is excluded, so 3 is reached at depth two.
    sga_traverse_variant(
      "edge type filtered node emission",
      labeled,
      sga_variant_traverse_body(literal, "nodes", 1, 2, extra=types),
      [sga_variant_node_row(1, 2, 1), sga_variant_node_row(1, 3, 2)],
      ceiling=74,
      work=74,
      work_short=reach_work,
      work_short_at=73,
      workspace=80,
      workspace_short=reach_space,
      workspace_short_at_start=true,
      ledger=false,
      labeled=true,
    ),
    sga_traverse_variant(
      "edge type filtered path emission",
      labeled,
      sga_variant_traverse_body(literal, "paths", 1, 2, extra=types),
      [
        sga_variant_path_row([1, 2], labeled=true),
        sga_variant_path_row([1, 2, 3], labeled=true),
      ],
      ceiling=146,
      work=61,
      work_short=paths_capture,
      work_short_at=60,
      workspace=20,
      workspace_short=paths_space,
      workspace_short_at_start=false,
      ledger=true,
      labeled=true,
    ),
    // Shortest workspace follows 14 slots per node and 4 per edge (19 and
    // 6 when weighted, doubled edges when bidirectional, 2 more per node
    // for nearest selections) plus the larger value buffer.
    sga_shortest_variant(
      "scalar unweighted",
      chain,
      sga_variant_shortest_body("1", "4"),
      [sga_variant_shortest_row([1, 3, 4])],
      work=102,
      workspace=111,
    ),
    sga_shortest_variant(
      "scalar weighted",
      chain,
      sga_variant_shortest_body("1", "4", extra=",\"weight\":\"weight\""),
      [sga_variant_shortest_row([1, 2, 3, 4], cost=70)],
      work=116,
      workspace=146,
    ),
    sga_shortest_variant(
      "scalar bidirectional",
      chain,
      sga_variant_shortest_body("4", "1", direction="both"),
      [
        "{\"edge_ids\":[{\"dst\":4,\"rel\":null,\"src\":3}," +
        "{\"dst\":3,\"rel\":null,\"src\":1}],\"hop_count\":2," +
        "\"node_ids\":[4,3,1],\"source_id\":4,\"target_id\":1," +
        "\"total_cost\":2}",
      ],
      work=157,
      workspace=131,
    ),
    sga_shortest_variant(
      "literal identity sets each pair",
      chain,
      sga_variant_shortest_body(
        "{\"ids\":[2,1]}",
        "{\"ids\":[4,3]}",
        extra=each_pair,
      ),
      [
        sga_variant_shortest_row([1, 3]),
        sga_variant_shortest_row([1, 3, 4]),
        sga_variant_shortest_row([2, 3]),
        sga_variant_shortest_row([2, 3, 4]),
      ],
      work=195,
      workspace=111,
    ),
    sga_shortest_variant(
      "literal identity sets nearest per source",
      chain,
      sga_variant_shortest_body(
        "{\"ids\":[2,1]}",
        "{\"ids\":[5,4]}",
        extra=",\"selection\":\"nearest_per_source\"",
      ),
      [sga_variant_shortest_row([1, 3, 4]), sga_variant_shortest_row([2, 3, 4])],
      work=197,
      workspace=121,
    ),
    sga_shortest_variant(
      "literal identity sets nearest pair",
      chain,
      sga_variant_shortest_body(
        "{\"ids\":[2,1]}",
        "{\"ids\":[5,4]}",
        extra=",\"selection\":\"nearest_pair\"",
      ),
      [sga_variant_shortest_row([1, 3, 4])],
      work=185,
      workspace=121,
    ),
    // Endpoint predicate bindings are reserved on first evaluation.
    sga_shortest_variant(
      "predicate endpoints",
      chain,
      sga_variant_shortest_body(
        "{\"where\":\"node_name = 'one'\"}",
        "{\"where\":\"node_name = 'four'\"}",
        extra=each_pair,
      ),
      [sga_variant_shortest_row([1, 3, 4])],
      work=180,
      workspace=114,
      workspace_short=@local_sga.ShortestPredicate(@execution.WorkspaceLimit),
      workspace_short_at_start=false,
    ),
    // One selector Relation on both sides includes zero-hop self pairs.
    sga_shortest_variant(
      "one selector Relation for both endpoints",
      chain,
      sga_variant_shortest_body(
        "{\"from\":\"selected\",\"id\":\"key\"}",
        "{\"from\":\"selected\",\"id\":\"key\"}",
        extra=each_pair,
      ),
      [
        sga_variant_shortest_row([1]),
        sga_variant_shortest_row([1, 3, 4]),
        sga_variant_shortest_row([4]),
      ],
      work=167,
      workspace=111,
      selectors=[("selected", "[{\"key\":4},{\"key\":1}]")],
    ),
    sga_shortest_variant(
      "two selector Relations",
      chain,
      sga_variant_shortest_body(
        "{\"from\":\"sources\",\"id\":\"key\"}",
        "{\"from\":\"targets\",\"id\":\"key\"}",
        extra=each_pair,
      ),
      [
        sga_variant_shortest_row([1, 3, 4, 5]),
        sga_variant_shortest_row([2, 3, 4, 5]),
      ],
      work=153,
      workspace=111,
      selectors=[
        ("sources", "[{\"key\":2},{\"key\":1}]"),
        ("targets", "[{\"key\":5}]"),
      ],
    ),
    // Wide endpoint predicates keep the narrow control work and workspace.
    sga_shortest_variant(
      "long-text predicate endpoints",
      wide,
      sga_variant_shortest_body(
        "{\"where\":\"node_name = '" + sga_variant_long + "one'\"}",
        "{\"where\":\"node_name = '" + sga_variant_long + "four'\"}",
        extra=each_pair,
      ),
      [sga_variant_shortest_row([1, 3, 4])],
      work=180,
      workspace=114,
      workspace_short=@local_sga.ShortestPredicate(@execution.WorkspaceLimit),
      workspace_short_at_start=false,
    ),
    sga_shortest_variant(
      "edge type filtered scalar",
      labeled,
      sga_variant_shortest_body("1", "4", extra=types),
      [sga_variant_shortest_row([1, 2, 3, 4], labeled=true)],
      work=107,
      workspace=111,
      labeled=true,
    ),
  ]
}

///|
priv struct SgaVariantFixture {
  owner : @lower.BoundPrepared
  sequence : @lower.PreparedSequence
  reads : Array[@execution.ProducerRead]
  graph : @graphs.Completed
  outputs : Array[@execution.CompletedOutput]
}

///|
fn sga_variant_owner(
  variant : SgaVariant,
  source : @lower.BoundPrepared,
  selectors : Array[@lower.BoundPrepared],
) -> @lower.BoundPrepared {
  let inputs = [
    (
      "rows",
      @pipeline.ProducedInput(
        @pipeline.produced_input(
          @lower.pipeline(@lower.bound_preparation(source)),
          @pipeline.Step(0),
        ).unwrap(),
      ),
    ),
  ]
  for index, selector in selectors {
    inputs.push(
      (
        variant.selectors[index].0,
        @pipeline.ProducedInput(
          @pipeline.produced_input(
            @lower.pipeline(@lower.bound_preparation(selector)),
            @pipeline.Step(0),
          ).unwrap(),
        ),
      ),
    )
  }
  let graph = if variant.labeled {
    "{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[]},\"edges\":{\"from\":\"rows\",\"source\":\"src\"," +
    "\"target\":\"dst\",\"label\":\"rel\",\"fields\":[\"weight\"]}}," +
    "\"as\":\"graph\"}"
  } else {
    "{\"graph\":{\"nodes\":{\"from\":\"rows\",\"id\":\"id\"," +
    "\"fields\":[\"node_name\"]},\"edges\":{\"from\":\"rows\"," +
    "\"source\":\"src\",\"target\":\"dst\",\"fields\":[\"weight\"]}}," +
    "\"as\":\"graph\"}"
  }
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[" + graph + ",{\"from\":\"graph\"," + variant.operation + "}]",
    ),
    inputs,
    None,
    Some(input_cursor("\"rows\"")),
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn sga_variant_fixture(variant : SgaVariant) -> SgaVariantFixture raise {
  let source_owner = if variant.labeled {
    carrier_graph_labeled_source_owner_with_rows(variant.rows)
  } else {
    carrier_graph_source_owner_with_rows(variant.rows)
  }
  let selector_owners = variant.selectors.map(selector => {
    carrier_graph_selector_source_owner(selector.1)
  })
  let owner = sga_variant_owner(variant, source_owner, selector_owners)
  let sequence = prepared_sequence(owner)
  let source = carrier_events_source_output(source_owner)
  let outputs = [source]
  let source_read = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let reads = [source_read]
  for index, selector_owner in selector_owners {
    let selected = carrier_events_source_output(selector_owner)
    outputs.push(selected)
    reads.push(
      @execution.prepare_producer_read(
        owner,
        @execution.bind_completed_input(
          owner,
          index + 1,
          selector_owner,
          selected,
        ).unwrap(),
        100,
        1000,
      ).unwrap(),
    )
  }
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [source_read, source_read],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  { owner, sequence, reads, graph, outputs, }
}

///|
fn sga_variant_release(fixture : SgaVariantFixture) -> Unit raise {
  assert_true(@graphs.discard_completed(fixture.graph))
  for output in fixture.outputs {
    assert_true(@execution.completed_output_available(output))
  }
}

///|
priv enum SgaVariantRun {
  SgaTraverseRun(@local_sga.TraverseExecution)
  SgaShortestRun(@local_sga.ShortestExecution)
}

///|
priv enum SgaVariantPoll {
  SgaVariantContinue(Int64)
  SgaVariantComplete(@execution.CompletedOutput, Int64)
  SgaVariantFailed(SgaVariantIssue, Int64)
  SgaVariantStopped(Int64)
}

///|
/// Traversal takes its ceiling from `ValueLimits.max_work`; shortest path
/// takes it from `control_work_limit` and keeps a wide value ceiling.
fn sga_variant_start(
  variant : SgaVariant,
  fixture : SgaVariantFixture,
  control : @bounded.Control,
  ceiling : Int,
  workspace : Int,
) -> Result[SgaVariantRun, SgaVariantIssue] raise {
  let input = @graphs.prepare_step_read(fixture.owner, 1, 0, fixture.graph).unwrap()
  match variant.kind {
    SgaTraverse =>
      @local_sga.start_traverse(
        control,
        task_test_completion(fixture.owner),
        fixture.sequence,
        1,
        input,
        10,
        {
          max_nodes: 1000,
          max_text_bytes: 1000,
          max_depth: 10,
          max_work: ceiling,
        },
        workspace,
        1000,
        1000,
        fixture.reads,
      )
      .map(run => SgaTraverseRun(run))
      .map_err(issue => SgaTraverseIssue(issue))
    SgaShortest =>
      @local_sga.start_shortest(
        control,
        task_test_completion(fixture.owner),
        fixture.sequence,
        1,
        input,
        10,
        {
          max_nodes: 1000,
          max_text_bytes: 1000,
          max_depth: 10,
          max_work: 10000,
        },
        workspace,
        1000,
        1000,
        fixture.reads,
        control_work_limit=Some(ceiling),
      )
      .map(run => SgaShortestRun(run))
      .map_err(issue => SgaShortestIssue(issue))
  }
}

///|
fn sga_variant_advance(run : SgaVariantRun) -> SgaVariantPoll {
  match run {
    SgaTraverseRun(execution) =>
      match @local_sga.advance_traverse(execution, 1).unwrap() {
        @local_sga.TraverseContinue(work~, ..) => SgaVariantContinue(work)
        @local_sga.TraverseComplete(output, work~, ..) =>
          SgaVariantComplete(output, work)
        @local_sga.TraverseFailed(issue, work~, ..) =>
          SgaVariantFailed(SgaTraverseIssue(issue), work)
        @local_sga.TraverseStopped(_, work~, ..) => SgaVariantStopped(work)
      }
    SgaShortestRun(execution) =>
      match @local_sga.advance_shortest(execution, 1).unwrap() {
        @local_sga.ShortestContinue(work~, ..) => SgaVariantContinue(work)
        @local_sga.ShortestComplete(output, work~, ..) =>
          SgaVariantComplete(output, work)
        @local_sga.ShortestFailed(issue, work~, ..) =>
          SgaVariantFailed(SgaShortestIssue(issue), work)
        @local_sga.ShortestStopped(_, work~, ..) => SgaVariantStopped(work)
      }
  }
}

///|
fn sga_variant_cleanup(run : SgaVariantRun) -> Bool {
  match run {
    SgaTraverseRun(execution) =>
      @local_sga.cleanup_traverse(execution) == Ok(true)
    SgaShortestRun(execution) =>
      @local_sga.cleanup_shortest(execution) == Ok(true)
  }
}

///|
fn sga_variant_cleanup_pending(run : SgaVariantRun) -> Bool {
  match run {
    SgaTraverseRun(execution) => @local_sga.traverse_cleanup_pending(execution)
    SgaShortestRun(execution) => @local_sga.shortest_cleanup_pending(execution)
  }
}

///|
fn sga_variant_stopped(run : SgaVariantRun) -> Bool {
  match run {
    SgaTraverseRun(execution) => @local_sga.traverse_stopped(execution)
    SgaShortestRun(execution) => @local_sga.shortest_stopped(execution)
  }
}

///|
fn sga_variant_attempts(run : SgaVariantRun) -> Int {
  match run {
    SgaTraverseRun(execution) =>
      @local_sga.traverse_value_item_attempts(execution)
    SgaShortestRun(execution) =>
      @local_sga.shortest_value_item_attempts(execution)
  }
}

///|
/// Private (entries, live slots, peak slots) of a ledger-backed kernel.
fn sga_variant_ledger(run : SgaVariantRun) -> (Int, Int, Int) {
  match run {
    SgaTraverseRun(execution) => {
      let (live, peak) = @local_sga.traverse_private_workspace_usage(execution)
      (@local_sga.traverse_private_entry_count(execution), live, peak)
    }
    SgaShortestRun(_) => (0, 0, 0)
  }
}

///|
priv enum SgaVariantOutcome {
  SgaVariantRejected(SgaVariantIssue)
  SgaVariantCompleted(Array[String], Int64, Int)
  SgaVariantFailure(SgaVariantIssue, Int64)
} derive(Eq, Debug)

///|
/// Run one variant to its terminal outcome under explicit limits. Every
/// terminal outcome is cleaned up and must leave no private ledger behind.
/// A completion reports its rows, charged control work and ledger peak.
fn sga_variant_run(
  variant : SgaVariant,
  ceiling : Int,
  workspace : Int,
) -> SgaVariantOutcome raise {
  let fixture = sga_variant_fixture(variant)
  let run = match
    sga_variant_start(variant, fixture, @bounded.control(), ceiling, workspace) {
    Ok(run) => run
    Err(issue) => {
      sga_variant_release(fixture)
      return SgaVariantRejected(issue)
    }
  }
  let mut outcome = None
  for _ in 0..<10000 {
    if outcome is None {
      match sga_variant_advance(run) {
        SgaVariantContinue(_) => ()
        SgaVariantComplete(output, work) => {
          let rows = []
          for row in 0..<@execution.completed_row_count(output) {
            rows.push(
              @execution.completed_output_row_wire(output, row, 10000, 1000, 20).unwrap(),
            )
          }
          outcome = Some(
            SgaVariantCompleted(rows, work, sga_variant_ledger(run).2),
          )
        }
        SgaVariantFailed(issue, work) => {
          assert_true(sga_variant_cleanup_pending(run))
          outcome = Some(SgaVariantFailure(issue, work))
        }
        SgaVariantStopped(_) => fail("\{variant.name}: stopped without cancel")
      }
    }
  }
  guard outcome is Some(outcome) else {
    fail("\{variant.name}: no terminal outcome")
  }
  assert_true(sga_variant_cleanup(run))
  assert_false(sga_variant_cleanup_pending(run))
  let (entries, live, _) = sga_variant_ledger(run)
  assert_eq(entries, 0)
  assert_eq(live, 0)
  sga_variant_release(fixture)
  outcome
}

///|
fn sga_variant_expected_peak(variant : SgaVariant) -> Int {
  if variant.ledger {
    variant.workspace
  } else {
    0
  }
}

///|
fn sga_variants_check_work(kind : SgaVariantKind) -> Unit raise {
  let variants = sga_variants().filter(variant => variant.kind == kind)
  assert_true(variants.length() > 0)
  for variant in variants {
    assert_eq(
      (
        variant.name,
        sga_variant_run(variant, variant.ceiling, variant.workspace),
      ),
      (
        variant.name,
        SgaVariantCompleted(
          variant.expected,
          variant.work.to_int64(),
          sga_variant_expected_peak(variant),
        ),
      ),
    )
    assert_eq(
      (
        variant.name,
        sga_variant_run(variant, variant.ceiling - 1, variant.workspace),
      ),
      (
        variant.name,
        SgaVariantFailure(variant.work_short, variant.work_short_at.to_int64()),
      ),
    )
  }
}

///|
fn sga_variants_check_workspace(kind : SgaVariantKind) -> Unit raise {
  let variants = sga_variants().filter(variant => variant.kind == kind)
  assert_true(variants.length() > 0)
  for variant in variants {
    assert_eq(
      (
        variant.name,
        sga_variant_run(variant, variant.ceiling, variant.workspace),
      ),
      (
        variant.name,
        SgaVariantCompleted(
          variant.expected,
          variant.work.to_int64(),
          sga_variant_expected_peak(variant),
        ),
      ),
    )
    let short = sga_variant_run(variant, variant.ceiling, variant.workspace - 1)
    if variant.workspace_short_at_start {
      assert_eq(
        (variant.name, short),
        (variant.name, SgaVariantRejected(variant.workspace_short)),
      )
    } else {
      match short {
        SgaVariantFailure(issue, work) => {
          assert_eq(
            (variant.name, issue),
            (variant.name, variant.workspace_short),
          )
          assert_true(work < variant.work.to_int64())
        }
        _ => fail("\{variant.name}: workspace one short did not fail in flight")
      }
    }
  }
}

///|
/// Cancel each variant once half of its exact control work is charged. The
/// stop charges no further work, publishes no output, and cleanup reclaims
/// the private ledger while every input output stays available.
fn sga_variants_check_cancel(kind : SgaVariantKind) -> Unit raise {
  let variants = sga_variants().filter(variant => variant.kind == kind)
  assert_true(variants.length() > 0)
  for variant in variants {
    let fixture = sga_variant_fixture(variant)
    let control = @bounded.control()
    let run = match
      sga_variant_start(
        variant,
        fixture,
        control,
        variant.ceiling,
        variant.workspace,
      ) {
      Ok(run) => run
      Err(_) => fail("\{variant.name}: exact limits were not admitted")
    }
    let target = (variant.work / 2).to_int64()
    let mut charged = 0L
    let mut polls = 0
    while charged < target {
      match sga_variant_advance(run) {
        SgaVariantContinue(work) => charged = work
        _ => fail("\{variant.name}: terminal before cancellation")
      }
      polls += 1
      assert_true(polls < 10000)
    }
    assert_true(charged > 0L && charged < variant.work.to_int64())
    if variant.ledger {
      let (entries, live, _) = sga_variant_ledger(run)
      assert_true(entries > 0)
      assert_true(live > 0 && live <= variant.workspace)
    }
    let attempts = sga_variant_attempts(run)
    assert_true(@bounded.request_cancel(control))
    match sga_variant_advance(run) {
      SgaVariantStopped(work) =>
        assert_eq((variant.name, work), (variant.name, charged))
      _ => fail("\{variant.name}: cancellation did not stop")
    }
    assert_eq(sga_variant_attempts(run), attempts)
    assert_true(sga_variant_stopped(run))
    assert_true(sga_variant_cleanup_pending(run))
    assert_true(sga_variant_cleanup(run))
    assert_false(sga_variant_cleanup_pending(run))
    let (entries, live, _) = sga_variant_ledger(run)
    assert_eq((variant.name, entries, live), (variant.name, 0, 0))
    sga_variant_release(fixture)
  }
}

///|
test "SGA traversal variants admit exact work and reject one unit short" {
  sga_variants_check_work(SgaTraverse)
}

///|
test "SGA traversal variants admit exact workspace and reject one entry short" {
  sga_variants_check_workspace(SgaTraverse)
}

///|
test "SGA traversal variants cancel after bounded work and clean up" {
  sga_variants_check_cancel(SgaTraverse)
}

///|
test "SGA shortest path variants admit exact work and reject one unit short" {
  sga_variants_check_work(SgaShortest)
}

///|
test "SGA shortest path variants admit exact workspace and reject one entry short" {
  sga_variants_check_workspace(SgaShortest)
}

///|
test "SGA shortest path variants cancel after bounded work and clean up" {
  sga_variants_check_cancel(SgaShortest)
}
