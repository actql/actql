///|
/// Read only the exact completed consumer's saved envelope. Checked edge
/// admission, not common Run identity, selects its existing producer owner.
fn completed_holder_successor_parent(
  journal : @journal.Journal,
  admission : @resident_host.ResidentRunAdmission,
  request : @remote.DispatchRequest,
  at : String,
) -> String? {
  match
    @resident_host.resident_completed_consumer_producer_identity(
      journal, admission, request, at,
    ) {
    Ok(identity) => Some(identity)
    Err(_) => None
  }
}

///|
/// Restore a completed descendant inside the holder which already owns the
/// exclusive Site slot. Never admit, claim, execute or borrow input here.
/// Pending acquisition retains the same Runtime and exact component custody.
fn restore_completed_holder_successor(
  tasks : Map[String, HolderTaskCustody],
  order : Array[String],
  request : @remote.DispatchRequest,
  environment : SiteEnvironment,
  execution : @resident_host.ResidentExecution,
  resources : HolderOutputResources,
  admission : @resident_host.ResidentRunAdmission,
  delegation : @resident.ResidentSiteDelegation,
  current_time : () -> String,
  exclusive_current : () -> Bool,
) -> Bool {
  let identity = @remote.dispatch_request_identity(request)
  if tasks.get(identity) is Some(saved) {
    if saved.released || saved.release_requested {
      return false
    }
    if saved.executed is Some(_) {
      return true
    }
    // Never replace a live consumer owner or uncertain failed restoration.
    if saved.consumer is Some(_) || saved.restoration_cleanup is Some(_) {
      return false
    }
  }
  let task = if tasks.get(identity) is Some(saved) &&
    saved.restoration is Some(_) {
    saved
  } else {
    if !exclusive_current() {
      return false
    }
    guard completed_holder_successor_parent(
        environment.journal,
        admission,
        request,
        current_time(),
      )
      is Some(parent) &&
      tasks.get(parent) is Some(producer) &&
      !producer.released &&
      !(producer.successor_identity is Some(saved) && saved != identity) else {
      return false
    }
    let attempt = @remote.dispatch_request_attempt_identity(request).unwrap()
    guard @resident_host.resident_completed_holder_claimant(
        environment.journal,
        admission,
        delegation,
        @site.site_generation(environment.site),
        attempt,
        current_time(),
      )
      is Ok(Some(claimant)) &&
      @resident_host.resident_holder_process_hold_identity(
        environment.journal,
        admission,
        attempt,
        claimant,
      )
      is Ok(hold) else {
      return false
    }
    let active = match
      execution.bundles.acquire_active_component(
        @bundle.native_active_runtime_component_cid(execution.active_runtime),
        @bundle.native_active_runtime_target_triple(execution.active_runtime),
        hold,
      ) {
      Ok(value) => value
      Err(_) => return false
    }
    let candidate = new_holder_task_custody(request, None, None, Some(parent))
    candidate.process_hold.val = Some(active)
    let selected = remember_holder_successor(tasks, order, producer, candidate)
    guard selected is Some(saved) else {
      close_untransferred_consumer_binding(execution, candidate.process_hold)
      return false
    }
    // Exact replay reuses the existing entry. No overlapping owner exists;
    // a previous failed setup closed its component holding before retry.
    saved.process_hold.val = Some(active)
    saved.restoration_failed = true
    match
      @resident_host.prepare_resident_completed_attempt(
        environment.journal,
        { ..execution, active_runtime: active, },
        admission,
        delegation,
        attempt,
        current_time,
        exclusive_current,
        retained_cleanup=Some(
          (
            resources.transfer_journal,
            resources.retained_root,
            resources.retained_max_bytes,
          ),
        ),
      ) {
      Ok(owner) => {
        saved.process_hold.val = None
        saved.restoration = Some(owner)
      }
      Err(failure) => {
        if failure.pending_runtime is Some(runtime) {
          saved.process_hold.val = None
          saved.restoration_cleanup = Some(runtime)
        } else {
          close_untransferred_consumer_binding(execution, saved.process_hold)
        }
        return false
      }
    }
    saved
  }
  guard task.restoration is Some(owner) else { return false }
  match owner.advance() {
    @resident_host.ResidentCompletedReady(completed) => {
      task.executed = Some(completed)
      task.restoration = None
      task.restoration_failed = false
      report("consumer-restored", [
        ("request_cid", completed.completion.dispatch_request_cid),
        ("revision", completed.completion.revision.to_string()),
      ])
      true
    }
    _ => false
  }
}
