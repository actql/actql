///|
struct AggregateOrder {
  aggregate : @relation.CheckedAggregate
  completion : SortCompletion?
  inherited : LogicalOrder?
}

///|
struct GroupOrders {
  consumer : CheckedStep
  input : Target
  orders : Array[AggregateOrder?]
  work : Int
  text : Int
}

///|
pub fn group_orders_consumer(v : GroupOrders) -> CheckedStep {
  v.consumer
}

///|
pub fn group_orders_input(v : GroupOrders) -> Target {
  v.input
}

///|
pub fn group_orders_count(v : GroupOrders) -> Int {
  v.orders.length()
}

///|
/// Unordered aggregates and invalid indices have no local order entry.
pub fn group_order_at(v : GroupOrders, index : Int) -> AggregateOrder? {
  v.orders.get(index).bind(x => x)
}

///|
pub fn group_orders_usage(v : GroupOrders) -> (Int, Int) {
  (v.work, v.text)
}

///|
pub fn aggregate_order_source(v : AggregateOrder) -> @relation.CheckedAggregate {
  v.aggregate
}

///|
pub fn aggregate_order_completion(v : AggregateOrder) -> SortCompletion? {
  v.completion
}

///|
pub fn aggregate_order_inherited(v : AggregateOrder) -> LogicalOrder? {
  v.inherited
}

///|
/// Atomic local-order resolution for all group/window_group aggregates. It does
/// not resolve group output order, execute filters, or validate result limits.
pub fn resolve_group_orders(
  p : CheckedPipeline,
  index : Int,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[GroupOrders, Issue] {
  try {
    if max_work < 0 || max_text_bytes < 0 {
      fail(p.source, InvalidLimits)
    }
    guard p.steps.get(index) is Some(consumer) else {
      fail(p.source, InvalidBody)
    }
    let op = match consumer.operation {
      Unary(op) | WindowGroup(op) => op
      _ => fail(consumer.source, InvalidBody)
    }
    guard @relation.group(op) is Some(group) else {
      fail(consumer.source, InvalidBody)
    }
    let input = consumer.input.unwrap()
    let source = @relation.source(op)
    let b : Budget = {
      limits: {
        max_steps: 0,
        max_work,
        max_text_bytes,
        max_nodes: 0,
        max_tokens: 0,
        max_depth: 0,
      },
      work: max_work,
      text: max_text_bytes,
      nodes: 0,
      tokens: 0,
    }
    let n = @relation.aggregate_count(group)
    spend(b, source, 1)
    spend(b, source, n)
    let mut key : @evidence.KeyedRelation? = None
    let mut selected = false
    let inherited = logical_order(p, input)
    let orders : Array[AggregateOrder?] = []
    for i in 0..<n {
      let aggregate = @relation.aggregate_at(group, i).unwrap()
      let count = @relation.aggregate_order_count(aggregate)
      if count == 0 {
        orders.push(None)
        continue
      }
      if !selected {
        key = select_order_key(b, op, candidate_keys(p, input))
        selected = true
      }
      let source = @relation.aggregate_source(aggregate)
      if key is Some(key) {
        let completion = complete_key_order(b, source, key, count, j => {
          @relation.aggregate_order_at(aggregate, j)
        })
        orders.push(
          Some({ aggregate, completion: Some(completion), inherited: None, }),
        )
      } else {
        // array_agg's explicit candidate-key requirement is stronger than a
        // generic total-order requirement; an input sequence cannot replace it.
        if @relation.aggregate_function(aggregate) == @relation.ArrayAgg ||
          inherited is None {
          fail(source, UnresolvedOrder)
        }
        spend(b, source, count)
        for j in 0..<count {
          let term = @relation.aggregate_order_at(aggregate, j).unwrap()
          charge(b, term.source, @schema.reference_name(term.field))
        }
        orders.push(Some({ aggregate, completion: None, inherited, }))
      }
    }
    Ok({
      consumer,
      input,
      orders,
      work: max_work - b.work,
      text: max_text_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
