///|
/// Resolved Relation ports retained by the same preparation that allocates
/// canonical node identities. These views never revisit frontend operations,
/// invent input evidence, or grant execution authority.
pub fn preparation_input_count(prepared : Prepared) -> Int {
  prepared.input_carriers.length()
}

///|
pub fn preparation_input_schema(
  prepared : Prepared,
  index : Int,
) -> @schema.Schema? {
  prepared.input_schemas.get(index).unwrap_or(None)
}

///|
/// Exact checked Carrier at one receiving input position. This is semantic
/// metadata only; it is not a runtime value, read authority, or completion.
pub fn preparation_input_carrier(
  prepared : Prepared,
  index : Int,
) -> @carrier.Carrier? {
  prepared.input_carriers.get(index)
}

///|
/// Input provenance category, not proof that a producer has completed.
pub fn preparation_input_is_produced(prepared : Prepared, index : Int) -> Bool {
  @pipeline.input_producer(prepared.owner, index) is Some(_)
}

///|
pub fn preparation_input_keys(
  prepared : Prepared,
  index : Int,
) -> @evidence.KeySet? {
  @pipeline.candidate_keys(prepared.owner, @pipeline.Input(index))
}

///|
/// Ordered input occurrences, not a deduplicated predecessor set. A self join
/// retains both occurrences even when they identify the same logical input.
pub fn node_input_target(node : PreparedNode, index : Int) -> @pipeline.Target? {
  node.input_targets.get(index)
}

///|
pub fn node_input_count(node : PreparedNode) -> Int {
  node.input_targets.length()
}

///|
/// Whether the registered portable kernel boundary can consume this input as
/// an immutable managed Carrier view. This is execution capability metadata,
/// not authority to read a particular completion.
pub fn node_accepts_managed_carrier_view(
  node : PreparedNode,
  index : Int,
) -> Bool {
  if index < 0 || index >= node.input_targets.length() {
    return false
  }
  match operation(node) {
    "SGA.normalize"
    | "SGA.bounds_check"
    | "SGA.degree_metrics"
    | "SGA.components"
    | "SGA.reachable"
    | "SGA.equal"
    | "SGA.diff"
    | "SGA.graft"
    | "SGA.union_structural"
    | "SGA.diff_structural"
    | "SGA.mean_structural"
    | "TEA.watermark.label"
    | "TEA.dedupe"
    | "TEA.window.session_assign"
    | "TEA.window.fixed_label"
    | "TEA.window.sliding_assign"
    | "TEA.sequence.match"
    | "VEC.normalize_l2"
    | "VEC.score_sort"
    | "VEC.pool"
    | "BRIDGE.events.to_rows"
    | "BRIDGE.vectors.to_rows"
    | "BRIDGE.graph.to_node_rows"
    | "BRIDGE.graph.to_edge_rows" => true
    "SGA.apply_delta" => index == 0
    "SGA.shortest_path" => index == 0
    "SGA.subgraph" => index == 0
    "SGA.traverse" => index == 0
    "SGA.match_nodes" | "SGA.match_edges" => index == 0
    "VEC.knn_join" => true
    _ => false
  }
}

///|
/// A split task is legal only when a registered portable candidate can execute
/// this exact checked occurrence on its own. Other carrier pipelines remain
/// fused; this rule does not depend on the neighboring operation's name.
pub fn node_supports_selected_managed_execution(node : PreparedNode) -> Bool {
  match node.payload {
    Values(_) | InnerJoin(_) | CrossJoinRows(_) | AppendRows(_) | SetRows(_) =>
      true
    GraphConstructionValue(_) => operation(node) == "BRIDGE.rows.to_graph"
    GraphTraverseRows(checked) =>
      operation(node) == "SGA.traverse" &&
      @graph.traverse_emission(checked) == @graph.TraversedPaths &&
      node.input_targets.length() == 2
    GraphMatchRows(_) =>
      operation(node) == "SGA.match_nodes" ||
      operation(node) == "SGA.match_edges"
    GraphReachRows(_) => operation(node) == "SGA.reachable"
    GraphShortestRows(_) => operation(node) == "SGA.shortest_path"
    GraphEqualityRows(_) => operation(node) == "SGA.equal"
    GraphDiffRows(_) => operation(node) == "SGA.diff"
    GraphApplyValue(_) => operation(node) == "SGA.apply_delta"
    BasicGraph(_) =>
      operation(node) == "SGA.normalize" ||
      operation(node) == "SGA.bounds_check" ||
      operation(node) == "SGA.degree_metrics" ||
      operation(node) == "SGA.components"
    StructuralGraph(_) | GraphUnion(_) | GraphMeanValue(_) => true
    GraphSubgraphValue(_) => operation(node) == "SGA.subgraph"
    VectorValue(_) =>
      operation(node) == "BRIDGE.rows.to_vectors" ||
      operation(node) == "VEC.normalize_l2" ||
      operation(node) == "VEC.score_sort"
    NearestValue(_) => true
    PoolValue(_) => operation(node) == "VEC.pool"
    RankingValue(_) => operation(node) == "VEC.merge_rankings"
    EventValue(_) =>
      operation(node) == "BRIDGE.rows.to_events" ||
      operation(node) == "TEA.watermark.label" ||
      operation(node) == "TEA.dedupe" ||
      operation(node) == "TEA.window.session_assign"
    SequenceRows(_) => operation(node) == "TEA.sequence.match"
    RowWindow(_) => true
    CarrierProjection(_) =>
      operation(node) == "BRIDGE.graph.to_node_rows" ||
      operation(node) == "BRIDGE.graph.to_edge_rows" ||
      operation(node) == "BRIDGE.events.to_rows" ||
      operation(node) == "BRIDGE.vectors.to_rows"
    Where(_)
    | Derive(_)
    | Select(_)
    | Sort(_)
    | Limit(_)
    | TopK(_)
    | TopKBy(_)
    | Distinct(_)
    | Dedupe(_) => true
    Watermark(_) | Lag(_) | Pivot(_) | Unpivot(_) | Unnest(_) | JsonPick(_) =>
      true
    CountGroup(checked) => checked_bounded_count(checked)
    AssertRows(_) =>
      operation(node) == "REL.assert_all" ||
      operation(node) == "REL.assert_unique"
    _ => false
  }
}

