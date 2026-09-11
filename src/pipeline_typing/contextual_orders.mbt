///|
pub enum ContextualOrder {
  InputSequence(InputOrderResolution)
  KeyCompletion(SortCompletion)
  TakeSequence(LogicalOrder)
  AnalyticPosition(AnalyticPositionOrder)
  Aggregates(GroupOrders)
  NestedRows(NestOrder)
}

///|
struct ContextualOrders {
  pipeline : CheckedPipeline
  entries : Array[Array[ContextualOrder]]
  work : Int
  text : Int
}

///|
/// Resolves every contextual order consumer, including unused named branches.
/// Retains conditional evidence; does not discharge execution or capacity checks.
pub fn resolve_contextual_orders(
  p : CheckedPipeline,
  max_steps~ : Int,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[ContextualOrders, Issue] {
  try {
    if max_steps < 0 || max_work < 0 || max_text_bytes < 0 {
      fail(p.source, InvalidLimits)
    }
    if p.steps.length() > max_steps {
      fail(p.source, BudgetExceeded)
    }
    let mut work = max_work
    let mut text = max_text_bytes
    let entries : Array[Array[ContextualOrder]] = []
    for i in 0..<p.steps.length() {
      let step = p.steps[i]
      if work == 0 {
        fail(step.source, BudgetExceeded)
      }
      work -= 1
      let entry : Array[ContextualOrder] = []
      match step.operation {
        Unary(op) | WindowGroup(op) => {
          if @relation.existing_order_requirement(op) is Some(_) {
            guard resolve_existing_input_order(p, i) is Some(order) else {
              fail(step.source, UnresolvedOrder)
            }
            entry.push(InputSequence(order))
          }
          match @relation.operation(op) {
            Lag => {
              guard lag_order_completion(p, i) is Some(order) else {
                fail(step.source, UnresolvedOrder)
              }
              entry.push(KeyCompletion(order))
            }
            Sort | TopK | TopKBy if @relation.ranking_term_count(op) > 0 => {
              guard logical_order(p, Step(i)).bind(order_sort_completion)
                is Some(order) else {
                fail(step.source, UnresolvedOrder)
              }
              entry.push(KeyCompletion(order))
            }
            Take => {
              guard take_order(p, i) is Some(order) else {
                fail(step.source, UnresolvedOrder)
              }
              entry.push(TakeSequence(order))
            }
            Analytic =>
              for pending in @relation.pending_validations(op) {
                if work == 0 {
                  fail(pending.source, BudgetExceeded)
                }
                work -= 1
                if pending.kind is @relation.AnalyticPositionOrder {
                  guard analytic_position_order(p, i) is Some(order) else {
                    fail(pending.source, UnresolvedOrder)
                  }
                  entry.push(AnalyticPosition(order))
                }
              }
            _ => ()
          }
          if @relation.group(op) is Some(_) {
            let order = match
              resolve_group_orders(p, i, max_work=work, max_text_bytes=text) {
              Ok(order) => order
              Err(e) => raise Stop(e)
            }
            let (used_work, used_text) = group_orders_usage(order)
            work -= used_work
            text -= used_text
            entry.push(Aggregates(order))
          }
        }
        Nest(_) => {
          let order = match
            resolve_nest_order(p, i, max_work=work, max_text_bytes=text) {
            Ok(order) => order
            Err(e) => raise Stop(e)
          }
          let (used_work, used_text) = nest_order_usage(order)
          work -= used_work
          text -= used_text
          entry.push(NestedRows(order))
        }
        _ => ()
      }
      entries.push(entry)
    }
    Ok({
      pipeline: p,
      entries,
      work: max_work - work,
      text: max_text_bytes - text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn contextual_orders_pipeline(v : ContextualOrders) -> CheckedPipeline {
  v.pipeline
}

///|
pub fn contextual_orders_count(v : ContextualOrders) -> Int {
  v.entries.length()
}

///|
pub fn contextual_orders_at(
  v : ContextualOrders,
  index : Int,
) -> Array[ContextualOrder]? {
  v.entries.get(index).map(entries => entries.copy())
}

///|
pub fn contextual_orders_usage(v : ContextualOrders) -> (Int, Int) {
  (v.work, v.text)
}
