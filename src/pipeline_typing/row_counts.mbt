///|
/// Conditional successful-output count, not a Host ceiling or execution permit.
pub struct RowCount {
  upper : Int64
  exact : Bool
} derive(Eq, Debug)

///|
/// Distinct graph extents; neither is a Relation row count.
pub struct GraphCount {
  nodes : RowCount?
  edges : RowCount?
} derive(Eq, Debug)

///|
priv struct CountTable[T] {
  inputs : Array[T?]
  steps : Array[T?]
}

///|
fn graph_count_at(
  target : Target,
  table : CountTable[GraphCount],
) -> GraphCount? {
  match target {
    Input(i) => table.inputs[i]
    Step(i) => table.steps[i]
  }
}

///|
fn count(n : Int64, exact : Bool) -> RowCount {
  { upper: n, exact: exact || n == 0L, }
}

///|
fn reduce_count(input : RowCount?) -> RowCount? {
  input.map(v => count(v.upper, false))
}

///|
fn set_count(
  left : RowCount?,
  right : RowCount?,
  operation : @set.Operation,
  duplicates : @set.Duplicates,
  empty_schema : Bool,
) -> RowCount? {
  if left is Some({ upper: 0L, .. }) ||
    (operation == @set.Intersect && right is Some({ upper: 0L, .. })) {
    return Some(count(0L, true))
  }
  // With no fields there is exactly one possible row equivalence class.
  if empty_schema && left is Some(a) && a.exact && right is Some(z) && z.exact {
    let n = if operation == @set.Except {
      if a.upper > z.upper {
        a.upper - z.upper
      } else {
        0L
      }
    } else if a.upper < z.upper {
      a.upper
    } else {
      z.upper
    }
    if duplicates == @set.All {
      return Some(count(n, true))
    }
    let survives = a.upper > 0L &&
      (if operation == @set.Except { z.upper == 0L } else { z.upper > 0L })
    return Some(count(if survives { 1L } else { 0L }, true))
  }
  if operation == @set.Except &&
    duplicates == @set.All &&
    right is Some({ upper: 0L, .. }) {
    return left
  }
  if empty_schema && duplicates == @set.Distinct {
    return Some(count(1L, false))
  }
  if operation == @set.Except {
    return reduce_count(left)
  }
  match (left, right) {
    (Some(a), Some(z)) =>
      Some(count(if a.upper < z.upper { a.upper } else { z.upper }, false))
    (Some(a), None) | (None, Some(a)) => Some(count(a.upper, false))
    _ => None
  }
}

///|
fn count_at(target : Target, table : CountTable[RowCount]) -> RowCount? {
  match target {
    Input(i) => table.inputs[i]
    Step(i) => table.steps[i]
  }
}

///|
fn sum_counts(
  source : @decode.Cursor,
  a : RowCount?,
  z : RowCount?,
) -> RowCount? raise Stop {
  guard a is Some(a) && z is Some(z) else { return None }
  guard @capacity.read(a.upper) is Ok(left) &&
    @capacity.read(z.upper) is Ok(right) else {
    fail(source, RowBoundOverflow)
  }
  match @capacity.add(left, right) {
    Ok(total) => Some(count(@capacity.value(total), a.exact && z.exact))
    Err(_) => fail(source, RowBoundOverflow)
  }
}

///|
fn product_counts(
  source : @decode.Cursor,
  a : RowCount?,
  z : RowCount?,
) -> RowCount? raise Stop {
  if a is Some({ upper: 0L, .. }) || z is Some({ upper: 0L, .. }) {
    return Some(count(0L, true))
  }
  guard a is Some(a) && z is Some(z) else { return None }
  guard @capacity.read(a.upper) is Ok(left) &&
    @capacity.read(z.upper) is Ok(right) else {
    fail(source, RowBoundOverflow)
  }
  match @capacity.multiply(left, right) {
    Ok(total) => Some(count(@capacity.value(total), a.exact && z.exact))
    Err(_) => fail(source, RowBoundOverflow)
  }
}

///|
fn slice_count(input : RowCount?, limit : Int64?, offset : Int64?) -> RowCount? {
  let remaining = input.map(v => {
    match offset {
      Some(n) => count(if v.upper > n { v.upper - n } else { 0L }, v.exact)
      None => count(v.upper, false)
    }
  })
  match (remaining, limit) {
    (Some(v), Some(n)) =>
      Some(count(if v.upper < n { v.upper } else { n }, v.exact))
    (Some(v), None) => Some(count(v.upper, false))
    (None, Some(n)) => Some(count(n, false))
    (None, None) => None
  }
}

