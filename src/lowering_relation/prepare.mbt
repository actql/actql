///|
/// Preparation is not an executable fragment: expression lowering, parameter
/// binding and operation-parameter admission still have to succeed.
struct Prepared {
  owner : @pipeline.CheckedPipeline
  nodes : Array[PreparedNode]
  input_ids : Array[String]
  input_schemas : Array[@schema.Schema?]
  input_carriers : Array[@carrier.Carrier]
  usage : Usage
}

///|
struct PreparedNode {
  id : String
  projection_id : String?
  order_id : String?
  aggregation_id : String?
  nest_expansion : Array[PreparedNestExpansionNode]?
  payload : Payload
  inputs : Array[String]
  input_targets : Array[@pipeline.Target]
  output_schema : @schema.Schema?
  output_carrier : @carrier.Carrier
  source : @decode.Cursor
}

///|
/// Retain checked payloads rather than reinterpreting source JSON. These are
/// not a second semantic IR, and must not be passed to an execution engine.
pub enum Payload {
  Values(@values.CheckedValues)
  RowWindow(@window.CheckedWindow)
  Derive(@relation.CheckedOperation)
  Where(@relation.CheckedOperation)
  Select(@relation.CheckedOperation)
  Limit(@relation.CheckedOperation)
  TopK(@relation.CheckedOperation)
  TopKBy(@relation.CheckedOperation)
  Pivot(@relation.CheckedOperation)
  Unnest(@relation.CheckedOperation)
  Unpivot(@relation.CheckedOperation)
  Distinct(@relation.CheckedOperation)
  Dedupe(@relation.CheckedOperation)
  Sort(@relation.CheckedOperation)
  CountGroup(@relation.CheckedOperation)
  WindowGroup(@relation.CheckedOperation)
  Lag(@relation.CheckedOperation)
  Watermark(@relation.CheckedOperation)
  Analytic(@relation.CheckedOperation)
  AssertRows(@relation.CheckedOperation)
  JsonPick(@relation.CheckedOperation)
  InnerJoin(@join.CheckedJoin)
  CrossJoinRows(@join.CheckedCrossJoin)
  AppendRows(@append.CheckedAppend)
  SetRows(@set.CheckedSet)
  NestRows(@nest.CheckedNest)
  BasicGraph(@graph.CheckedGraph)
  StructuralGraph(@graph.CheckedStructural)
  GraphUnion(@graph.CheckedUnion)
  GraphMeanValue(@graph.CheckedMean)
  GraphMatchRows(@graph.CheckedMatch)
  GraphReachRows(@graph.CheckedReach)
  GraphSubgraphValue(@graph.CheckedSubgraph)
  GraphEqualityRows(@graph.CheckedEquality)
  GraphDiffRows(@graph.CheckedDiff)
  GraphApplyValue(@graph.CheckedApply)
}

///|
pub(all) struct Limits {
  max_nodes : Int
  max_references : Int
  max_work : Int
  max_identifier_bytes : Int
} derive(Eq, Debug)

///|
pub(all) struct Usage {
  nodes : Int
  references : Int
  work : Int
  identifier_bytes : Int
} derive(Eq, Debug)

///|
pub(all) enum IssueKind {
  InvalidLimits
  BudgetExceeded
  OperationNotImplemented
  InvalidCheckedWiring
  IdentifierCollision
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
}

///|
pub fn pipeline(value : Prepared) -> @pipeline.CheckedPipeline {
  value.owner
}

///|
pub fn usage(value : Prepared) -> Usage {
  value.usage
}

///|
pub fn node_count(value : Prepared) -> Int {
  value.nodes.length()
}

///|
pub fn node_at(value : Prepared, index : Int) -> PreparedNode? {
  value.nodes.get(index)
}

///|
pub fn node_id(value : PreparedNode) -> String {
  value.id
}

///|
/// Canonical keyed-distinct prefix, reserved by the same collision allocator.
pub fn projection_node_id(value : PreparedNode) -> String? {
  value.projection_id
}

///|
pub fn order_node_id(value : PreparedNode) -> String? {
  value.order_id
}

///|
pub fn payload(value : PreparedNode) -> Payload {
  value.payload
}

///|
pub fn source(value : PreparedNode) -> @decode.Cursor {
  value.source
}

///|
pub fn input_ids(value : PreparedNode) -> Array[String] {
  value.inputs.copy()
}

///|
pub fn input_id(value : Prepared, index : Int) -> String? {
  value.input_ids.get(index)
}

