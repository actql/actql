///|
// One entered preparation inside the same acquired Journal's original Read.
// The callback is not an authority, admission receipt or cleanup ACK. Its
// caller retains its own output/primary in an out-slot before returning.
pub fn[T] NativeLocalJournalCapture::with_original_read(
  self : NativeLocalJournalCapture,
  operation : (NativeLocalHostConnection) -> T,
) -> Result[T, NativeLocalAdoptionIssue] {
  if self.closing ||
    self.read_callback_active ||
    self.read_operation_issue is Some(_) {
    return Err(
      self.read_operation_issue.unwrap_or(OriginalResourceScopePending),
    )
  }
  guard self.opening is JournalAcquired(host) &&
    self.original_resources is Some(original) else {
    return Err(InvalidInput)
  }
  if original.store_operation is Some(_) {
    return Err(OriginalResourceScopePending)
  }
  self.clear_read_operation_facts()
  host.journal.admitted_publications.clear()
  host.journal.admitted_record = None
  host.journal.admitted_adoption = None
  native_timing_count(32)
  match original.check_journal_current(host) {
    Err(issue) => {
      self.read_operation_issue = Some(issue)
      return Err(issue)
    }
    Ok(_) => ()
  }
  self.read_callback_active = true
  self.read_facts_valid = true
  host.journal.operation_active = true
  let result = original.stage(@arena.HostRead, fn() {
    let value = operation(host)
    match self.read_operation_issue {
      Some(issue) => Err(issue)
      None => Ok(value)
    }
  })
  if result is Err(issue) && self.read_operation_issue is None {
    self.read_operation_issue = Some(issue)
  }
  self.read_callback_active = false
  self.read_facts_valid = false
  host.journal.operation_active = false
  host.journal.admitted_publications.clear()
  self.clear_read_operation_facts()
  host.journal.admitted_record = None
  host.journal.admitted_adoption = None
  // This is the one closed trusted Native command callback. Its internal
  // reads and phase exchanges do not create another authorization boundary.
  // The actual Read leave/return and any recorded failure remain with stage.
  result
}

///|
// Suspend only the currently entered same Read. The full existing fence owns
// Runtime, SQLite transaction and original configuration/adoption checks. Run
// custody belongs to the selected target reader. Then resume this original
// scope, without reissuing a consuming claim.
// A failed leave/exchange remains cleanup-only with its first actual issue.
pub fn NativeLocalJournalCapture::check_current_in_original_read(
  self : NativeLocalJournalCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  native_timing_count(18)
  if self.closing || self.read_operation_issue is Some(_) {
    return Err(
      self.read_operation_issue.unwrap_or(OriginalResourceScopePending),
    )
  }
  guard self.opening is JournalAcquired(host) &&
    self.original_resources is Some(original) &&
    !original.interrupted &&
    original.active_phase is Some(@arena.HostRead) else {
    return Err(OriginalResourceScopePending)
  }
  if self.read_callback_active && self.read_facts_valid {
    return self.check_original_read_lifetime()
  }
  native_timing_count(32)
  host.journal.admitted_adoption = None
  match original.host.leave_local_host_phase(original.pair) {
    Err(issue) => {
      let primary = OriginalResourceLeave(None, issue)
      original.interrupted = true
      self.read_operation_issue = Some(primary)
      return Err(primary)
    }
    Ok(_) => original.active_phase = None
  }
  let current = original.check_journal_current(host)
  if current is Err(issue) {
    self.read_operation_issue = Some(issue)
  }
  if original.interrupted {
    return match current {
      Err(issue) => Err(issue)
      Ok(_) => {
        self.read_operation_issue = Some(OriginalResourceScopePending)
        Err(OriginalResourceScopePending)
      }
    }
  }
  match original.host.enter_local_host_phase(original.pair, @arena.HostRead) {
    Err(issue) => {
      original.interrupted = true
      let primary = self.read_operation_issue.unwrap_or(
        OriginalResources(issue),
      )
      self.read_operation_issue = Some(primary)
      Err(primary)
    }
    Ok(_) => {
      original.active_phase = Some(@arena.HostRead)
      current
    }
  }
}

///|
/// Selected original bytes under the full same-pair current fence. This is
/// neither a discovered configuration nor a Provider or execution grant.
pub fn NativeLocalJournalCapture::selected_configuration_in_original_read(
  self : NativeLocalJournalCapture,
  name : String,
) -> Result[Bytes, NativeLocalAdoptionIssue] {
  match self.check_current_in_original_read() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.opening is JournalAcquired(host) else { return Err(InvalidInput) }
  // The command entry validated this retained original. Pure selection does
  // not restage configuration or inspect its filesystem generation again.
  if self.read_callback_active && self.read_facts_valid {
    return match
      host.session.settings.files.iter().find_first(file => file.name == name) {
      Some(file) => Ok(file.body)
      None => Err(InvalidInput)
    }
  }
  host.session.selected_configuration(name)
}

///|
/// Return the originally admitted Account, with all current checks retained.
/// Its presence is not an allow decision for the command or a business Run.
pub fn NativeLocalJournalCapture::configuration_in_original_read(
  self : NativeLocalJournalCapture,
) -> Result[
  @authorization.AdmittedAccountConfiguration,
  NativeLocalAdoptionIssue,
] {
  match self.check_current_in_original_read() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard self.opening is JournalAcquired(host) else { return Err(InvalidInput) }
  Ok(host.session.configuration)
}

///|
/// Stop this capture and finish only its own recorded pending phase exchange.
/// This is not a Root/Reader/DB/Library/context/domain retirement ACK. Another
/// Runtime's entered phase remains with that Runtime's original cleanup port.
pub fn NativeLocalJournalCapture::finish_pending_original_scope(
  self : NativeLocalJournalCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  self.closing = true
  match self.original_resources {
    Some(original) => original.finish_pending_leave()
    None => Ok(())
  }
}

///|
// Existing physical identity/lifetime observation only. This cannot admit
// config, Account, a Run, a new scope or any cleanup acknowledgment.
fn NativeLocalJournalCapture::check_original_read_lifetime(
  self : NativeLocalJournalCapture,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.closing || self.read_operation_issue is Some(_) {
    return Err(
      self.read_operation_issue.unwrap_or(OriginalResourceScopePending),
    )
  }
  guard self.opening is JournalAcquired(host) &&
    !host.closed &&
    !host.journal.fenced &&
    self.original_resources is Some(original) &&
    !original.interrupted &&
    original.active_phase is Some(@arena.HostRead) else {
    return Err(OriginalResourceScopePending)
  }
  match
    original.host.observe_local_host_consuming_read_scope(
      original.pair,
      original.read,
    ) {
    Ok(@arena.ReadEntered) => Ok(())
    Ok(_) => Err(OriginalResourceScopePending)
    Err(issue) => Err(OriginalResources(issue))
  }
}
