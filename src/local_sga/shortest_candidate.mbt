///|
// This is a cursor inside the existing path owner, not an execution owner or
// public number representation. Overrange is never emitted as Infinity.
priv enum ShortestCost {
  FiniteShortestCost(Double)
  OverrangeShortestCost
}

///|
pub(all) enum ShortestCandidateIssue {
  InvalidShortestCost
  ShortestCandidateInputUnavailable
  ShortestCandidateWorkLimit
  InvalidShortestCandidateCursor
  SelectedShortestOverrange
} derive(Eq, Debug)

///|
fn shortest_cost_add(
  cost : ShortestCost,
  weight : Double,
) -> Result[ShortestCost, ShortestCandidateIssue] {
  if weight.is_nan() || weight.is_inf() || weight < 0.0 {
    return Err(InvalidShortestCost)
  }
  match cost {
    OverrangeShortestCost => Ok(OverrangeShortestCost)
    FiniteShortestCost(value) => {
      if value.is_nan() || value.is_inf() || value < 0.0 {
        return Err(InvalidShortestCost)
      }
      // One binary64 addition per edge, in authored path order. An exact
      // accumulator followed by one rounding would implement a different law.
      let next = value + weight
      Ok(
        if next.is_inf() {
          OverrangeShortestCost
        } else {
          FiniteShortestCost(next)
        },
      )
    }
  }
}

///|
fn shortest_edge_weight(
  source : GraphReadSource,
  checked : @graph_type.CheckedShortest,
  edge : Int,
) -> Result[Double, ShortestCandidateIssue] {
  if @graph_type.shortest_weight(checked) is None {
    return Ok(1.0)
  }
  guard graph_read_edge_definition(source, edge) is Some(definition) &&
    @graph_type.shortest_weight_position(checked, definition) is Some(position) &&
    graph_read_edge_property(source, edge, position) is Some(value) else {
    return Err(ShortestCandidateInputUnavailable)
  }
  guard value.value is @value.Number(weight) &&
    !weight.is_nan() &&
    !weight.is_inf() &&
    weight >= 0.0 else {
    return Err(InvalidShortestCost)
  }
  Ok(weight)
}

///|
fn shortest_cost_compare(left : ShortestCost, right : ShortestCost) -> Int {
  match (left, right) {
    (OverrangeShortestCost, OverrangeShortestCost) => 0
    (OverrangeShortestCost, _) => 1
    (_, OverrangeShortestCost) => -1
    (FiniteShortestCost(left), FiniteShortestCost(right)) =>
      if left < right {
        -1
      } else if left > right {
        1
      } else {
        0
      }
  }
}

///|
priv struct ShortestCandidate {
  path : TraversalPath
  cost : ShortestCost
}

///|
priv enum ShortestComparisonPhase {
  Cost
  Hops
  Source
  Target
  Nodes
  Edges
}

///|
priv struct ShortestComparison {
  source : GraphReadSource
  left : ShortestCandidate
  right : ShortestCandidate
  mut phase : ShortestComparisonPhase
  mut index : Int
  mut identity_unit : Int
  mut work_remaining : Int
  mut terminal : Bool
}

///|
priv enum ShortestComparisonPoll {
  ShortestComparisonContinue(Int)
  ShortestComparisonComplete(Int, Int)
  ShortestComparisonFailed(ShortestCandidateIssue, Int)
}

///|
fn prepare_shortest_comparison(
  source : GraphReadSource,
  left : ShortestCandidate,
  right : ShortestCandidate,
  max_work : Int,
) -> Result[ShortestComparison, ShortestCandidateIssue] {
  if max_work < 0 ||
    left.path.nodes.is_empty() ||
    right.path.nodes.is_empty() ||
    left.path.nodes.length() - 1 != left.path.edges.length() ||
    right.path.nodes.length() - 1 != right.path.edges.length() {
    return Err(InvalidShortestCandidateCursor)
  }
  // Candidates are private immutable paths of one owner. No input retention or
  // new read authority is acquired by this comparison cursor.
  Ok({
    source,
    left,
    right,
    phase: Cost,
    index: 0,
    identity_unit: 0,
    work_remaining: max_work,
    terminal: false,
  })
}