///|
pub fn operation(value : PreparedNode) -> String {
  match value.payload {
    Values(_) => "REL.values"
    RowWindow(value) =>
      match @window.kind(@window.options(value)) {
        @window.Fixed => "REL.window.fixed"
        @window.Sliding => "REL.window.sliding"
      }
    Derive(_) => "REL.derive"
    Where(_) => "REL.where"
    Select(_) => "REL.select"
    Limit(_) => "REL.limit"
    TopK(_) => "REL.topk"
    TopKBy(_) => "REL.topk_partitioned"
    Pivot(_) => "REL.pivot"
    Unnest(_) => "REL.unnest"
    Unpivot(_) => "REL.unpivot"
    Distinct(_) => "REL.distinct"
    Dedupe(_) => "REL.dedupeRows"
    Sort(_) => "REL.orderByStable"
    CountGroup(_) => "REL.groupBy"
    WindowGroup(_) => "REL.window.project"
    Lag(_) => "REL.window.lag"
    Watermark(_) => "REL.watermark"
    Analytic(_) => "REL.analytic"
    AssertRows(op) =>
      match @relation.row_operation(op) {
        Some(@relation.AssertWhere) => "REL.assert_all"
        Some(@relation.AssertUnique(_)) => "REL.assert_unique"
        _ => "REL.assert_all"
      }
    JsonPick(_) => "REL.json.pick"
    InnerJoin(_) => "REL.join"
    CrossJoinRows(_) => "REL.cross_join"
    AppendRows(_) => "REL.unionAll"
    // Nest lowers to a registered multi-node expansion whose final node is a
    // projection. There is no REL.nest operation in the AoA registry.
    NestRows(_) => "REL.select"
    BasicGraph(value) =>
      match @graph.operation(value) {
        @graph.NormalizeGraph => "SGA.normalize"
        @graph.Degree => "SGA.degree_metrics"
        @graph.Components => "SGA.components"
        @graph.GraphBounds => "SGA.bounds_check"
      }
    StructuralGraph(value) =>
      match @graph.structural_operation(value) {
        @graph.Graft => "SGA.graft"
        @graph.Union => "SGA.union_structural"
        @graph.Subtract => "SGA.diff_structural"
      }
    GraphUnion(_) => "SGA.union_structural"
    GraphMeanValue(_) => "SGA.mean_structural"
    GraphMatchRows(value) =>
      match @graph.match_entity(value) {
        @graph.Nodes => "SGA.match_nodes"
        @graph.Edges => "SGA.match_edges"
      }
    GraphReachRows(_) => "SGA.reachable"
    GraphSubgraphValue(_) => "SGA.subgraph"
    GraphEqualityRows(_) => "SGA.equal"
    GraphDiffRows(_) => "SGA.diff"
    GraphApplyValue(_) => "SGA.apply_delta"
    SetRows(checked) =>
      match @set.operation(checked) {
        @set.Except => "REL.except_rows"
        @set.Intersect => "REL.intersect_rows"
      }
  }
}

///|
fn classify(op : @pipeline.CheckedOperation) -> Payload? {
  match op {
    Values(v) => Some(Values(v))
    Window(value) => Some(RowWindow(value))
    Unary(v) =>
      match @relation.operation(v) {
        Derive => Some(Derive(v))
        Filter => Some(Where(v))
        Select | Rename | Drop => Some(Select(v))
        Take => Some(Limit(v))
        TopK => Some(TopK(v))
        TopKBy => Some(TopKBy(v))
        Pivot => Some(Pivot(v))
        Unnest => Some(Unnest(v))
        Unpivot => Some(Unpivot(v))
        Distinct => Some(Distinct(v))
        DedupeRows => Some(Dedupe(v))
        Sort => Some(Sort(v))
        Group => Some(CountGroup(v))
        AssertRows => Some(AssertRows(v))
        JsonPick => Some(JsonPick(v))
        Lag => Some(Lag(v))
        WatermarkRows => Some(Watermark(v))
        Analytic => Some(Analytic(v))
      }
    Join(checked~, ..) => Some(InnerJoin(checked))
    CrossJoin(checked~, ..) => Some(CrossJoinRows(checked))
    Append(checked~, ..) => Some(AppendRows(checked))
    Set(checked~, ..) => Some(SetRows(checked))
    WindowGroup(v) => Some(WindowGroup(v))
    Nest(checked~, ..) => Some(NestRows(checked))
    IntervalJoin(..)
    | AsOfJoin(..)
    | Sequence(_)
    | TimeSeries(_)
    | Calendar(_)
    | Projection(_) => None
    Graph(value) =>
      match @graph.operation(value) {
        @graph.NormalizeGraph
        | @graph.Degree
        | @graph.Components
        | @graph.GraphBounds => Some(BasicGraph(value))
      }
    GraphMatch(value) => Some(GraphMatchRows(value))
    Reach(value) => Some(GraphReachRows(value))
    Subgraph(checked~, ..) => Some(GraphSubgraphValue(checked))
    Traverse(..) | Shortest(..) => None
    GraphEquality(checked~, ..) => Some(GraphEqualityRows(checked))
    GraphDiff(checked~, ..) => Some(GraphDiffRows(checked))
    GraphApply(checked~, ..) => Some(GraphApplyValue(checked))
    GraphStructural(checked~, ..) => Some(StructuralGraph(checked))
    GraphUnion(v) => Some(GraphUnion(v))
    GraphMean(value) => Some(GraphMeanValue(value))
    GraphConstruction(..)
    | Vector(_)
    | Nearest(..)
    | Pool(_)
    | Ranking(_)
    | TextRank(..)
    | Event(_) => None
  }
}

