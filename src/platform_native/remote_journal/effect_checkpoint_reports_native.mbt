///|
/// Scheduling DATA only. An empty report namespace needs no dispatch/material
/// reconstruction. Presence never admits a report or authorizes its delivery.
pub fn Journal::has_effect_checkpoint_reports(
  self : Journal,
) -> Result[Bool, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  match self.database.scan_after("site_effect_checkpoint_report", "") {
    Ok(_) => Ok(true)
    Err(@sqlite.NotFound) => Ok(false)
    Err(issue) => Err(Physical(issue))
  }
}

///|
/// Read the exact original report without refreshing its Run or review window.
/// This is custody inspection, not a current permission to send or approve.
pub fn Journal::effect_checkpoint_report(
  self : Journal,
  request : @remote.DispatchRequest,
  limits : @checkpoint.WireLimits,
) -> Result[
  (@remote.RemoteEffectCheckpointReport, @remote.RemoteEffectCheckpointReply?),
  NativeRemoteJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  match self.require(request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @remote.dispatch_request_identity(request)
  let saved = match self.database.read("site_effect_checkpoint_report", key) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let wire = @utf8.decode(saved.body) catch { _ => return Err(StateCollision) }
  let report = match
    @remote.admit_remote_effect_checkpoint_report_json(wire, request, limits) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.database.read("site_effect_checkpoint_reply", key) {
    Err(@sqlite.NotFound) => Ok((report, None))
    Err(issue) => Err(Physical(issue))
    Ok(value) => {
      let body = @utf8.decode(value.body) catch {
        _ => return Err(StateCollision)
      }
      match @remote.admit_remote_effect_checkpoint_reply_json(body, report) {
        Ok(reply) => Ok((report, Some(reply)))
        Err(issue) => Err(Protocol(issue))
      }
    }
  }
}

///|
/// Retain one original review per consumer dispatch before sending. The exact
/// Site binding, dispatch outcome, cancellation and insertion share the
/// existing journal transaction. Failed/uncertain commit permits no send.
/// An already saved report stays inspectable and replayable for reconciliation;
/// replay cannot create a new review after cancellation or cleanup.
pub fn Journal::retain_effect_checkpoint_report(
  self : Journal,
  report : @remote.RemoteEffectCheckpointReport,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  let request = @remote.remote_effect_checkpoint_report_dispatch(report)
  match @remote.prepare_dispatch_acceptance(self.control, request) {
    Ok(_) => ()
    Err(issue) => return Err(Protocol(issue))
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @remote.dispatch_request_identity(request)
  let bytes = @utf8.encode(@remote.remote_effect_checkpoint_report_json(report))
  let result = (fn() {
    let record = match self.require(request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match self.database.read("site_effect_checkpoint_report", key) {
      Ok(saved) if saved.body == bytes => Ok(())
      Ok(_) => Err(StateCollision)
      Err(@sqlite.NotFound) => {
        match self.cancellation_requested(request) {
          Ok(false) => ()
          Ok(true) => return Err(StateCollision)
          Err(issue) => return Err(issue)
        }
        guard @remote.dispatch_record_state(record)
          is (@remote.NativeSettled, _, @remote.CleanupActive, _, _) else {
          return Err(StateCollision)
        }
        self.database
        .insert("site_effect_checkpoint_report", key, bytes)
        .map(_ => ())
        .map_err(issue => Physical(issue))
      }
      Err(issue) => Err(Physical(issue))
    }
  })()
  self.finish_effect_checkpoint_mutation(result)
}

///|
fn Journal::finish_effect_checkpoint_mutation(
  self : Journal,
  result : Result[Unit, NativeRemoteJournalIssue],
) -> Result[Unit, NativeRemoteJournalIssue] {
  match result {
    Err(issue) => {
      ignore(self.database.rollback())
      Err(issue)
    }
    Ok(_) =>
      match self.database.commit() {
        Ok(_) => Ok(())
        Err(issue) => {
          ignore(self.database.rollback())
          Err(Physical(issue))
        }
      }
  }
}

///|
/// Original report receipt is immutable. Accepted is not approval, execution
/// completion, or permission to release the retained continuation.
pub fn Journal::record_effect_checkpoint_reply(
  self : Journal,
  request : @remote.DispatchRequest,
  body : String,
  limits : @checkpoint.WireLimits,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = (fn() {
    let (report, _) = match self.effect_checkpoint_report(request, limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match @remote.admit_remote_effect_checkpoint_reply_json(body, report) {
      Ok(_) => ()
      Err(issue) => return Err(Protocol(issue))
    }
    let key = @remote.dispatch_request_identity(request)
    let bytes = @utf8.encode(body)
    match self.database.read("site_effect_checkpoint_reply", key) {
      Ok(value) if value.body == bytes => Ok(())
      Ok(_) => Err(StateCollision)
      Err(@sqlite.NotFound) =>
        self.database
        .insert("site_effect_checkpoint_reply", key, bytes)
        .map(_ => ())
        .map_err(issue => Physical(issue))
      Err(issue) => Err(Physical(issue))
    }
  })()
  self.finish_effect_checkpoint_mutation(result)
}