///|
fn unary_count(
  source : @decode.Cursor,
  input : RowCount?,
  op : @relation.CheckedOperation,
) -> RowCount? raise Stop {
  match @relation.row_count_rule(op) {
    Unknown => None
    Preserve => input
    Reduce => reduce_count(input)
    OneRow => Some(count(1L, true))
    OneExistingRow =>
      match input {
        Some(v) => Some(count(if v.upper == 0L { 0L } else { 1L }, v.exact))
        None => Some(count(1L, false))
      }
    Slice(limit~, offset~) => slice_count(input, limit, offset)
    Repeat(n) => product_counts(source, input, Some(count(n, true)))
    Expand(n) =>
      product_counts(source, reduce_count(input), n.map(v => count(v, false)))
  }
}

///|
fn join_count(
  source : @decode.Cursor,
  left : RowCount?,
  right : RowCount?,
  kind : @join.Kind,
  left_unique? : Bool = false,
  right_unique? : Bool = false,
) -> RowCount? raise Stop {
  // Empty-side rules below are stronger than uniqueness-based upper bounds.
  if (left_unique || right_unique) &&
    !(left is Some({ upper: 0L, .. })) &&
    !(right is Some({ upper: 0L, .. })) {
    match kind {
      Inner => {
        if left_unique && right_unique {
          return match (left, right) {
            (Some(a), Some(z)) =>
              Some(
                count(if a.upper < z.upper { a.upper } else { z.upper }, false),
              )
            (Some(v), None) | (None, Some(v)) => Some(count(v.upper, false))
            _ => None
          }
        }
        return reduce_count(if right_unique { left } else { right })
      }
      Left => {
        if right_unique || (right is Some(v) && v.upper <= 1L) {
          return left
        }
        // Each right row matches at most one left row. Once a match exists,
        // one left row no longer contributes an unmatched output occurrence.
        return reduce_count(
          sum_counts(source, left, right.map(v => count(v.upper - 1L, false))),
        )
      }
      Full => return reduce_count(sum_counts(source, left, right))
      Semi | Anti => ()
    }
  }
  match kind {
    Inner => reduce_count(product_counts(source, left, right))
    Semi =>
      if right is Some({ upper: 0L, .. }) {
        Some(count(0L, true))
      } else {
        reduce_count(left)
      }
    Anti =>
      if right is Some({ upper: 0L, .. }) {
        left
      } else {
        reduce_count(left)
      }
    Left =>
      if right is Some(v) && v.upper <= 1L {
        left
      } else {
        product_counts(
          source,
          reduce_count(left),
          right.map(v => count(if v.upper == 0L { 1L } else { v.upper }, false)),
        )
      }
    Full => {
      if left is Some({ upper: 0L, .. }) {
        return right
      }
      if right is Some({ upper: 0L, .. }) {
        return left
      }
      guard left is Some(a) && right is Some(z) else { return None }
      // Maximum over matching pairs and isolated vertices is max(L*R, L+R).
      // For L,R >= 2 the product dominates; avoid an unnecessary sum.
      if a.upper == 1L || z.upper == 1L {
        reduce_count(sum_counts(source, left, right))
      } else {
        reduce_count(product_counts(source, left, right))
      }
    }
  }
}

///|
fn window_count(
  source : @decode.Cursor,
  input : RowCount?,
  options : @window.Options,
) -> RowCount? raise Stop {
  if @window.kind(options) == Fixed {
    return input
  }
  let factor = match (@window.size(options), @window.step(options)) {
    (Literal(size), Some(Literal(step))) =>
      Some(
        count(
          size / step + (if size % step == 0L { 0L } else { 1L }),
          size % step == 0L,
        ),
      )
    _ => None
  }
  product_counts(source, input, factor)
}

///|
fn count_violation(actual : RowCount?, threshold : @graph.Count?) -> RowCount {
  guard threshold is Some(threshold) else { return count(0L, true) }
  extent_violation(
    actual,
    match threshold {
      Literal(n) => Some(n)
      Parameter(_) => None
    },
  )
}

///|
fn extent_violation(actual : RowCount?, threshold : Int64?) -> RowCount {
  if actual is Some({ upper: 0L, .. }) {
    return count(0L, true)
  }
  match (actual, threshold) {
    (Some(actual), Some(maximum)) =>
      if actual.upper <= maximum {
        count(0L, true)
      } else {
        count(1L, actual.exact)
      }
    _ => count(1L, false)
  }
}

