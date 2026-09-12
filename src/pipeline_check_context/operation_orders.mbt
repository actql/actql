///|
pub(all) enum OperationOrderIssue {
  InvalidLimits
  BudgetExceeded
  ForeignOwner(Int)
  MissingResolution(Int, @pipeline.OperationOrderDemand)
  AmbiguousResolution(Int)
} derive(Eq, Debug)

///|
pub struct OperationOrderLink {
  requirement_index : Int
  site : OperationRequirementSite
  resolution : @pipeline.ContextualOrder
}

///|
struct ProgramOperationOrders {
  requirements : ProgramOperationRequirements
  links : Array[OperationOrderLink]
  work : Int
}

///|
// Bounded slots indexed once per step, avoiding a resolution-array scan for
// every ordered aggregate or repeated requirement.
priv struct OperationOrderIndex {
  mut input : @pipeline.ContextualOrder?
  mut key : @pipeline.ContextualOrder?
  mut sort : @pipeline.ContextualOrder?
  mut take : @pipeline.ContextualOrder?
  mut analytic : @pipeline.ContextualOrder?
  mut aggregates : @pipeline.ContextualOrder?
  mut nest : @pipeline.ContextualOrder?
}

///|
fn empty_operation_orders() -> OperationOrderIndex {
  {
    input: None,
    key: None,
    sort: None,
    take: None,
    analytic: None,
    aggregates: None,
    nest: None,
  }
}

///|
fn retain_operation_order(
  v : OperationOrderIndex,
  order : @pipeline.ContextualOrder,
) -> Bool {
  let previous = match order {
    InputSequence(_) => {
      let old = v.input
      v.input = Some(order)
      old
    }
    KeyCompletion(_) => {
      let old = v.key
      v.key = Some(order)
      old
    }
    SortSequence(_) => {
      let old = v.sort
      v.sort = Some(order)
      old
    }
    TakeSequence(_) => {
      let old = v.take
      v.take = Some(order)
      old
    }
    AnalyticPosition(_) => {
      let old = v.analytic
      v.analytic = Some(order)
      old
    }
    Aggregates(_) => {
      let old = v.aggregates
      v.aggregates = Some(order)
      old
    }
    NestedRows(_) => {
      let old = v.nest
      v.nest = Some(order)
      old
    }
  }
  previous is None
}

///|
fn select_operation_order(
  v : OperationOrderIndex,
  demand : @pipeline.OperationOrderDemand,
) -> @pipeline.ContextualOrder? {
  match demand {
    CompleteOrder => {
      // Exactly one of authored sort, top-k completion, or group-local orders.
      let choices = (if v.sort is Some(_) { 1 } else { 0 }) +
        (if v.key is Some(_) { 1 } else { 0 }) +
        (if v.aggregates is Some(_) { 1 } else { 0 })
      if choices != 1 {
        None
      } else {
        match v.sort {
          Some(_) => v.sort
          None =>
            match v.key {
              Some(_) => v.key
              None => v.aggregates
            }
        }
      }
    }
    StableSequence =>
      match (v.take, v.input) {
        (Some(_), None) => v.take
        (None, Some(InputSequence(r))) =>
          if @pipeline.input_order_requirement(r) is StableInputOrder {
            v.input
          } else {
            None
          }
        _ => None
      }
    PrefixSequence =>
      match v.input {
        Some(InputSequence(r)) =>
          if @pipeline.input_order_requirement(r) is WatermarkPrefixOrder {
            v.input
          } else {
            None
          }
        _ => None
      }
    LagKey => v.key
    AnalyticPositions => v.analytic
    NestedRows => v.nest
  }
}

///|
/// Link contextual order requirements only to the original producer resolution.
/// No order is re-inferred and conditional runtime evidence remains conditional.
pub fn link_program_operation_orders(
  requirements : ProgramOperationRequirements,
  max_work : Int,
  max_links : Int,
) -> Result[ProgramOperationOrders, OperationOrderIssue] {
  if max_work < 0 || max_links < 0 {
    return Err(InvalidLimits)
  }
  let mut work = requirements.work
  if work >= max_work {
    return Err(BudgetExceeded)
  }
  work += 1
  let stages = requirements.expressions.identity.sources.operations.preparation.profiles.context.selected.context.wired.stages
  let links : Array[OperationOrderLink] = []
  let mut previous = (-1, -1, -1)
  let mut indexed = empty_operation_orders()
  for i in 0..<requirements.entries.length() {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let site = requirements.entries[i]
    guard @pipeline.operation_order_demand(site.requirement) is Some(demand) else {
      continue
    }
    let location = (site.stage, site.producer_visit, site.step)
    if location != previous {
      let closure = @results.checked_producer_orders(
        stages.contexts[site.stage].context.orders,
      )
      let orders = match
        @pipeline.contextual_closure_at(closure, site.producer_visit) {
        Some(v) => v
        None => return Err(ForeignOwner(i))
      }
      if !physical_equal(
          @pipeline.contextual_orders_pipeline(orders),
          site.pipeline,
        ) {
        return Err(ForeignOwner(i))
      }
      let n = match @pipeline.contextual_order_count(orders, site.step) {
        Some(n) => n
        None => return Err(ForeignOwner(i))
      }
      if work >= max_work || n > max_work - work - 1 {
        return Err(BudgetExceeded)
      }
      work += n + 1
      indexed = empty_operation_orders()
      for j in 0..<n {
        let order = @pipeline.contextual_order_at(orders, site.step, j).unwrap()
        if !retain_operation_order(indexed, order) {
          return Err(AmbiguousResolution(i))
        }
      }
      previous = location
    }
    let resolution = match select_operation_order(indexed, demand) {
      Some(v) => v
      None => return Err(MissingResolution(i, demand))
    }
    if work == max_work || links.length() == max_links {
      return Err(BudgetExceeded)
    }
    work += 1
    links.push({ requirement_index: i, site, resolution, })
  }
  Ok({ requirements, links, work, })
}

///|
pub fn operation_orders_requirements(
  v : ProgramOperationOrders,
) -> ProgramOperationRequirements {
  v.requirements
}

///|
pub fn operation_orders_count(v : ProgramOperationOrders) -> Int {
  v.links.length()
}

///|
pub fn operation_order_link_at(
  v : ProgramOperationOrders,
  index : Int,
) -> OperationOrderLink? {
  v.links.get(index)
}

///|
pub fn operation_orders_work(v : ProgramOperationOrders) -> Int {
  v.work
}
