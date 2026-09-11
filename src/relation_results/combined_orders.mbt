///|
pub(all) struct OrderCheckLimits {
  max_steps : Int
  max_results : Int
  max_work : Int
  max_text_bytes : Int
}

///|
pub(all) enum OrderCheckIssue {
  PipelineOrder(@pipeline.Issue)
  ProducerOrder(@pipeline.ProducerOrderIssue)
  ResultOrder(Issue)
}

///|
/// Contextual order strategies across producer ancestry and root publications.
/// Conditional evidence only: capacity, binding and execution remain separate.
struct CheckedOrders {
  contextual : @pipeline.ContextualClosure
  publication : PublicationOrders
  work : Int
  text_bytes : Int
}

///|
/// Resolve every producer step and every root Result atomically under one budget.
/// The pipeline comes from results, so callers cannot pair foreign contexts.
pub fn resolve_all_orders(
  results : CheckedResults,
  limits : OrderCheckLimits,
) -> Result[CheckedOrders, OrderCheckIssue] {
  try {
    if limits.max_steps < 0 ||
      limits.max_results < 0 ||
      limits.max_work < 0 ||
      limits.max_text_bytes < 0 {
      fail(results.source, InvalidLimits)
    }
    if results.definitions.length() > limits.max_results ||
      @pipeline.step_count(results.pipeline) > limits.max_steps {
      fail(results.source, BudgetExceeded)
    }
    let contextual = match
      @pipeline.resolve_contextual_closure(
        results.pipeline,
        max_steps=limits.max_steps,
        max_work=limits.max_work,
        max_text_bytes=limits.max_text_bytes,
      ) {
      Ok(v) => v
      Err(e) =>
        return Err(
          if physical_equal(e.pipeline, results.pipeline) {
            PipelineOrder(e.issue)
          } else {
            ProducerOrder(e)
          },
        )
    }
    let (step_work, step_text) = @pipeline.contextual_closure_usage(contextual)
    let publication = match
      resolve_publication_orders(
        results,
        max_results=limits.max_results,
        max_work=limits.max_work - step_work,
        max_text_bytes=limits.max_text_bytes - step_text,
      ) {
      Ok(v) => v
      Err(e) => raise Stop(e)
    }
    let (result_work, result_text) = publication_orders_usage(publication)
    Ok({
      contextual,
      publication,
      work: step_work + result_work,
      text_bytes: step_text + result_text,
    })
  } catch {
    Stop(e) => Err(ResultOrder(e))
  }
}

///|
pub fn checked_contextual_orders(
  orders : CheckedOrders,
) -> @pipeline.ContextualOrders {
  @pipeline.contextual_closure_root(orders.contextual)
}

///|
pub fn checked_producer_orders(
  orders : CheckedOrders,
) -> @pipeline.ContextualClosure {
  orders.contextual
}

///|
pub fn checked_publication_orders(orders : CheckedOrders) -> PublicationOrders {
  orders.publication
}

///|
pub fn checked_orders_usage(orders : CheckedOrders) -> (Int, Int) {
  (orders.work, orders.text_bytes)
}