///|
fn graph_report_count(
  source : @decode.Cursor,
  input : GraphCount?,
  operation : @graph.CheckedGraph,
) -> RowCount? raise Stop {
  guard @graph.options(operation)
    is BoundsOptions(max_nodes~, max_edges~, max_degree~) else {
    return None
  }
  let nodes = input.bind(g => g.nodes)
  let edges = input.bind(g => g.edges)
  let whole = sum_counts(
    source,
    Some(count_violation(nodes, max_nodes)),
    Some(count_violation(edges, max_edges)),
  )
  let degree = if max_degree is None || edges is Some({ upper: 0L, .. }) {
    Some(count(0L, true))
  } else if edges is Some(e) &&
    max_degree is Some(Literal(maximum)) &&
    e.upper <= maximum / 2L {
    // Total degree is at most twice the edge count, including self-loops.
    // Compare by division to avoid overflowing an unnecessary 2*E product.
    Some(count(0L, true))
  } else {
    reduce_count(nodes)
  }
  sum_counts(source, whole, degree)
}

///|
fn ranking_count(
  b : Budget,
  step : CheckedStep,
  prior : CountTable[RowCount],
  op : @vector.CheckedRanking,
) -> RowCount? raise Stop {
  let options = @vector.merged_ranking_options(op)
  let global = @vector.ranking_by_count(options) == 0
  let k = @vector.ranking_k(options).to_int64()
  // Inspect completeness before adding: an unknown operand prevents deriving
  // a finite union bound, so a known prefix must not fail with a bogus overflow.
  spend(b, step.source, step.connections.entries.length())
  let mut known = true
  for edge in step.connections.entries {
    if count_at(edge.target, prior) is None {
      known = false
    }
  }
  if !known {
    return if global { Some(count(k, false)) } else { None }
  }
  spend(b, step.source, step.connections.entries.length())
  let mut total = Some(count(0L, true))
  for edge in step.connections.entries {
    let next = count_at(edge.target, prior)
    if global {
      // Compute min(k, sum) directly; no oversized intermediate is needed.
      let a = total.unwrap().upper
      let z = next.unwrap().upper
      total = Some(count(if z >= k - a { k } else { a + z }, false))
    } else {
      total = sum_counts(step.source, total, next)
    }
  }
  reduce_count(total)
}

///|
fn selector_count(
  selector : @graph.CheckedSelector,
  target : Target?,
  rows : CountTable[RowCount],
  nodes : RowCount?,
) -> RowCount? {
  let selected = match @graph.selector_form(selector) {
    ExplicitIds =>
      Some(count(@graph.selector_id_count(selector).to_int64(), false))
    RelationIds(_) => reduce_count(target.bind(t => count_at(t, rows)))
    PredicateNodes => None
  }
  match (selected, nodes) {
    (Some(a), Some(z)) =>
      Some(count(if a.upper < z.upper { a.upper } else { z.upper }, false))
    (Some(a), None) => Some(a)
    (None, _) => reduce_count(nodes)
  }
}

///|
fn endpoint_count(
  endpoint : @graph.PathEndpoint,
  target : Target?,
  rows : CountTable[RowCount],
  nodes : RowCount?,
) -> RowCount? {
  match endpoint {
    Single(_) =>
      Some(count(if nodes is Some({ upper: 0L, .. }) { 0L } else { 1L }, false))
    Selected(s) => selector_count(s, target, rows, nodes)
  }
}

///|
fn mean_graph_count(
  b : Budget,
  step : CheckedStep,
  graphs : CountTable[GraphCount],
  op : @graph.CheckedMean,
) -> GraphCount raise Stop {
  let options = @graph.mean_options(op)
  let entries = step.connections.entries
  spend(b, step.source, entries.length())
  let mut known_nodes = true
  let mut known_edges = true
  for i in 0..<entries.length() {
    if @graph.mean_weight_at(options, i).unwrap() == 0.0 {
      continue
    }
    let value = graph_count_at(entries[i].target, graphs)
    if value.bind(v => v.nodes) is None {
      known_nodes = false
    }
    if value.bind(v => v.edges) is None {
      known_edges = false
    }
  }
  let mut nodes = if known_nodes { Some(count(0L, true)) } else { None }
  let mut edges = if known_edges { Some(count(0L, true)) } else { None }
  spend(b, step.source, entries.length())
  for i in 0..<entries.length() {
    if @graph.mean_weight_at(options, i).unwrap() == 0.0 {
      continue
    }
    let value = graph_count_at(entries[i].target, graphs)
    if known_nodes {
      nodes = sum_counts(step.source, nodes, value.bind(v => v.nodes))
    }
    if known_edges {
      edges = sum_counts(step.source, edges, value.bind(v => v.edges))
    }
  }
  { nodes: reduce_count(nodes), edges: reduce_count(edges), }
}

