///|
/// Local facts, never Run release, capacity settlement or execution authority.
priv enum EndedHolderChannelEvidence {
  ChannelDescriptorsRetired
  ChannelCloseUnconfirmed
}

///|
priv enum EndedHolderReportEvidence {
  OriginalStatusPending
  OriginalStatusAcknowledged
}

///|
/// Only this existing recovery Owner's terminal handle progression. It is not
/// a Run outcome or a source of physical stop/cleanup/authorization evidence.
priv enum StoppedRecoveryTerminalClose {
  RecoveryTerminalOpen
  RecoveryTerminalJournal
  RecoveryTerminalSlot
  RecoveryTerminalSlotUnknown
  RecoveryTerminalClosed
}

///|
fn retry_stopped_recovery_terminal_close(
  original : StoppedReleaseRecovery,
  retained : Ref[StoppedReleaseRecovery?],
) -> Bool {
  guard retained.val is Some(owner) && physical_equal(owner, original) else {
    return false
  }
  if original.terminal_close is RecoveryTerminalJournal {
    guard original.journal.close_checked() is Ok(_) else { return false }
    original.terminal_close = RecoveryTerminalSlot
  }
  if original.terminal_close is RecoveryTerminalSlot {
    if !original.slot.close() {
      original.terminal_close = RecoveryTerminalSlotUnknown
      return false
    }
    original.terminal_close = RecoveryTerminalClosed
  }
  if original.terminal_close is RecoveryTerminalClosed {
    retained.val = None
    return true
  }
  false
}

///|
/// The existing controller's one executor responsibility. A durable report
/// ACK cannot replace physical retirement or discard its original objects.
priv struct EndedHolderResponsibility {
  original : RunningHolder
  channel : EndedHolderChannelEvidence
  mut report_evidence : EndedHolderReportEvidence
  mut startability : Bool?
  journal : Ref[@journal.Journal?]
}

///|
fn retain_ended_holder(current : RunningHolder) -> EndedHolderResponsibility {
  {
    original: current,
    channel: if current.channel.close() {
      ChannelDescriptorsRetired
    } else {
      ChannelCloseUnconfirmed
    },
    report_evidence: OriginalStatusPending,
    startability: None,
    journal: Ref(None),
  }
}

///|
/// One original status/checked-close pass. A failed close keeps the same
/// journal; no new journal is opened and no HTTP report is repeated after ACK.
fn observe_ended_holder(
  original : EndedHolderResponsibility,
  environment : ControlEnvironment,
  client : @http.Client,
  observation_url : String,
) -> Unit {
  if original.journal.val is None &&
    original.report_evidence is OriginalStatusAcknowledged {
    return
  }
  let journal = match original.journal.val {
    Some(value) => value
    None =>
      match fresh_journal(environment) {
        Some(value) => {
          original.journal.val = Some(value)
          value
        }
        None => {
          report("observation-pending", [
            ("attempt", original.original.attempt), ("reason", "journal-open"),
          ])
          return
        }
      }
  }
  if original.report_evidence is OriginalStatusPending {
    match journal.require(original.original.request) {
      Ok(record) =>
        original.startability = Some(@remote.remote_runtime_record_startable(record))
      Err(_) => () // Unreadable is not proof that starting is safe.
    }
    match @client.acknowledge_status(
      journal, client, observation_url, original.original.request,
    ) {
      Ok(Some(record)) => {
        original.report_evidence = OriginalStatusAcknowledged
        original.startability = Some(@remote.remote_runtime_record_startable(record))
      }
      Ok(None) => original.report_evidence = OriginalStatusAcknowledged
      Err(issue) => report("observation-pending", [
        ("attempt", original.original.attempt), ("reason", client_code(issue)),
      ])
    }
  }
  match journal.close_checked() {
    Ok(_) => original.journal.val = None
    Err(_) => report("observation-cleanup-pending", [
      ("attempt", original.original.attempt), ("reason", "original-journal-close"),
    ])
  }
}

///|
/// A status ACK is only one fact. The same executor slot separately confirms
/// descendant stop, and its current named hold must still be valid. Returning
/// true releases controller admission only, never a task/Store reservation.
fn ended_holder_can_leave_window(
  original : EndedHolderResponsibility,
  slot : @slot.NativeExecutorSlot,
) -> Bool {
  guard original.channel is ChannelDescriptorsRetired &&
    original.report_evidence is OriginalStatusAcknowledged &&
    original.startability is Some(_) && original.journal.val is None else {
    return false
  }
  slot.try_acquire() == Ok(true) && slot.verify_current_hold() == Ok(())
}

