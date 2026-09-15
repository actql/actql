///|
/// Installed Local preparation; the dispatch lookup does not interpret its name.
fn prepare_local_dispatch_work(
  host : StrategyHostDispatch,
  task : Int,
  _revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[DispatchWork, DispatchIssue] {
  let registration = host.local_registration
  let generated = host.generated[task - 1]
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let candidate = match
    @local_connector.local_fixed_compute_candidate(
      registration,
      request,
      generated,
      [],
      quantities,
      host.limits.candidate_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let choice = match
    @connector.choose_fixed_compute_candidate(
      host.registry,
      request,
      [@connector.prepared_compute_candidate(candidate)],
      Some([0]),
      host.limits.candidate_work,
    ) {
    Ok(Proposed(choice)) => choice
    Ok(_) => return Err(ForeignSelection)
    Err(issue) => return Err(Candidate(issue))
  }
  Ok(DispatchWork::Local(choice, candidate))
}

///|
/// DuckDB-specific compilation and binding stay in this implementation entry.
fn prepare_native_dispatch_work(
  host : StrategyHostDispatch,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[DispatchWork, DispatchIssue] {
  let registration = host.native_registration
  let owner = @connector.fixed_compute_request_owner(request)
  let inputs = @connector.fixed_compute_request_inputs(request)
  let generated = host.generated[task - 1]
  let quantities : @connector.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  if host.native_rejections[task - 1] is Some(_) {
    return Err(ForeignSelection)
  }
  if @strategy.strategy_resident_profile(revision, task) is Some(_) &&
    host.resident_rejections[task - 1] is Some(_) {
    return Err(ForeignSelection)
  }
  let prepared = if @strategy.captured_task_join_output_limit(host.run, task)
    is Some(required) {
    let query = match
      @duckdb.compile_fixed_inner_join(
        owner,
        "main",
        dispatch_input_tables(owner),
        host.limits.native_query,
      ) {
      Ok(value) => value
      Err(issue) => return Err(NativeCandidate(Compilation(issue)))
    }
    match
      @resources.charge_planning(
        @strategy.captured_dag_ledger(host.run),
        host.limits.join_validation.max_work,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Run(Physical(issue)))
    }
    let imported = match
      @duckdb.prepare_fixed_join_inputs(
        query,
        inputs,
        host.limits.join_validation,
        host.limits.native_query.max_entries,
        host.limits.native_query.max_sql_bytes,
      ) {
      Ok(value) => value
      Err(issue) => {
        @strategy.stop_captured_dag(host.run)
        return Err(JoinPreparation(issue))
      }
    }
    let ceiling = if required < host.limits.capacity.max_rows.to_int64() {
      required.to_int()
    } else {
      host.limits.capacity.max_rows
    }
    let compute = match @duckdb.prepare_fixed_join_compute(imported, ceiling) {
      Ok(value) => value
      Err(issue) => return Err(NativeCandidate(Compilation(issue)))
    }
    @duckdb_compute.duckdb_bound_compute_candidate(
      registration,
      request,
      compute,
      [],
      quantities,
      host.limits.candidate_work,
    )
  } else {
    @duckdb_compute.duckdb_fixed_compute_candidate(
      registration,
      request,
      "owned_input",
      host.limits.native_query,
      [],
      quantities,
      host.limits.candidate_work,
    )
  }
  let candidate = match prepared {
    Ok(value) => value
    Err(issue) => return Err(NativeCandidate(issue))
  }
  let choice = match
    @connector.choose_fixed_compute_candidate(
      host.registry,
      request,
      [@connector.prepared_compute_candidate(candidate)],
      Some([0]),
      host.limits.candidate_work,
    ) {
    Ok(Proposed(choice)) => choice
    Ok(_) => return Err(ForeignSelection)
    Err(issue) => return Err(Candidate(issue))
  }
  Ok(
    DispatchWork::Native(
      configure_strategy_compute_host(
        host.run,
        task,
        configure_compute_host(
          choice,
          candidate,
          generated,
          host.limits.native,
          host.limits.transport,
        ),
      ),
    ),
  )
}
