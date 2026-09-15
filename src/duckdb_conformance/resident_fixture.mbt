///|
#export_name("strategyFixtureResidentDispatch")
pub fn strategy_fixture_resident_dispatch(
  f : StrategyFixture,
) -> @dbhost.StrategyHostDispatch {
  resident_dispatch_fixture(f, 1L, 100L, 100L)
}

///|
#export_name("strategyFixtureResidentCleanupDispatch")
pub fn strategy_fixture_resident_cleanup_dispatch(
  f : StrategyFixture,
) -> @dbhost.StrategyHostDispatch {
  resident_dispatch_fixture(f, 100L, 1000L, 10L)
}

///|
fn resident_dispatch_fixture(
  f : StrategyFixture,
  cleanup : Int64,
  first_local : Int64,
  remaining_local : Int64,
) -> @dbhost.StrategyHostDispatch {
  let host = strategy_fixture_dispatch(f)
  let count = @strategy.graph_task_count(f.graph) - 1
  let profiles = Array::makei(count, i => @dbhost.DispatchEstimateProfile::{
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(if i == 0 { first_local } else { remaining_local }),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(100L),
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
    max_offers: count * 3,
    max_strategies: if count == 3 {
      27
    } else {
      81
    },
    max_work: 10000,
    max_revisions: count + 1,
  }).unwrap()
  let profile = @strategy.prepare_resident_profile(
    f.run.unwrap(),
    @connector.prepare_resource_binding(
      f.registry,
      @connector.capability_registration_at(f.registry, 1).unwrap(),
    ).unwrap(),
    134217728L,
    @strategy.prepare_shared_work(
      f.run.unwrap(),
      1,
      [{ work_slots: [0], milliseconds: Some(1L), }],
      3,
    ).unwrap(),
    @strategy.prepare_shared_work(
      f.run.unwrap(),
      1,
      [{ work_slots: [0], milliseconds: Some(cleanup), }],
      3,
    ).unwrap(),
    Array::make(count + 1, @strategy.ResidentImportEstimate::{
      work: @strategy.prepare_shared_work(
        f.run.unwrap(),
        1,
        [{ work_slots: [0], milliseconds: Some(1L), }],
        3,
      ).unwrap(),
      transfer_bytes: 100000L,
      scratch_bytes: 2000000L,
      table_bytes: 4000000L,
    }),
  ).unwrap()
  @dbhost.configure_resident_dispatch(
    host,
    profile,
    Array::make(count, [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(1L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ]),
  ).unwrap()
  host
}