///|
/// The selected count provider consumes keyed and global count profiles.
/// Keep the split decision narrower than general group eligibility so an
/// unsupported aggregate cannot enter a selected task without a provider.
fn checked_bounded_count(checked : @relation.CheckedOperation) -> Bool {
  guard @relation.group(checked) is Some(group) else { return false }
  for index in 0..<@relation.aggregate_count(group) {
    guard @relation.aggregate_at(group, index) is Some(aggregate) &&
      (
        @relation.aggregate_function(aggregate) == @relation.Count ||
        @relation.aggregate_function(aggregate) == @relation.CountIf
      ) &&
      @relation.aggregate_filter(aggregate) is None &&
      @relation.aggregate_distinct(aggregate) != Some(true) else {
      return false
    }
    match @relation.aggregate_argument(aggregate) {
      Rows =>
        if @relation.aggregate_function(aggregate) is @relation.Count {
          ()
        } else {
          return false
        }
      Field(_) => ()
      Expression(_) => return false
    }
  }
  true
}

///|
/// A one-step fused prefix and its first selected consumer share a checked
/// managed handoff only where both existing providers preserve the exact view.
pub fn node_supports_bounded_managed_prefix(
  node : PreparedNode,
  consumer : PreparedNode,
) -> Bool {
  match (node.payload, consumer.payload) {
    (Values(_), Where(_))
    | (Values(_), Derive(_))
    | (Values(_), Distinct(_))
    | (Values(_), Dedupe(_))
    | (Values(_), Select(_))
    | (Values(_), Sort(_))
    | (Values(_), Limit(_))
    | (Values(_), RowWindow(_))
    | (Values(_), Watermark(_))
    | (Values(_), Lag(_))
    | (Values(_), Pivot(_))
    | (Values(_), Analytic(_))
    | (Values(_), Unpivot(_))
    | (Values(_), Unnest(_))
    | (Values(_), JsonPick(_))
    | (Values(_), CountGroup(_))
    | (RankingValue(_), Where(_))
    | (RankingValue(_), Derive(_))
    | (RankingValue(_), Select(_))
    | (NearestValue(_), Where(_))
    | (NearestValue(_), Derive(_))
    | (NearestValue(_), Select(_))
    | (CrossJoinRows(_), _) => true
    (Values(_), AssertRows(_)) =>
      operation(consumer) == "REL.assert_all" ||
      operation(consumer) == "REL.assert_unique"
    _ => false
  }
}