///|
pub fn prepare(
  checked : @pipeline.CheckedPipeline,
  limits : Limits,
) -> Result[Prepared, Issue] {
  let root = @pipeline.source(checked)
  if limits.max_nodes < 0 ||
    limits.max_references < 0 ||
    limits.max_work < 0 ||
    limits.max_identifier_bytes < 0 {
    return Err({ kind: InvalidLimits, source: root, })
  }
  let count = @pipeline.step_count(checked)
  let inputs = @pipeline.input_count(checked)
  if count > limits.max_nodes || inputs > limits.max_nodes - count {
    return Err({ kind: BudgetExceeded, source: root, })
  }
  let nodes : Array[PreparedNode] = []
  let input_ids : Array[String] = []
  let input_schemas : Array[@schema.Schema?] = []
  let input_carriers : Array[@carrier.Carrier] = []
  let used : Map[String, Bool] = Map([])
  let mut work = 0
  let mut references = 0
  let mut bytes = 0
  let mut expansions = 0
  for i = 0; i < inputs; i = i + 1 {
    if work >= limits.max_work {
      return Err({ kind: BudgetExceeded, source: root, })
    }
    work += 1
    let id = "input_" + i.to_string()
    if id.length() > limits.max_identifier_bytes - bytes {
      return Err({ kind: BudgetExceeded, source: root, })
    }
    bytes += id.length() // Generated identifiers are ASCII, on every target.
    used[id] = true
    input_ids.push(id)
    guard @pipeline.carrier_at(checked, @pipeline.Input(i)) is Some(carrier) else {
      return Err({ kind: InvalidCheckedWiring, source: root, })
    }
    input_carriers.push(carrier)
    let schema = @pipeline.schema_at(checked, @pipeline.Input(i))
    if @carrier.kind(carrier) == @carrier.RelationKind && schema is None {
      return Err({ kind: InvalidCheckedWiring, source: root, })
    }
    input_schemas.push(schema)
  }
  for i = 0; i < count; i = i + 1 {
    if work >= limits.max_work {
      return Err({ kind: BudgetExceeded, source: root, })
    }
    work += 1
    guard @pipeline.step_at(checked, i) is Some(step) else {
      return Err({ kind: InvalidCheckedWiring, source: root, })
    }
    guard classify(step.operation) is Some(payload) else {
      return Err({ kind: OperationNotImplemented, source: step.source, })
    }
    guard @pipeline.carrier_at(checked, @pipeline.Step(i))
      is Some(output_carrier) else {
      return Err({ kind: InvalidCheckedWiring, source: step.source, })
    }
    let output_schema = @pipeline.step_schema(step)
    if @carrier.kind(output_carrier) == @carrier.RelationKind &&
      output_schema is None {
      return Err({ kind: InvalidCheckedWiring, source: step.source, })
    }
    let (preferred, arity) = match payload {
      Values(_) => ("values", 0)
      RowWindow(_) => ("window", 1)
      Derive(_) => ("derive", 1)
      Where(_) => ("where", 1)
      Select(_) => ("select", 1)
      Limit(_) => ("limit", 1)
      TopK(_) => ("top_k", 1)
      TopKBy(_) => ("top_k_by", 1)
      Pivot(_) => ("pivot", 1)
      Unnest(_) => ("unnest", 1)
      Unpivot(_) => ("unpivot", 1)
      Distinct(_) => ("distinct", 1)
      Dedupe(_) => ("dedupe", 1)
      Sort(_) => ("sort", 1)
      CountGroup(_) => ("group", 1)
      WindowGroup(_) => ("window_group", 1)
      Lag(_) => ("lag", 1)
      Watermark(_) => ("watermark", 1)
      Analytic(_) => ("analytic", 1)
      AssertRows(_) => ("assert", 1)
      JsonPick(_) => ("json_pick", 1)
      InnerJoin(_) => ("join", 2)
      CrossJoinRows(_) => ("cross_join", 2)
      AppendRows(_) => ("append", 2)
      NestRows(_) => ("nest", 2)
      BasicGraph(value) =>
        (
          match @graph.operation(value) {
            @graph.NormalizeGraph => "normalize_graph"
            @graph.Degree => "degree"
            @graph.Components => "components"
            @graph.GraphBounds => "graph_bounds"
          },
          1,
        )
      StructuralGraph(value) =>
        (
          match @graph.structural_operation(value) {
            @graph.Graft => "graft_graph"
            @graph.Union => "union_graphs"
            @graph.Subtract => "subtract_graphs"
          },
          2,
        )
      GraphUnion(value) => ("union_graphs", 1 + @graph.union_count(value))
      GraphMeanValue(value) =>
        ("mean_graphs", @graph.mean_sample_count(@graph.mean_options(value)))
      GraphMatchRows(value) =>
        (
          match @graph.match_entity(value) {
            @graph.Nodes => "match_nodes"
            @graph.Edges => "match_edges"
          },
          1,
        )
      GraphReachRows(_) => ("reach", 1)
      GraphSubgraphValue(checked) =>
        (
          "subgraph",
          if @graph.selector_form(@graph.subgraph_nodes(checked))
            is @graph.RelationIds(..) {
            2
          } else {
            1
          },
        )
      GraphEqualityRows(_) => ("graphs_equal", 2)
      GraphDiffRows(_) => ("graph_diff", 2)
      GraphApplyValue(_) => ("apply_graph_delta", 2)
      SetRows(checked) =>
        (
          match @set.operation(checked) {
            @set.Except => "except"
            @set.Intersect => "intersect"
          },
          2,
        )
    }
    let id = preferred + "_" + i.to_string()
    let nest_expansion = match payload {
      NestRows(nest) => Some(prepare_source_nest_expansion(checked, i, nest))
      _ => None
    }
    if nest_expansion is Some(expansion) {
      let expanded_nodes = expansion.length()
      let expanded_references = nest_expansion_reference_count(expansion)
      let added_nodes = expanded_nodes - 1
      let added_references = expanded_references - arity
      if added_nodes > limits.max_nodes - count - inputs - expansions ||
        added_references > limits.max_references - references ||
        added_nodes > limits.max_work - work ||
        added_references > limits.max_work - work - added_nodes {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      for expansion_node in expansion {
        if expansion_node.source_node {
          continue
        }
        let generated = nest_generated_role_id(i, expansion_node.role)
        if used.contains(generated) || generated == id {
          return Err({ kind: IdentifierCollision, source: step.source, })
        }
        if generated.length() > limits.max_identifier_bytes - bytes {
          return Err({ kind: BudgetExceeded, source: step.source, })
        }
        bytes += generated.length()
        used[generated] = true
      }
      expansions += added_nodes
      references += added_references
      work += added_nodes + added_references
    }
    let projection_id = match payload {
      InnerJoin(_) => {
        if expansions >= limits.max_nodes - count - inputs ||
          references >= limits.max_references ||
          work >= limits.max_work {
          return Err({ kind: BudgetExceeded, source: step.source, })
        }
        let prefix = "join_raw_" + i.to_string()
        if used.contains(prefix) || prefix == id {
          return Err({ kind: IdentifierCollision, source: step.source, })
        }
        if prefix.length() > limits.max_identifier_bytes - bytes {
          return Err({ kind: BudgetExceeded, source: step.source, })
        }
        bytes += prefix.length()
        expansions += 1
        references += 1
        work += 1
        used[prefix] = true
        Some(prefix)
      }
      Distinct(op) => {
        let width = @schema.field_count(@relation.output_schema(op))
        if width > limits.max_work - work {
          return Err({ kind: BudgetExceeded, source: step.source, })
        }
        work += width
        if @relation.projection(op).is_empty() {
          None
        } else {
          if expansions >= limits.max_nodes - count - inputs ||
            references >= limits.max_references ||
            work >= limits.max_work {
            return Err({ kind: BudgetExceeded, source: step.source, })
          }
          let prefix = "select_" + i.to_string()
          if used.contains(prefix) || prefix == id {
            return Err({ kind: IdentifierCollision, source: step.source, })
          }
          if prefix.length() > limits.max_identifier_bytes - bytes {
            return Err({ kind: BudgetExceeded, source: step.source, })
          }
          bytes += prefix.length()
          expansions += 1
          references += 1
          work += 1
          used[prefix] = true
          Some(prefix)
        }
      }
      Values(_)
      | RowWindow(_)
      | Derive(_)
      | Where(_)
      | Select(_)
      | Limit(_)
      | TopK(_)
      | TopKBy(_)
      | Pivot(_)
      | Unnest(_)
      | Unpivot(_)
      | Dedupe(_)
      | Sort(_)
      | CountGroup(_)
      | WindowGroup(_)
      | Lag(_)
      | Watermark(_)
      | Analytic(_) => None
      AssertRows(_) => None
      JsonPick(_) => None
      AppendRows(_) => None
      SetRows(_) => None
      CrossJoinRows(_) => None
      NestRows(_) => None
      BasicGraph(_) => None
      StructuralGraph(_) => None
      GraphUnion(_) => None
      GraphMeanValue(_) => None
      GraphMatchRows(_) => None
      GraphReachRows(_) => None
      GraphSubgraphValue(_) => None
      GraphEqualityRows(_) => None
      GraphDiffRows(_) => None
      GraphApplyValue(_) => None
    }
    let order_id = if payload is Limit(_) &&
      take_completion(checked, i) is Some(_) {
      if expansions >= limits.max_nodes - count - inputs ||
        references >= limits.max_references ||
        work >= limits.max_work {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      let prefix = "sort_" + i.to_string()
      if used.contains(prefix) || prefix == id {
        return Err({ kind: IdentifierCollision, source: step.source, })
      }
      if prefix.length() > limits.max_identifier_bytes - bytes {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      bytes += prefix.length()
      expansions += 1
      references += 1
      work += 1
      used[prefix] = true
      Some(prefix)
    } else {
      None
    }
    if used.contains(id) {
      return Err({ kind: IdentifierCollision, source: step.source, })
    }
    let aggregation_id = if payload is CountGroup(_) {
      if expansions >= limits.max_nodes - count - inputs ||
        references >= limits.max_references ||
        work >= limits.max_work {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      let prefix = "aggregate_" + i.to_string()
      if used.contains(prefix) || prefix == id {
        return Err({ kind: IdentifierCollision, source: step.source, })
      }
      if prefix.length() > limits.max_identifier_bytes - bytes {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      bytes += prefix.length()
      expansions += 1
      references += 1
      work += 1
      used[prefix] = true
      Some(prefix)
    } else {
      None
    }
    if id.length() > limits.max_identifier_bytes - bytes {
      return Err({ kind: BudgetExceeded, source: step.source, })
    }
    bytes += id.length()
    let refs : Array[String] = []
    let input_targets : Array[@pipeline.Target] = []
    let occurrences = @pipeline.input_occurrence_count(step)
    if occurrences != arity {
      return Err({ kind: InvalidCheckedWiring, source: step.source, })
    }
    for j = 0; j < occurrences; j = j + 1 {
      if work >= limits.max_work || references >= limits.max_references {
        return Err({ kind: BudgetExceeded, source: step.source, })
      }
      work += 1
      references += 1
      guard @pipeline.input_occurrence_at(step, j) is Some(occurrence) else {
        return Err({ kind: InvalidCheckedWiring, source: step.source, })
      }
      if @pipeline.carrier_at(checked, occurrence.target) is None {
        return Err({ kind: InvalidCheckedWiring, source: step.source, })
      }
      let resolved = match occurrence.target {
        Input(index) => input_ids.get(index)
        Step(index) => nodes.get(index).map(node => node.id)
      }
      guard resolved is Some(ref_) else {
        return Err({ kind: InvalidCheckedWiring, source: step.source, })
      }
      refs.push(ref_)
      input_targets.push(occurrence.target)
    }
    used[id] = true
    nodes.push({
      id,
      projection_id,
      order_id,
      aggregation_id,
      nest_expansion,
      payload,
      inputs: refs,
      input_targets,
      output_schema,
      output_carrier,
      source: step.source,
    })
  }
  Ok({
    owner: checked,
    nodes,
    input_ids,
    input_schemas,
    input_carriers,
    usage: {
      nodes: count + inputs + expansions,
      references,
      work,
      identifier_bytes: bytes,
    },
  })
}
