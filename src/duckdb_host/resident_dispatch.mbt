///|
priv struct ResidentDispatch {
  profile : @strategy.ResidentProfile
  rates : Array[Array[DispatchRate]]
}

///|
pub fn dispatch_resident_input(
  host : StrategyHostDispatch,
  task : Int,
) -> (Int, Int64, Int, Int)? {
  guard @strategy.captured_dag_strategy(host.run) is Some(revision) &&
    @strategy.strategy_resident_profile(revision, task) is Some(profile) else {
    return None
  }
  let graph = @strategy.captured_dag_graph(host.run)
  for i in 0..<@strategy.graph_data_count(graph) {
    let edge = @strategy.graph_data_at(graph, i).unwrap()
    if edge.consumer == task {
      return @strategy.resident_profile_import(profile, edge.producer).map(value => {
        (
          edge.producer,
          value.table_bytes,
          host.limits.input_entries,
          host.limits.input_name_bytes,
        )
      })
    }
  }
  None
}

///|
/// Install finite resident alternatives before the first dispatch. Rates cover
/// task work only; the profile adds shared preparation/import/cleanup separately.
pub fn configure_resident_dispatch(
  host : StrategyHostDispatch,
  profile : @strategy.ResidentProfile,
  rates : Array[Array[DispatchRate]],
) -> Result[Unit, DispatchIssue] {
  if host.resident is Some(_) ||
    host.pending is Some(_) ||
    @strategy.strategy_history_count(host.run) != 0 ||
    rates.length() != host.generated.length() ||
    !@strategy.resident_profile_matches(host.run, profile) {
    return Err(InvalidConfiguration)
  }
  for row in rates {
    match
      @strategy.charge_planning(
        @strategy.captured_dag_ledger(host.run),
        row.length(),
      ) {
      Err(issue) => return Err(Run(Physical(issue)))
      Ok(_) => ()
    }
    for rate in row {
      for value in [rate.fixed_ms, rate.per_row_ms, rate.per_wire_byte_ms] {
        if value is Some(value) && value < 0L {
          return Err(InvalidConfiguration)
        }
      }
    }
    match
      @cost.assess_serial(
        8,
        row.map(rate => { work_slots: rate.work_slots, milliseconds: None, }),
        host.limits.candidate_work,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Search(Cost(issue)))
    }
  }
  host.resident = Some({
    profile,
    rates: rates.map(row => {
      row.map(rate => { ..rate, work_slots: rate.work_slots.copy(), })
    }),
  })
  Ok(())
}
