///|
pub(all) enum ApplicationClosureIssue {
  InvalidLimits
  CoverageCount(expected~ : Int, actual~ : Int)
  WorkLimit(Int)
  ForeignPipeline(Int)
} derive(Eq, Debug)

///|
/// Coverage of supported capacity applications at every producer occurrence.
/// Does not certify unsupported sources, consumers or runnable Plans.
struct ApplicationClosure {
  orders : @pipeline.ContextualClosure
  entries : Array[ApplicationCoverage]
  work : Int
}

///|
pub fn check_application_closure(
  orders : @pipeline.ContextualClosure,
  applications : Array[ApplicationCoverage],
  max_work~ : Int,
) -> Result[ApplicationClosure, ApplicationClosureIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let n = @pipeline.contextual_closure_count(orders)
  if applications.length() != n {
    return Err(CoverageCount(expected=n, actual=applications.length()))
  }
  let mut work = 0
  for i, app in applications {
    if work >= max_work {
      return Err(WorkLimit(i))
    }
    work += 1
    if app.work > max_work - work {
      return Err(WorkLimit(i))
    }
    work += app.work
    let expected = @pipeline.contextual_orders_pipeline(
      @pipeline.contextual_closure_at(orders, i).unwrap(),
    )
    if !physical_equal(expected, app.sources.graph.pipeline) {
      return Err(ForeignPipeline(i))
    }
  }
  Ok({ orders, entries: applications.copy(), work, })
}

///|
pub fn application_closure_orders(
  v : ApplicationClosure,
) -> @pipeline.ContextualClosure {
  v.orders
}

///|
pub fn application_closure_at(
  v : ApplicationClosure,
  index : Int,
) -> ApplicationCoverage? {
  v.entries.get(index)
}

///|
pub fn application_closure_work(v : ApplicationClosure) -> Int {
  v.work
}