///|
fn cleanup_shortest_comparison(cursor : ShortestComparison) -> Unit {
  cursor.terminal = true
  cursor.identity_unit = 0
}

///|
fn advance_shortest_comparison(
  cursor : ShortestComparison,
  quantum : Int,
) -> ShortestComparisonPoll {
  if cursor.terminal || quantum < 1 {
    return ShortestComparisonFailed(InvalidShortestCandidateCursor, 0)
  }
  let mut work = 0
  while work < quantum {
    if !graph_read_available(cursor.source) {
      cursor.terminal = true
      return ShortestComparisonFailed(ShortestCandidateInputUnavailable, work)
    }
    if cursor.work_remaining == 0 {
      cursor.terminal = true
      return ShortestComparisonFailed(ShortestCandidateWorkLimit, work)
    }
    let left = cursor.left.path
    let right = cursor.right.path
    let mut order = None
    let mut done = false
    cursor.work_remaining -= 1
    work += 1
    match cursor.phase {
      Cost => {
        order = Some(shortest_cost_compare(cursor.left.cost, cursor.right.cost))
        cursor.phase = Hops
      }
      Hops => {
        order = Some(left.edges.length().compare(right.edges.length()))
        cursor.phase = Source
      }
      Source | Target | Nodes | Edges => {
        let (left_key, right_key) = match cursor.phase {
          Source =>
            (
              graph_read_node_identity_order_key(cursor.source, left.nodes[0]),
              graph_read_node_identity_order_key(cursor.source, right.nodes[0]),
            )
          Target =>
            (
              graph_read_node_identity_order_key(
                cursor.source,
                left.nodes.last().unwrap(),
              ),
              graph_read_node_identity_order_key(
                cursor.source,
                right.nodes.last().unwrap(),
              ),
            )
          Nodes =>
            (
              graph_read_node_identity_order_key(
                cursor.source,
                left.nodes[cursor.index],
              ),
              graph_read_node_identity_order_key(
                cursor.source,
                right.nodes[cursor.index],
              ),
            )
          Edges => {
            if cursor.index == left.edges.length() {
              cursor.terminal = true
              return ShortestComparisonComplete(0, work)
            }
            (
              graph_read_edge_identity_order_key(
                cursor.source,
                left.edges[cursor.index],
              ),
              graph_read_edge_identity_order_key(
                cursor.source,
                right.edges[cursor.index],
              ),
            )
          }
          Cost | Hops => abort("non-identity shortest comparison phase")
        }
        guard left_key is Some(left_key) && right_key is Some(right_key) else {
          cursor.terminal = true
          return ShortestComparisonFailed(
            ShortestCandidateInputUnavailable,
            work,
          )
        }
        let (result, next) = graph_identity_compare_unit(
          left_key,
          right_key,
          cursor.identity_unit,
        )
        cursor.identity_unit = next
        order = result
        if result is Some(0) {
          cursor.identity_unit = 0
          match cursor.phase {
            Source => cursor.phase = Target
            Target => {
              cursor.phase = Nodes
              cursor.index = 0
            }
            Nodes => {
              cursor.index += 1
              if cursor.index == left.nodes.length() {
                cursor.phase = Edges
                cursor.index = 0
              }
            }
            Edges => {
              cursor.index += 1
              done = cursor.index == left.edges.length()
            }
            Cost | Hops => ()
          }
        }
      }
    }
    if order is Some(order) && (order != 0 || done) {
      cursor.terminal = true
      return ShortestComparisonComplete(order, work)
    }
  }
  ShortestComparisonContinue(work)
}
