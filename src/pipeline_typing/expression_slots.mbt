///|
pub struct ExpressionSlot {
  step : Int
  expression : @typing.TypedExpression
}

///|
struct ExpressionSlots {
  pipeline : CheckedPipeline
  entries : Array[ExpressionSlot]
  work : Int
}

///|
pub(all) enum ExpressionSlotIssue {
  InvalidLimits
  WorkLimit
  SlotLimit
} derive(Eq, Debug)

///|
priv struct SlotCollector {
  entries : Array[ExpressionSlot]
  mut remaining : Int
  max_slots : Int
}

///|
priv suberror SlotFailure {
  SlotFailure(ExpressionSlotIssue)
}

///|
fn slot_tick(c : SlotCollector) -> Unit raise SlotFailure {
  if c.remaining == 0 {
    raise SlotFailure(WorkLimit)
  }
  c.remaining -= 1
}

///|
fn slot_add(
  c : SlotCollector,
  step : Int,
  expression : @typing.TypedExpression?,
) -> Unit raise SlotFailure {
  slot_tick(c)
  if expression is Some(expression) {
    if c.entries.length() == c.max_slots {
      raise SlotFailure(SlotLimit)
    }
    c.entries.push({ step, expression, })
  }
}

///|
fn slot_predicate(
  c : SlotCollector,
  step : Int,
  predicate : @graph.CheckedPredicate?,
) -> Unit raise SlotFailure {
  slot_add(c, step, predicate.map(@graph.predicate_expression))
}

///|
/// Enumerate retained typed expression roots in every local step. This does not
/// include non-expression Parameter operands or recursively visit producers.
pub fn collect_expression_slots(
  pipeline : CheckedPipeline,
  max_work~ : Int,
  max_slots~ : Int,
) -> Result[ExpressionSlots, ExpressionSlotIssue] {
  if max_work < 0 || max_slots < 0 {
    return Err(InvalidLimits)
  }
  let c : SlotCollector = { entries: [], remaining: max_work, max_slots, }
  try {
    for step in 0..<pipeline.steps.length() {
      slot_tick(c)
      match pipeline.steps[step].operation {
        Unary(operation) | WindowGroup(operation) =>
          for i in 0..<@relation.binding_count(operation) {
            slot_add(
              c,
              step,
              Some(@relation.binding_at(operation, i).unwrap().expression),
            )
          }
        Sequence(operation) =>
          for i in 0..<@relation.sequence_pattern_count(operation) {
            slot_add(
              c,
              step,
              Some(
                @relation.sequence_pattern_at(operation, i).unwrap().predicate,
              ),
            )
          }
        GraphMatch(operation) =>
          slot_predicate(c, step, @graph.match_predicate(operation))
        Subgraph(checked~, ..) => {
          slot_predicate(
            c,
            step,
            @graph.selector_predicate(@graph.subgraph_nodes(checked)),
          )
          slot_predicate(c, step, @graph.subgraph_edges(checked))
        }
        Traverse(checked~, ..) => {
          slot_predicate(
            c,
            step,
            @graph.selector_predicate(@graph.traverse_start(checked)),
          )
          for i in 0..<@graph.traverse_hop_count(checked) {
            let hop = @graph.traverse_hop_at(checked, i).unwrap()
            slot_predicate(c, step, @graph.hop_predicate(hop, @graph.Edges))
            slot_predicate(c, step, @graph.hop_predicate(hop, @graph.Nodes))
          }
        }
        Shortest(checked~, ..) =>
          for side in [@schema.Left, @schema.Right] {
            let predicate = match @graph.shortest_endpoint(checked, side) {
              @graph.Single(_) => None
              @graph.Selected(selector) => @graph.selector_predicate(selector)
            }
            slot_predicate(c, step, predicate)
          }
        // These checked forms retain scalar/cell operands or field selectors,
        // not general Expression roots. Do not use a catch-all here.
        Join(..)
        | Append(..)
        | Nest(..)
        | Set(..)
        | CrossJoin(..)
        | IntervalJoin(..)
        | AsOfJoin(..)
        | Values(_)
        | TimeSeries(_)
        | Calendar(_)
        | Window(_)
        | Projection(_)
        | Graph(_)
        | Reach(_)
        | GraphEquality(..)
        | GraphDiff(..)
        | GraphApply(..)
        | GraphStructural(..)
        | GraphMean(_)
        | GraphConstruction(..)
        | Vector(_)
        | Nearest(..)
        | Pool(_)
        | Ranking(_)
        | TextRank(_)
        | Event(_) => ()
      }
    }
    Ok({ pipeline, entries: c.entries, work: max_work - c.remaining, })
  } catch {
    SlotFailure(issue) => Err(issue)
  }
}

///|
pub fn expression_slots_pipeline(slots : ExpressionSlots) -> CheckedPipeline {
  slots.pipeline
}

///|
pub fn expression_slot_count(slots : ExpressionSlots) -> Int {
  slots.entries.length()
}

///|
pub fn expression_slot_at(
  slots : ExpressionSlots,
  index : Int,
) -> ExpressionSlot? {
  slots.entries.get(index)
}

///|
pub fn expression_slots_work(slots : ExpressionSlots) -> Int {
  slots.work
}
