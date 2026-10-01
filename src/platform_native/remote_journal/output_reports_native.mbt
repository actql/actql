///|
fn Journal::report_custody(
  self : Journal,
  key : String,
) -> Result[@remote.RemoteOutputReportCustody, NativeRemoteJournalIssue] {
  let value = match self.database.read("site_output_report", key) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let body = @utf8.decode(value.body) catch { _ => return Err(StateCollision) }
  match @remote.admit_remote_output_report_custody_json(body) {
    Ok(custody) if @remote.remote_output_report_custody_key(custody) == key =>
      Ok(custody)
    _ => Err(StateCollision)
  }
}

///|
/// Reject a report before payload or Transfer side effects when the exact
/// durable snapshot would exceed this journal's configured record limit.
/// This prevents an oversized report from becoming an in-memory-only cleanup
/// responsibility after physical release.
pub fn Journal::ensure_output_report_capacity(
  self : Journal,
  output : @remote.RemotePollOutput,
  payload : @payload.PublicationPayloadRequest,
  transfer : @transfer.RemoteTransferRequest,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let size = match
    @remote.remote_output_report_custody_preflight_bytes(
      output, payload, transfer,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  if size > self.max_record_bytes {
    Err(Physical(@sqlite.CapacityExceeded))
  } else {
    Ok(())
  }
}

///|
/// Exactly one original report per Output intent. Physical cleanup scopes
/// never filter this scope. A failed/unknown commit does not permit sending.
pub fn Journal::retain_output_report(
  self : Journal,
  custody : @remote.RemoteOutputReportCustody,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let request = @remote.remote_output_report_custody_dispatch(custody)
  match @remote.prepare_dispatch_acceptance(self.control, request) {
    Ok(_) => ()
    Err(issue) => return Err(Protocol(issue))
  }
  match self.require(request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @remote.remote_output_report_custody_key(custody)
  let body = @utf8.encode(@remote.remote_output_report_custody_json(custody))
  match
    self.reserve_output_report(
      @remote.remote_output_report_custody_output(custody),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = match self.database.read("site_output_report", key) {
    Ok(value) if value.body == body => Ok(())
    Ok(_) => Err(StateCollision)
    Err(@sqlite.NotFound) =>
      self.database
      .insert("site_output_report", key, body)
      .map(_ => ())
      .map_err(issue => Physical(issue))
    Err(issue) => Err(Physical(issue))
  }
  match result {
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
    Ok(_) => ()
  }
  match self.database.commit() {
    Ok(_) => Ok(())
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}

///|
/// Includes suspended and acknowledged reports for inspection. Reply bytes
/// are validated against the original report, never interpreted by status.
pub fn Journal::output_report(
  self : Journal,
  key : String,
) -> Result[
  (@remote.RemoteOutputReportCustody, @remote.RemoteOutputReportReply?),
  NativeRemoteJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  let custody = match self.report_custody(key) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match self.database.read("site_output_report_reply", key) {
    Ok(value) if @remote.admit_remote_output_report_retry_json(
        @utf8.decode(value.body) catch {
          _ => ""
        },
      )
      is Ok(reason) =>
      Ok((custody, Some(@remote.RemoteOutputReportReply::Retry(reason))))
    Ok(value) => {
      let body = @utf8.decode(value.body) catch {
        _ => return Err(StateCollision)
      }
      match
        @remote.admit_remote_output_report_reply_json(
          body,
          @remote.remote_output_report_custody_result(custody),
        ) {
        Ok(reply) => Ok((custody, Some(reply)))
        Err(issue) => Err(Protocol(issue))
      }
    }
    Err(@sqlite.NotFound) => Ok((custody, None))
    Err(issue) => Err(Physical(issue))
  }
}

///|
/// Cursor enumeration is durable and does not require a live holder. The
/// caller may inspect a suspended report, but must not automatically send it.
pub fn Journal::output_report_after(
  self : Journal,
  after : String,
) -> Result[
  (String, @remote.RemoteOutputReportCustody, @remote.RemoteOutputReportReply?)?,
  NativeRemoteJournalIssue,
] {
  if self.closed {
    return Err(Closed)
  }
  match self.database.scan_after("site_output_report", after) {
    Ok(entry) =>
      self
      .output_report(entry.key)
      .map(value => Some((entry.key, value.0, value.1)))
    Err(@sqlite.NotFound) => Ok(None)
    Err(issue) => Err(Physical(issue))
  }
}

///|
/// Accepted is terminal. Refusal is a checked, non-secret attention state.
/// No acknowledgement is returned until the same transaction commits.
pub fn Journal::record_output_report_reply(
  self : Journal,
  key : String,
  body : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = (fn() {
    let custody = match self.report_custody(key) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let report = @remote.remote_output_report_custody_result(custody)
    let reply = match
      @remote.admit_remote_output_report_reply_json(body, report) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    let bytes = @utf8.encode(body)
    match self.database.read("site_output_report_reply", key) {
      Ok(value) if value.body == bytes => Ok(())
      Ok(value) => {
        let old_body = @utf8.decode(value.body) catch {
          _ => return Err(StateCollision)
        }
        if @remote.admit_remote_output_report_retry_json(old_body) is Ok(_) {
          return self.database
            .compare_exchange(
              "site_output_report_reply",
              key,
              value.revision,
              bytes,
            )
            .map(_ => ())
            .map_err(issue => Physical(issue))
        }
        if @remote.admit_remote_output_report_reply_json(old_body, report)
          is Ok(@remote.RemoteOutputReportReply::Accepted) {
          return Err(StateCollision)
        }
        if reply is @remote.RemoteOutputReportReply::Refused(_) {
          return Err(StateCollision)
        }
        self.database
        .compare_exchange(
          "site_output_report_reply",
          key,
          value.revision,
          bytes,
        )
        .map(_ => ())
        .map_err(issue => Physical(issue))
      }
      Err(@sqlite.NotFound) =>
        self.database
        .insert("site_output_report_reply", key, bytes)
        .map(_ => ())
        .map_err(issue => Physical(issue))
      Err(issue) => Err(Physical(issue))
    }
  })()
  match result {
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
    Ok(_) => ()
  }
  match self.database.commit() {
    Ok(_) => Ok(())
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}

///|
/// Explicit retry clears only a refusal under the current Site binding.
/// Original report bytes, identity and the physical cleanup facts are fixed.
pub fn Journal::retry_output_report(
  self : Journal,
  key : String,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = match self.output_report(key) {
    Ok((custody, Some(@remote.RemoteOutputReportReply::Refused(reason)))) =>
      match
        @remote.prepare_dispatch_acceptance(
          self.control,
          @remote.remote_output_report_custody_dispatch(custody),
        ) {
        Err(issue) => Err(Protocol(issue))
        Ok(_) =>
          match self.database.read("site_output_report_reply", key) {
            Ok(value) => {
              let marker = match
                @remote.remote_output_report_retry_json(reason) {
                Ok(value) => @utf8.encode(value)
                Err(issue) => return Err(Protocol(issue))
              }
              self.database
              .compare_exchange(
                "site_output_report_reply",
                key,
                value.revision,
                marker,
              )
              .map(_ => ())
              .map_err(issue => Physical(issue))
            }
            Err(issue) => Err(Physical(issue))
          }
      }
    Ok((_, None)) => Ok(())
    Ok(_) => Err(StateCollision)
    Err(issue) => Err(issue)
  }
  match result {
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
    Ok(_) => ()
  }
  match self.database.commit() {
    Ok(_) => Ok(())
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}

///|
/// Reserve bounded report storage before payload/Transfer starts. Exhaustion
/// rejects only new Output work; cleanup, existing reports and ACKs continue.
pub fn Journal::reserve_output_report(
  self : Journal,
  output : @remote.RemotePollOutput,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  let request = @remote.remote_poll_output_request(output)
  match @remote.prepare_dispatch_acceptance(self.control, request) {
    Ok(_) => ()
    Err(issue) => return Err(Protocol(issue))
  }
  match self.require(request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key = @remote.remote_output_intent_identity(
    @remote.remote_poll_output_intent(output),
  )
  let body = match
    @remote.remote_poll_output_json(
      request,
      @remote.remote_poll_output_intent(output),
    ) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(Protocol(issue))
    }
  }
  let result = (fn() {
    match self.database.read("site_output_report_slot", key) {
      Ok(value) if value.body == body => return Ok(())
      Ok(_) => return Err(StateCollision)
      Err(@sqlite.NotFound) => ()
      Err(issue) => return Err(Physical(issue))
    }
    // Closed report snapshots are at most 2 MiB, so 32 retained occurrences
    // bound their total bodies to 64 MiB. No retry appends another record.
    let mut cursor = ""
    let mut count = 0
    while true {
      match self.database.scan_after("site_output_report_slot", cursor) {
        Ok(entry) => {
          cursor = entry.key
          count += 1
          if count >= 32 {
            return Err(Physical(@sqlite.CapacityExceeded))
          }
        }
        Err(@sqlite.NotFound) => break
        Err(issue) => return Err(Physical(issue))
      }
    }
    self.database
    .insert("site_output_report_slot", key, body)
    .map(_ => ())
    .map_err(issue => Physical(issue))
  })()
  match result {
    Err(issue) => {
      ignore(self.database.rollback())
      return Err(issue)
    }
    Ok(_) => ()
  }
  match self.database.commit() {
    Ok(_) => Ok(())
    Err(issue) => {
      ignore(self.database.rollback())
      Err(Physical(issue))
    }
  }
}