///|
/// Preserve an established fused Carrier provider when no later Relation
/// consumer needs the selected-view handoff. Selection is still decided
/// before execution, never as a retry after a provider failure.
pub fn node_prefers_fused_without_relation_consumer(
  node : PreparedNode,
) -> Bool {
  match node.payload {
    BasicGraph(_) =>
      operation(node) == "SGA.normalize" ||
      operation(node) == "SGA.bounds_check" ||
      operation(node) == "SGA.degree_metrics" ||
      operation(node) == "SGA.components"
    StructuralGraph(_) | GraphUnion(_) | GraphMeanValue(_) => true
    GraphSubgraphValue(_) => operation(node) == "SGA.subgraph"
    GraphEqualityRows(_) => operation(node) == "SGA.equal"
    GraphMatchRows(_) =>
      operation(node) == "SGA.match_nodes" ||
      operation(node) == "SGA.match_edges"
    EventValue(_) =>
      operation(node) == "TEA.watermark.label" ||
      operation(node) == "TEA.dedupe" ||
      operation(node) == "TEA.window.session_assign"
    RowWindow(_) =>
      operation(node) == "TEA.window.fixed_label" ||
      operation(node) == "TEA.window.sliding_assign"
    VectorValue(_) => operation(node) == "VEC.normalize_l2"
    NearestValue(_) => true
    CarrierProjection(_) =>
      operation(node) == "BRIDGE.graph.to_edge_rows" ||
      operation(node) == "BRIDGE.vectors.to_rows"
    _ => false
  }
}

///|
/// The common selected-operation Relation reader can preserve the checked
/// row kernel at this exact internal input. This is typed capability
/// metadata, not a second interpretation of the authored operation name.
pub fn node_accepts_managed_relation_view(
  node : PreparedNode,
  index : Int,
) -> Bool {
  if node.payload is RankingValue(_) {
    return operation(node) == "VEC.merge_rankings" &&
      index >= 0 &&
      index < node.input_targets.length()
  }
  if node.input_targets.length() == 2 && index >= 0 && index < 2 {
    return match node.payload {
      GraphConstructionValue(_) => operation(node) == "BRIDGE.rows.to_graph"
      GraphTraverseRows(_) => index == 1 && operation(node) == "SGA.traverse"
      GraphSubgraphValue(_) => index == 1 && operation(node) == "SGA.subgraph"
      GraphApplyValue(_) => index == 1 && operation(node) == "SGA.apply_delta"
      InnerJoin(_)
      | CrossJoinRows(_)
      | AppendRows(_)
      | SetRows(_)
      | NestRows(_)
      | NearestValue(_) => true
      _ => false
    }
  }
  if index != 0 || node.input_targets.length() != 1 {
    return false
  }
  match node.payload {
    EventValue(_) => operation(node) == "BRIDGE.rows.to_events"
    VectorValue(_) => operation(node) == "BRIDGE.rows.to_vectors"
    Where(_)
    | Derive(_)
    | Select(_)
    | Sort(_)
    | Limit(_)
    | TopK(_)
    | TopKBy(_)
    | Distinct(_)
    | Dedupe(_)
    | CountGroup(_)
    | RowWindow(_)
    | Watermark(_)
    | Lag(_)
    | JsonPick(_) => true
    Pivot(_) | Unpivot(_) | Unnest(_) | WindowGroup(_) | Analytic(_) => true
    AssertRows(_) =>
      operation(node) == "REL.assert_all" ||
      operation(node) == "REL.assert_unique"
    _ => false
  }
}

///|
pub fn node_input_step(node : PreparedNode, index : Int) -> Int? {
  match node_input_target(node, index) {
    Some(@pipeline.Step(step)) => Some(step)
    _ => None
  }
}

///|
pub fn node_output_schema(node : PreparedNode) -> @schema.Schema {
  node.output_schema.unwrap()
}

///|
/// Relation schema when this node produces a Relation. Other Carrier kinds do
/// not acquire a synthetic row schema at the shared lowering boundary.
pub fn node_relation_schema(node : PreparedNode) -> @schema.Schema? {
  node.output_schema
}

///|
/// Exact checked Carrier produced by this node. Lowering retains the typed
/// result instead of reconstructing Carrier roles from an operation name.
pub fn node_output_carrier(node : PreparedNode) -> @carrier.Carrier {
  node.output_carrier
}

///|
pub fn preparation_schema_at(
  prepared : Prepared,
  target : @pipeline.Target,
) -> @schema.Schema? {
  match target {
    Input(index) => prepared.input_schemas.get(index).unwrap_or(None)
    Step(index) => prepared.nodes.get(index).bind(node => node.output_schema)
  }
}

///|
/// Exact checked Carrier at a prepared semantic port.
pub fn preparation_carrier_at(
  prepared : Prepared,
  target : @pipeline.Target,
) -> @carrier.Carrier? {
  match target {
    Input(index) => prepared.input_carriers.get(index)
    Step(index) => prepared.nodes.get(index).map(node => node.output_carrier)
  }
}

///|
/// Final output of the finite single-output sequence profile. An empty sequence
/// passes its first input through; an input-free empty preparation has no port.
pub fn preparation_output_target(prepared : Prepared) -> @pipeline.Target? {
  if !prepared.nodes.is_empty() {
    Some(@pipeline.Step(prepared.nodes.length() - 1))
  } else if !prepared.input_carriers.is_empty() {
    Some(@pipeline.Input(0))
  } else {
    None
  }
}
