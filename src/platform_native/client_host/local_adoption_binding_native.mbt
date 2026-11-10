///|
// Transport aliases inside the existing adoption Owner. The capture retains
// Session/partial-open responsibility; the original pair retains its phases.
// This record neither supplies funding nor imports an independently made Root.
priv struct NativeLocalAdoptionBinding {
  host : @arena.InstalledArenaHost
  pair : @arena.InstalledArenaLocalHostResources
  read : @arena.InstalledArenaOriginalRead
  crypto : @crypto.Library
  capture : NativeLocalAdoptionCapture?
  preparation_issue : NativeLocalAdoptionIssue?
  mut leave_pending : Bool
}

///|
priv enum NativeLocalAdoptionBindingIssue {
  InvalidOperation
  Preparation(NativeLocalAdoptionIssue)
  Capture(NativeLocalAdoptionCaptureIssue)
  Resources(@arena.InstalledArenaLocalHostResourcesIssue)
  ReadScopePending
  Leave(
    NativeLocalAdoptionBindingIssue?,
    @arena.InstalledArenaLocalHostResourcesIssue
  )
}

///|
priv struct NativeLocalAdoptionBindingReply {
  original : NativeLocalAdoptionBinding
  operation : Int
  issue : NativeLocalAdoptionBindingIssue?
}

///|
// Pure preparation: retain all actual borrowed parents before any open. The
// existing capture snapshots selection and is the only Session/open issuer.
fn prepare_local_adoption_binding(
  host : @arena.InstalledArenaHost,
  pair : @arena.InstalledArenaLocalHostResources,
  read : @arena.InstalledArenaOriginalRead,
  crypto : @crypto.Library,
  input : NativeLocalExistingAdoptionInput,
  diagnostic_ceiling : Int,
) -> NativeLocalAdoptionBinding {
  let prepared : Result[NativeLocalAdoptionCapture, NativeLocalAdoptionIssue] = if diagnostic_ceiling <=
    0 {
    Err(InvalidInput)
  } else {
    prepare_native_local_existing_adoption_capture_in_current_read_context(
      input, crypto, diagnostic_ceiling,
    )
  }
  let (capture, preparation_issue) = match prepared {
    Ok(value) => (Some(value), None)
    Err(issue) => (None, Some(issue))
  }
  {
    host,
    pair,
    read,
    crypto,
    capture,
    preparation_issue,
    leave_pending: false,
  }
}

///|
fn NativeLocalAdoptionBinding::reply(
  self : NativeLocalAdoptionBinding,
  operation : Int,
  issue : NativeLocalAdoptionBindingIssue?,
) -> NativeLocalAdoptionBindingReply {
  { original: self, operation, issue, }
}

///|
// Only cleanup can finish an original pending leave. Never repeat the stage
// that preceded a failed leave, even when its physical effect was confirmed.
fn NativeLocalAdoptionBinding::finish_pending_leave(
  self : NativeLocalAdoptionBinding,
) -> Result[Unit, NativeLocalAdoptionBindingIssue] {
  if self.leave_pending {
    match self.host.leave_local_host_phase(self.pair) {
      Err(issue) => return Err(Resources(issue))
      Ok(_) => self.leave_pending = false
    }
  }
  Ok(())
}

