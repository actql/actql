///|
/// All named Result order strategies, not permission to publish their data.
struct PublicationOrders {
  results : CheckedResults
  orders : Array[PublicationOrder]
  work : Int
  text_bytes : Int
}

///|
pub fn resolve_publication_orders(
  results : CheckedResults,
  max_results~ : Int,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[PublicationOrders, Issue] {
  try {
    if max_results < 0 || max_work < 0 || max_text_bytes < 0 {
      fail(results.source, InvalidLimits)
    }
    if results.definitions.length() > max_results {
      fail(results.source, BudgetExceeded)
    }
    let orders : Array[PublicationOrder] = []
    let mut work = max_work
    let mut text = max_text_bytes
    for i in 0..<results.definitions.length() {
      let order = match
        resolve_publication_order(
          results,
          i,
          max_work=work,
          max_text_bytes=text,
        ) {
        Ok(value) => value
        Err(e) => raise Stop(e)
      }
      work -= order.work
      text -= order.text_bytes
      orders.push(order)
    }
    Ok({
      results,
      orders,
      work: max_work - work,
      text_bytes: max_text_bytes - text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn publication_orders_results(p : PublicationOrders) -> CheckedResults {
  p.results
}

///|
pub fn publication_orders_count(p : PublicationOrders) -> Int {
  p.orders.length()
}

///|
pub fn publication_order_at(
  p : PublicationOrders,
  index : Int,
) -> PublicationOrder? {
  p.orders.get(index)
}

///|
pub fn publication_orders_usage(p : PublicationOrders) -> (Int, Int) {
  (p.work, p.text_bytes)
}
