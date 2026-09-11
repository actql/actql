///|
pub(all) enum WiringIssue {
  InvalidLimits
  ForeignSource
  ForeignOrders(Int)
  InconsistentUsage
  BudgetExceeded
} derive(Eq, Debug)

///|
struct WiredStages {
  stages : StageContexts
  wiring : @stage_results.ResultWiring
  work : Int
  text : Int
}

///|
/// Attach already validated Result imports and root exports to the exact
/// publication order owners retained by all stage contexts. Ordinary/receipt
/// input contracts, static discharge and execution authorization remain separate.
pub fn attach_result_wiring(
  stages : StageContexts,
  wiring : @stage_results.ResultWiring,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[WiredStages, WiringIssue] {
  if max_work < 0 || max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let source = @stages.operations_source(
    @stages.bound_operations(stages.operations),
  )
  if !physical_equal(@stage_results.wiring_source(wiring), source) {
    return Err(ForeignSource)
  }
  if stages.work > max_work || stages.text > max_text_bytes {
    return Err(BudgetExceeded)
  }
  let (wire_work, wire_text) = @stage_results.wiring_usage(wiring)
  let mut added_work = wire_work
  let mut added_text = wire_text
  let mut work = stages.work
  for i in 0..<stages.contexts.length() {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let ports = @stage_results.stage_port_publications(
      @stage_results.wiring_stage_at(wiring, i).unwrap(),
    )
    let expected = stages.contexts[i].context.orders
    if !physical_equal(@results.ports_orders(ports), expected) {
      return Err(ForeignOrders(i))
    }
    // Wiring includes prepared-port costs, including these same prior orders.
    // Subtract only after verifying the exact shared owner, not equal amounts.
    let (shared_work, shared_text) = @results.checked_orders_usage(expected)
    if shared_work > added_work || shared_text > added_text {
      return Err(InconsistentUsage)
    }
    added_work -= shared_work
    added_text -= shared_text
  }
  if added_work > max_work - work || added_text > max_text_bytes - stages.text {
    return Err(BudgetExceeded)
  }
  Ok({
    stages,
    wiring,
    work: work + added_work,
    text: stages.text + added_text,
  })
}

///|
pub fn wired_stage_contexts(v : WiredStages) -> StageContexts {
  v.stages
}

///|
pub fn result_wiring(v : WiredStages) -> @stage_results.ResultWiring {
  v.wiring
}

///|
pub fn wired_usage(v : WiredStages) -> (Int, Int) {
  (v.work, v.text)
}