///|
fn NativeLocalAdoptionBinding::operate(
  self : NativeLocalAdoptionBinding,
  operation : Int,
) -> NativeLocalAdoptionBindingReply {
  if operation != 1 && operation != 2 && operation != 3 && operation != 5 {
    return self.reply(operation, Some(InvalidOperation))
  }
  let cleanup = operation == 3
  if cleanup {
    match self.finish_pending_leave() {
      Err(issue) => return self.reply(operation, Some(issue))
      Ok(_) => ()
    }
  } else if self.leave_pending {
    return self.reply(operation, Some(ReadScopePending))
  }
  guard self.capture is Some(capture) else {
    return self.reply(
      operation,
      if cleanup {
        None
      } else {
        self.preparation_issue.map(issue => Preparation(issue))
      },
    )
  }
  if operation == 5 && capture.original_journal() is None {
    return self.reply(
      operation,
      Some(Capture(AdoptionJournal(JournalNotOpened))),
    )
  }
  if !cleanup {
    match
      self.host.require_local_host_consuming_read_current(self.pair, self.read) {
      Err(issue) => return self.reply(operation, Some(Resources(issue)))
      Ok(_) => ()
    }
  }
  // The retained Journal brackets its own Read and SQLite stages. Wrapping it
  // in another Read phase would both nest the scope and select the wrong domain.
  let direct_read = capture.original_journal() is None
  if direct_read {
    let entered = if cleanup {
      self.host.enter_local_host_cleanup(self.pair, @arena.HostRead)
    } else {
      self.host.enter_local_host_phase(self.pair, @arena.HostRead)
    }
    match entered {
      Err(issue) => return self.reply(operation, Some(Resources(issue)))
      Ok(_) => self.leave_pending = true
    }
  }
  // Open only the child already retained by this capture. Its original open
  // state prevents a second attempt after a refusal or a lost response.
  let primary : NativeLocalAdoptionBindingIssue? = if operation == 5 {
    capture
    .original_journal()
    .unwrap()
    .open()
    .issue()
    .map(issue => Capture(AdoptionJournal(issue)))
  } else {
    let original = match operation {
      1 => capture.open()
      2 => capture.check_current()
      _ => capture.close()
    }
    original.issue().map(issue => Capture(issue))
  }
  if direct_read {
    match self.host.leave_local_host_phase(self.pair) {
      Err(issue) => return self.reply(operation, Some(Leave(primary, issue)))
      Ok(_) => self.leave_pending = false
    }
  }
  self.reply(operation, primary)
}

///|
fn NativeLocalAdoptionBinding::capture_journal(
  self : NativeLocalAdoptionBinding,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> NativeLocalAdoptionBindingReply {
  if self.leave_pending {
    return self.reply(4, Some(ReadScopePending))
  }
  guard self.capture is Some(capture) else {
    return self.reply(
      4,
      self.preparation_issue.map(issue => Preparation(issue)),
    )
  }
  match
    self.host.require_local_host_consuming_read_current(self.pair, self.read) {
    Err(issue) => return self.reply(4, Some(Resources(issue)))
    Ok(_) => ()
  }
  // The original capture stores this same child before exposing its alias.
  // A lost response is observed via original_journal(), never another prepare.
  self.reply(
    4,
    match
      capture.capture_journal_with_original_resources(
        self.host,
        self.pair,
        self.read,
        ttl_ms,
        max_records,
        max_snapshot_bytes,
        max_retained_intent_bytes~,
      ) {
      Ok(_) => None
      Err(issue) => Some(Capture(issue))
    },
  )
}

///|
fn NativeLocalAdoptionBinding::descriptor_cleanup_acknowledged(
  self : NativeLocalAdoptionBinding,
) -> Bool {
  if self.leave_pending {
    return false
  }
  match self.capture {
    Some(capture) => capture.descriptor_cleanup_acknowledged()
    // Preparation performs no physical open. Borrowed parents and Crypto still
    // require their original, separate cleanup; this is only inner DATA scope.
    None => self.preparation_issue is Some(_)
  }
}

///|
fn NativeLocalAdoptionBindingReply::issue_family(
  self : NativeLocalAdoptionBindingReply,
) -> Int {
  match self.issue {
    None => 0
    Some(InvalidOperation) => 1
    Some(Preparation(_)) => 2
    Some(Capture(AdoptionOpeningUnconfirmed)) => 3
    Some(Capture(AdoptionJournal(JournalOpeningUnconfirmed))) => 3
    Some(Capture(_)) => 4
    Some(Resources(_)) => 5
    Some(ReadScopePending) => 6
    Some(Leave(_, _)) => 7
  }
}