///|
// Single forward pass over already checked, ordered operand occurrences.
fn derive_row_counts(
  b : Budget,
  steps : Array[CheckedStep],
  joins : Array[JoinEvidence?],
  inputs : Array[ProducedInput?],
) -> (Array[RowCount?], Array[GraphCount?]) raise Stop {
  let result : CountTable[RowCount] = {
    inputs: inputs.map(v => v.bind(p => p.rows)),
    steps: [],
  }
  let graphs : CountTable[GraphCount] = {
    inputs: inputs.map(v => v.bind(p => p.graph)),
    steps: [],
  }
  for step in steps {
    spend(b, step.source, 1)
    let input = step.input.bind(t => count_at(t, result))
    let graph_input = step.input.bind(t => graph_count_at(t, graphs))
    let graph_output = match step.operation {
      GraphMean(op) => Some(mean_graph_count(b, step, graphs, op))
      GraphUnion(_) => {
        spend(b, step.source, step.connections.entries.length())
        let mut known_nodes = true
        let mut known_edges = true
        for entry in step.connections.entries {
          let other = graph_count_at(entry.target, graphs)
          if other.bind(v => v.nodes) is None {
            known_nodes = false
          }
          if other.bind(v => v.edges) is None {
            known_edges = false
          }
        }
        let mut nodes = if known_nodes { Some(count(0L, true)) } else { None }
        let mut edges = if known_edges { Some(count(0L, true)) } else { None }
        spend(b, step.source, step.connections.entries.length())
        for entry in step.connections.entries {
          let other = graph_count_at(entry.target, graphs)
          if known_nodes {
            nodes = sum_counts(step.source, nodes, other.bind(v => v.nodes))
          }
          if known_edges {
            edges = sum_counts(step.source, edges, other.bind(v => v.edges))
          }
        }
        Some({ nodes: reduce_count(nodes), edges: reduce_count(edges), })
      }
      GraphConstruction(nodes~, edges~, ..) => {
        let edges = reduce_count(count_at(edges, result))
        let nodes = match nodes {
          Some(t) => reduce_count(count_at(t, result))
          None => product_counts(step.source, edges, Some(count(2L, true)))
        }
        Some({
          nodes,
          edges: if nodes is Some({ upper: 0L, .. }) {
            Some(count(0L, true))
          } else {
            edges
          },
        })
      }
      Graph(v) =>
        if @graph.operation(v) == NormalizeGraph {
          graph_input
        } else {
          None
        }
      Subgraph(_) =>
        graph_input.map(v => {
          nodes: reduce_count(v.nodes),
          edges: reduce_count(v.edges),
        })
      GraphStructural(right~, checked~) =>
        if @graph.structural_operation(checked) == Subtract {
          graph_input.map(v => {
            nodes: reduce_count(v.nodes),
            edges: reduce_count(v.edges),
          })
        } else {
          let other = graph_count_at(right, graphs)
          Some({
            nodes: reduce_count(
              sum_counts(
                step.source,
                graph_input.bind(v => v.nodes),
                other.bind(v => v.nodes),
              ),
            ),
            edges: reduce_count(
              sum_counts(
                step.source,
                graph_input.bind(v => v.edges),
                other.bind(v => v.edges),
              ),
            ),
          })
        }
      _ => None
    }
    let next = match step.operation {
      Values(v) => Some(count(@values.row_count(v).to_int64(), true))
      TimeSeries(v) => @series.known_row_count(v).map(n => count(n, true))
      Calendar(v) =>
        match @calendar.cardinality(v) {
          PreserveInput => input
          AtMost(n) => Some(count(n.to_int64(), false))
        }
      Unary(op) | WindowGroup(op) => unary_count(step.source, input, op)
      Vector(_) | Infer(_) => input
      Projection(v) =>
        match @projection.operation(v) {
          Events | Vectors => input
          NodeRows => graph_input.bind(v => v.nodes)
          EdgeRows => graph_input.bind(v => v.edges)
        }
      Graph(v) =>
        match @graph.operation(v) {
          Degree | Components => graph_input.bind(v => v.nodes)
          GraphBounds => graph_report_count(step.source, graph_input, v)
          _ => None
        }
      GraphEquality(_) | GraphDiff(_) => Some(count(1L, true))
      Reach(checked) =>
        if @graph.reach_start(checked) is @graph.SingleReachStart(_) {
          reduce_count(graph_input.bind(g => g.nodes))
        } else {
          None // A selector may emit one row per selected start and graph node.
        }
      Traverse(selector~, checked~) => {
        let nodes = graph_input.bind(g => g.nodes)
        let starts = selector_count(
          @graph.traverse_start(checked),
          selector,
          result,
          nodes,
        )
        if @graph.traverse_emission(checked) == TraversedNodes {
          reduce_count(product_counts(step.source, starts, nodes))
        } else if starts is Some({ upper: 0L, .. }) ||
          nodes is Some({ upper: 0L, .. }) {
          Some(count(0L, true))
        } else {
          None // Simple-path enumeration needs a separate law or enforced ceiling.
        }
      }
      Shortest(source_selector~, target_selector~, checked~) => {
        let nodes = graph_input.bind(g => g.nodes)
        let left = endpoint_count(
          @graph.shortest_endpoint(checked, Left),
          source_selector,
          result,
          nodes,
        )
        let right = endpoint_count(
          @graph.shortest_endpoint(checked, Right),
          target_selector,
          result,
          nodes,
        )
        match @graph.shortest_selection(checked) {
          EachPair => reduce_count(product_counts(step.source, left, right))
          NearestPerSource =>
            if right is Some({ upper: 0L, .. }) {
              Some(count(0L, true))
            } else {
              reduce_count(left)
            }
          NearestPair =>
            Some(
              count(
                if left is Some({ upper: 0L, .. }) ||
                  right is Some({ upper: 0L, .. }) {
                  0L
                } else {
                  1L
                },
                false,
              ),
            )
        }
      }
      GraphMatch(v) =>
        reduce_count(
          graph_input.bind(g => {
            if @graph.match_entity(v) == Nodes {
              g.nodes
            } else {
              g.edges
            }
          }),
        )
      Event(v) =>
        match @event.options(v) {
          ToEvents | Session(_) | Watermark(_, Mark) => input
          Dedupe(_) | Watermark(_, Drop) => reduce_count(input)
        }
      Window(v) => window_count(step.source, input, @window.options(v))
      Pool(_) => reduce_count(input)
      Nearest(queries~, checked~) => {
        let k = @vector.nearest_k(
          @vector.nearest_pair_options(@vector.nearest_pair(checked)),
        )
        product_counts(
          step.source,
          count_at(queries, result),
          slice_count(input, Some(k), Some(0L)),
        )
      }
      TextRank(queries~, checked~) => {
        let k = @vector.text_rank_k(@vector.text_rank_options(checked)).to_int64()
        // Zero-score documents are omitted, unlike nearest's full ranking.
        reduce_count(
          product_counts(
            step.source,
            count_at(queries, result),
            slice_count(input, Some(k), Some(0L)),
          ),
        )
      }
      Ranking(v) => ranking_count(b, step, result, v)
      Nest(_) => input
      Join(right~, checked~) =>
        join_count(
          step.source,
          input,
          count_at(right, result),
          @join.kind(checked),
          left_unique=join_uniqueness(joins[result.steps.length()].unwrap()).0,
          right_unique=join_uniqueness(joins[result.steps.length()].unwrap()).1,
        )
      IntervalJoin(right~, checked~) =>
        join_count(
          step.source,
          input,
          count_at(right, result),
          @join.interval_kind(checked),
        )
      Append(right~, ..) =>
        sum_counts(step.source, input, count_at(right, result))
      CrossJoin(right~, checked~) =>
        if @join.cross_requires_one_right_row(checked) {
          input
        } else {
          product_counts(step.source, input, count_at(right, result))
        }
      Set(right~, checked~) =>
        set_count(
          input,
          count_at(right, result),
          @set.operation(checked),
          @set.duplicates(checked),
          @schema.field_count(@set.output_schema(checked)) == 0,
        )
      AsOfJoin(checked~, ..) =>
        if @join.asof_kind(checked) == Left {
          input
        } else {
          reduce_count(input)
        }
      _ => None
    }
    result.steps.push(next)
    graphs.steps.push(graph_output)
  }
  (result.steps, graphs.steps)
}

///|
pub fn graph_count(value : CheckedPipeline, target : Target) -> GraphCount? {
  match target {
    Input(i) => value.produced_inputs.get(i).bind(v => v.bind(p => p.graph))
    Step(i) => value.graph_counts.get(i).bind(v => v)
  }
}

///|
/// Scope is this pipeline and target; retain its operations and obligations.
/// Unknown input counts and unimplemented transfer rules return None, not zero.
pub fn row_count(value : CheckedPipeline, target : Target) -> RowCount? {
  match target {
    Input(i) => value.produced_inputs.get(i).bind(v => v.bind(p => p.rows))
    Step(i) => value.row_counts.get(i).bind(v => v)
  }
}