///|
/// Private lifetime handoff inside the existing controller, not another
/// recovery Owner/queue. Original reports, physical objects and slot scope
/// remain alive when the terminal control boundary cannot confirm retirement.
priv struct ControlEndedHolderLifetime {
  ended : Array[EndedHolderResponsibility]
  live : Ref[RunningHolder?]
  environment : ControlEnvironment
  client : @http.Client
  observation_url : String
  slot_path : String
  mut slot : @slot.NativeExecutorSlot
  mut orphan_store : @publication_store.Store?
  recovery : Ref[StoppedReleaseRecovery?]
  recovery_cursor : Ref[String]
  matches : @argparse.Matches
  recovery_close_failures : Ref[Int]
  mut pending_custody : PendingBundleCustody?
  replay_journal : Ref[ControlReplayJournalCustody?]
}

///|
fn retry_control_ended_holder_lifetime(original : ControlEndedHolderLifetime) -> Bool {
  guard retry_control_replay_journal_cleanup(original.replay_journal) else {
    return false
  }
  if original.live.val is Some(holder) {
    match holder.child.wait(false) {
      Ok(Some(_)) => {
        original.ended.push(retain_ended_holder(holder))
        original.live.val = None
      }
      Ok(None) | Err(_) => return false
    }
  }
  if original.orphan_store is Some(store) {
    // Retires this original handle only. Output intents and reservations are
    // still durable; no physical payload deletion is inferred from close ACK.
    guard store.close() is Ok(_) else { return false }
    original.orphan_store = None
  }
  if original.recovery.val is Some(owner) {
    if !(owner.terminal_close is RecoveryTerminalOpen) {
      guard retry_stopped_recovery_terminal_close(owner, original.recovery) else {
        return false
      }
    } else {
    // Select only from this existing Owner's original durable journal. Never
    // reconstruct a request from a candidate wire/current Program or a hash.
    let record = match owner.journal.recover_after(original.recovery_cursor.val) {
      Ok(Some((key, record))) => {
        original.recovery_cursor.val = key
        record
      }
      Ok(None) => {
        original.recovery_cursor.val = ""
        return false
      }
      Err(_) => return false
    }
    let request = @remote.dispatch_record_request(record)
    if @remote.dispatch_request_identity(request) != owner.request_identity {
      return false
    }
    let completed = recover_stopped_release(
      original.matches, request, original.recovery, original.recovery_close_failures,
    ) catch {
      CommandStop(_) => false // The same original Owner remains in recovery.
    }
    guard completed else { return false }
    }
  }
  match original.pending_custody {
    Some(Responding(report)) => {
      let (remaining, _) = @agent.advance_native_bundle_custody_report(
        Some(report),
        (delivery, response) => @client.report_bundle_custody(
          original.client, original.observation_url, delivery, response,
        ),
      )
      original.pending_custody = remaining.map(value => Responding(value))
      guard original.pending_custody is None else { return false }
    }
    Some(Waiting(_)) =>
      // No completed response/ACK exists. Keep the original delivery duty;
      // shutdown never turns a not-yet-performed operation into success.
      return false
    None => ()
  }
  if !original.slot.is_open() {
    // Same configured slot path, as in the ordinary controller. A failed
    // opener never discards the original ended/live responsibility.
    match @slot.open_native_executor_slot(original.slot_path) {
      Ok(value) => original.slot = value
      Err(_) => return false
    }
  }
  let remaining = original.ended.filter(ended => {
    observe_ended_holder(
      ended, original.environment, original.client, original.observation_url,
    )
    !ended_holder_can_leave_window(ended, original.slot)
  })
  original.ended.clear()
  original.ended.append(remaining)
  original.ended.is_empty()
}

///|
fn retain_control_ended_holder_lifetime(
  ended : Array[EndedHolderResponsibility],
  live : RunningHolder?,
  environment : ControlEnvironment,
  client : @http.Client,
  observation_url : String,
  slot : @slot.NativeExecutorSlot,
  slot_path : String,
  orphan_store : @publication_store.Store?,
  recovery : Ref[StoppedReleaseRecovery?],
  matches : @argparse.Matches,
  recovery_close_failures : Ref[Int],
  pending_custody : PendingBundleCustody?,
  replay_journal : Ref[ControlReplayJournalCustody?],
) -> @slot.NativeExecutorSlot {
  let original : ControlEndedHolderLifetime = {
    ended, live: Ref(live), environment, client, observation_url, slot, slot_path,
    orphan_store, recovery, recovery_cursor: Ref(""), matches,
    recovery_close_failures, pending_custody, replay_journal,
  }
  install_partial_holder_cleanup_signal()
  ignore(retain_holder_cleanup_lifetime(
    original,
    retry_control_ended_holder_lifetime,
    () => CleanupInputEnded,
    wait_holder_cleanup_lifetime_signal,
    (custody, _) => report("control-cleanup-pending", [
      ("ended", custody.ended.length().to_string()),
      ("live", (custody.live.val is Some(_)).to_string()),
    ]),
  ))
  original.slot
}
