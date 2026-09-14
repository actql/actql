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
  let profiles = Array::makei(3, i => @dbhost.DispatchEstimateProfile::{
    local_rates: [
      {
        work_slots: [0, 1, 2, 3, 4],
        fixed_ms: Some(if i == 0 { first_local } else { remaining_local }),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
      },
    ],
    native_rates: [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(100L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
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
    max_offers: 9,
    max_strategies: 27,
    max_work: 10000,
    max_revisions: 4,
  }).unwrap()
  let profile = @strategy.prepare_resident_profile(
    f.run.unwrap(),
    134217728L,
    Some(1L),
    Some(cleanup),
    Array::make(4, @strategy.ResidentImportEstimate::{
      milliseconds: Some(1L),
      transfer_bytes: 100000L,
      scratch_bytes: 2000000L,
      table_bytes: 4000000L,
    }),
  ).unwrap()
  @dbhost.configure_resident_dispatch(
    host,
    profile,
    Array::make(3, [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
        fixed_ms: Some(1L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
      },
    ]),
  ).unwrap()
  host
}
