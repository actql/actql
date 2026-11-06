///|
priv enum EffectCheckpointReplay {
  Idle
  Acknowledged(String)
  Attention(String, String)
  Pending(String, String)
}

///|
fn resident_checkpoint_report_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 32, }
}

///|
/// Inspect one original dispatch per control pass. The cursor and retry time
/// are disposable scheduling hints; the existing Site journal owns the report
/// and its exact receipt. Neither reconstruction nor ACK starts execution,
/// grants approval, releases custody, or replaces the original Run/Checkpoint.
fn advance_effect_checkpoint_replay(
  journal : @journal.Journal,
  client : @http.Client,
  url : String,
  delegation : @resident.ResidentSiteDelegation,
  generation : Int,
  cursor : Ref[String],
  next : Ref[UInt64],
  now : UInt64,
  backoff_ms : Int,
  checkpoint : (String) -> Unit,
) -> EffectCheckpointReplay {
  if backoff_ms < 1 {
    return Pending("", "invalid-backoff")
  }
  // Constant-size pacing for this report class. No request identity is kept
  // here; the original journal and cursor retain the durable responsibility.
  if now < next.val {
    return Idle
  }
  // Inspect the same Journal's report namespace before rebuilding any saved
  // dispatch or its materials. A report-less poll is not an execution/current
  // check. Present, malformed and unacknowledged reports retain the full path.
  match journal.has_effect_checkpoint_reports() {
    Ok(false) => {
      cursor.val = ""
      return Idle
    }
    Ok(true) => ()
    Err(_) => return Pending("", "journal-recovery")
  }
  let (key, record) = match journal.recover_after(cursor.val) {
    Ok(Some(value)) => value
    Ok(None) => {
      cursor.val = ""
      return Idle
    }
    Err(_) => return Pending("", "journal-recovery")
  }
  cursor.val = key
  let request = @remote.dispatch_record_request(record)
  let identity = @remote.dispatch_request_identity(request)
  let (_, reply) = match
    journal.effect_checkpoint_report(
      request,
      resident_checkpoint_report_limits(),
    ) {
    Ok(value) => value
    Err(@journal.Physical(@sqlite.NotFound)) => return Idle
    Err(_) => return Pending(identity, "journal-report")
  }
  match reply {
    Some(@remote.RemoteEffectCheckpointReply::Accepted) => return Idle
    Some(@remote.RemoteEffectCheckpointReply::Refused(reason)) => {
      next.val = now + backoff_ms.to_uint64()
      return Attention(identity, reason)
    }
    None => ()
  }
  next.val = now + backoff_ms.to_uint64()
  // Current operator delegation and the journal's current durable Site fence
  // precede HTTP I/O. A scope mismatch cannot manufacture a remote refusal.
  if @resident.check_resident_dispatch_delegation(
      delegation, request, generation,
    )
    is Err(_) {
    return Pending(identity, "scope-mismatch")
  }
  match
    @client.acknowledge_retained_effect_checkpoint(
      journal,
      client,
      url,
      request,
      resident_checkpoint_report_limits(),
      checkpoint~,
    ) {
    Ok(_) => Acknowledged(identity)
    Err(@client.EffectCheckpointRefused(reason)) => Attention(identity, reason)
    Err(issue) => Pending(identity, client_code(issue))
  }
}

///|
fn replay_effect_checkpoint_reports(
  environment : ControlEnvironment,
  retained : Ref[ControlReplayJournalCustody?],
  client : @http.Client,
  url : String,
  next : Ref[UInt64],
  backoff_ms : Int,
  cursor : Ref[String],
  delegation : @resident.ResidentSiteDelegation,
  checkpoint : (String) -> Unit,
) -> Unit {
  if @env.now() < next.val || retained.val is Some(_) {
    return
  }
  guard open_control_replay_journal(environment, retained) is Some(journal) else {
    report("effect-checkpoint-recovery-pending", [("reason", "journal-open")])
    return
  }
  match
    advance_effect_checkpoint_replay(
      journal,
      client,
      url,
      delegation,
      environment.site_generation,
      cursor,
      next,
      @env.now(),
      backoff_ms,
      checkpoint,
    ) {
    Idle => ()
    Acknowledged(identity) =>
      report("effect-checkpoint-acknowledged", [("request_cid", identity)])
    Attention(identity, reason) =>
      report("effect-checkpoint-attention", [
        ("request_cid", identity),
        ("reason", reason),
      ])
    Pending(identity, reason) =>
      report("effect-checkpoint-recovery-pending", [
        ("request_cid", identity),
        ("reason", reason),
      ])
  }
  if !retry_control_replay_journal_cleanup(retained) {
    report("effect-checkpoint-recovery-pending", [("reason", "journal-close")])
  }
}
