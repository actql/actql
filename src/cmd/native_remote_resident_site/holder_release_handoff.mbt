///|
/// Bookkeeping of the already authenticated Release, not execution authority.
/// The original admitted graph bounds this holder's distinct task duties.
fn remember_holder_release(
  holder : @remote.DispatchRequest,
  retained : Map[String, @remote.DispatchRequest],
  request : @remote.DispatchRequest,
  max_tasks : Int,
) -> Bool {
  guard holder_can_receive(holder, request) else { return false }
  let identity = @remote.dispatch_request_identity(request)
  if retained.contains(identity) {
    return true
  }
  guard max_tasks > 0 && retained.size() < max_tasks else { return false }
  retained[identity] = request
  true
}

///|
/// Child exit alone cannot select release. Reuse the received typed requests,
/// actual scoped stop and current exclusive Slot before the existing Journal
/// Owner begins cleanup. Keep every request through its later status ACK.
fn begin_ended_holder_releases(
  original : EndedHolderResponsibility,
  environment : ControlEnvironment,
  slot : @slot.NativeExecutorSlot,
  delegation : @resident.ResidentSiteDelegation,
) -> Bool {
  if original.original.releases.is_empty() {
    return true
  }
  guard original.process_retirement is HolderProcessRetired &&
    slot.try_acquire() == Ok(true) && slot.verify_current_hold() == Ok(()) else {
    return false
  }
  guard retry_control_replay_journal_cleanup(original.journal) else { return false }
  let journal = match open_control_replay_journal(environment, original.journal) {
    Some(value) => value
    None => return false
  }
  let mut begun = true
  for request in original.original.releases.values() {
    if @resident_host.begin_resident_output_release(
        journal, delegation, environment.site_generation, request,
      ) is Err(_) {
      begun = false
    }
  }
  let closed = retry_control_replay_journal_cleanup(original.journal)
  begun && closed
}

///|
/// Shared by a newly polled no-holder Release and the same request retained
/// before a live relay. Recovery and reporting use their existing Owners;
/// no relay, process exit or transport ACK substitutes for resource cleanup.
fn finish_stopped_control_release(
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  request : @remote.DispatchRequest,
  delegation : @resident.ResidentSiteDelegation,
  recovery : Ref[StoppedReleaseRecovery?],
  close_failures : Ref[Int],
  retained : Ref[ControlReplayJournalCustody?],
  client : @http.Client,
  observation_url : String,
  recover_now~ : Bool,
) -> Bool raise CommandStop {
  guard @resident.check_resident_dispatch_delegation(
    delegation, request, environment.site_generation,
  ) is Ok(_) else { return false }
  guard retry_control_replay_journal_cleanup(retained) else { return false }
  let journal = match open_control_replay_journal(environment, retained) {
    Some(value) => value
    None => return false
  }
  let needs_recovery = match journal.require(request) {
    Ok(record) => {
      let codes = @remote.dispatch_record_state_codes(record)
      codes[0] == 3 &&
      (recovery.val is Some(_) || codes[2] == 0 || codes[2] == 1 || codes[2] == 3)
    }
    _ => false
  }
  guard retry_control_replay_journal_cleanup(retained) else { return false }
  if recover_now && needs_recovery {
    if recover_stopped_release(matches, environment, request, recovery, close_failures) {
      report("release-recovered", [
        ("request_cid", @remote.dispatch_request_identity(request)),
      ])
    }
  }
  // The recovery may have committed through another Journal. Only a fresh
  // original durable view can report that new revision; never relax admission.
  guard retry_control_replay_journal_cleanup(retained) else { return false }
  let current = match open_control_replay_journal(environment, retained) {
    Some(value) => value
    None => return false
  }
  let acknowledged = match
    @client.acknowledge_status(current, client, observation_url, request) {
    Ok(value) => {
      report("release-observed", [
        ("request_cid", @remote.dispatch_request_identity(request)),
      ])
      value is Some(record) && @remote.remote_runtime_record_released(record)
    }
    Err(issue) => {
      report("release-failed", [("reason", client_code(issue))])
      false
    }
  }
  let closed = retry_control_replay_journal_cleanup(retained)
  acknowledged && closed
}

///|
/// This array belongs to the same ended-holder carrier, including terminal
/// handoff. Only the actual same-request Released report ACK removes a duty.
fn finish_ended_holder_releases(
  original : EndedHolderResponsibility,
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  delegation : @resident.ResidentSiteDelegation,
  recovery : Ref[StoppedReleaseRecovery?],
  close_failures : Ref[Int],
  client : @http.Client,
  observation_url : String,
) -> Bool raise CommandStop {
  let identities = original.original.releases.keys().to_array()
  for identity in identities {
    guard original.original.releases.get(identity) is Some(request) else { continue }
    if finish_stopped_control_release(
      matches, environment, request, delegation, recovery, close_failures,
      original.journal, client, observation_url, recover_now=true,
    ) {
      ignore(original.original.releases.remove(identity))
    }
  }
  original.original.releases.is_empty()
}
