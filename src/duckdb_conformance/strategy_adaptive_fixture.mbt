///|
#export_name("strategyFixtureCostedDispatch")
pub fn strategy_fixture_costed_dispatch(
  f : StrategyFixture,
  native_ms : Int64,
) -> @dbhost.StrategyHostDispatch {
  let host = strategy_fixture_dispatch(f)
  let count = @strategy.graph_task_count(f.graph) - 1
  let profiles : Array[@dbhost.DispatchEstimateProfile] = Array::makei(count, _ => {
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(5L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(native_ms),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_capacity: {
      transfer_bytes: 100000L,
      retained_bytes: 4000000L,
      execution_bytes: 268435456L,
    },
    output_rows_per_mille: Some(1000),
  })
  @dbhost.configure_dispatch_estimates(host, profiles, {
    max_offers: count * 2,
    max_strategies: 16,
    max_work: 1000,
    max_revisions: count + 1,
  }).unwrap()
  @dbhost.refresh_dispatch_estimates(host).unwrap()
  host
}

///|
#export_name("strategyFixtureAdaptiveDispatch")
pub fn strategy_fixture_adaptive_dispatch(
  f : StrategyFixture,
) -> @dbhost.StrategyHostDispatch {
  let host = strategy_fixture_dispatch(f)
  let profiles : Array[@dbhost.DispatchEstimateProfile] = Array::makei(3, index => {
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(
          if index == 0 {
            1L
          } else if index == 1 {
            100L
          } else {
            0L
          },
        ),
        per_row_ms: Some(if index == 2 { 2L } else { 0L }),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(
          if index == 0 {
            100L
          } else if index == 1 {
            1L
          } else {
            5L
          },
        ),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_capacity: {
      transfer_bytes: 100000L,
      retained_bytes: 4000000L,
      execution_bytes: 268435456L,
    },
    output_rows_per_mille: Some(1000),
  })
  @dbhost.configure_dispatch_estimates(host, profiles, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 3,
  }).unwrap()
  @dbhost.refresh_dispatch_estimates(host).unwrap()
  host
}

///|
#export_name("strategyFixtureHistoryPlacement")
pub fn strategy_fixture_history_placement(
  f : StrategyFixture,
  revision : Int,
) -> String {
  guard @strategy.strategy_history_at(f.run.unwrap(), revision)
    is Some(revision) else {
    return "missing"
  }
  let native_reg = @connector.capability_registration_at(f.registry, 1).unwrap()
  let out = StringBuilder()
  for task in 1..<4 {
    guard @strategy.strategy_registration(revision, task) is Some(registration) else {
      return "missing"
    }
    out.write_string(
      if physical_equal(registration, native_reg) {
        "D"
      } else {
        "L"
      },
    )
  }
  out.to_string()
}
