///|
/// Select the actual Host retention before this original Source starts I/O.
/// Fixed fields/Some and the bounded bind frame are already part of this
/// capture's construction reservation. This is DATA, not a permission or ACK.
pub fn NativeRelationFileCapture::bind_lookup_raw_retention(
  self : Self,
  retention : @publication.PublicationContract,
) -> Result[Unit, NativeRelationFileIssue] {
  guard !self.advancing &&
    self.phase is Prepared &&
    self.current() &&
    self.content is Some(content) &&
    content.raw_retention is None &&
    content.input is Some(input) else {
    return Err(Unavailable)
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  let at = (input.now_utc)()
  guard self.current() &&
    self.retained_keyed_original() &&
    self.phase is Prepared &&
    content.raw_retention is None &&
    @publication.result_retention_interval_state(retention, at)
    is Ok("available") else {
    return Err(Unavailable)
  }
  content.raw_retention = Some(retention)
  Ok(())
}

///|
// Same Source and existing Store child Owner. Each bounded advance authorizes
// the actual Source outside this frame. Persist/verify raw bytes BEFORE the
// physical JSON decoder can admit any document or derived Content page.
fn NativeRelationFileCapture::advance_raw_response(
  self : Self,
  content : NativeRelationFileContent,
) -> Result[Unit, NativeRelationFileIssue] {
  guard self.retained_keyed_original() &&
    self.transport_retired &&
    content.input is Some(input) &&
    content.raw_retention is Some(retention) &&
    content.raw_snapshot is Some(bytes) &&
    content.raw_snapshot_cid is Some(cid) else {
    return Err(Unavailable)
  }
  match content.phase {
    PrepareRawResponse => {
      let now = match self.content_clock(input) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let at = (input.now_utc)()
      guard self.current() &&
        self.retained_keyed_original() &&
        content.raw_response is None else {
        return Err(Unavailable)
      }
      let original = match
        @publication_host.prepare_client_keyed_native_raw_response(
          input.compiled,
          input.definition,
          input.request,
          retention,
          input.binding_wire,
          cid,
          bytes.length(),
          at,
          now,
          input.reference_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Lookup(issue))
      }
      // The lookup grow/current callback may have retired this very Source.
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      content.raw_response = Some(original)
      content.phase = PrepareRawStore
    }
    PrepareRawStore => {
      guard content.raw_response is Some(original) &&
        self.ledger is Some(ledger) &&
        self.metadata is Some(metadata) else {
        return Err(Unavailable)
      }
      let (retained, execution) = match
        file_capture_construction_capacity(
          self.selection.unwrap(),
          self.limits,
          self.acquisition.unwrap(),
          self.response_provider,
          Some(input),
          Some(bytes.length()),
          raw_candidate=Some(original.metadata),
        ) {
        Some(value) => value
        None => return Err(Capacity)
      }
      match
        @resources.grow_capacity_reservation(
          ledger, metadata, retained, execution,
        ) {
        Err(issue) => return Err(Resource(issue))
        Ok(_) => ()
      }
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      let child = match
        input.store.prepare_lookup_raw_custody(
          original.metadata,
          original.holding,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Store(issue))
      }
      // Retain the SAME child before the first fallible physical operation.
      content.raw_custody = Some(child)
      content.phase = PersistRaw
    }
    PersistRaw => {
      match content.raw_custody.unwrap().persist(bytes) {
        Err(issue) => return Err(Store(issue))
        Ok(_) => ()
      }
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      content.phase = VerifyRaw
    }
    VerifyRaw => {
      match content.raw_custody.unwrap().confirm(self.limits.chunk_bytes) {
        Err(issue) => return Err(Store(issue))
        Ok(_) => ()
      }
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      content.phase = RetireRawIO
    }
    RetireRawIO => {
      match content.raw_custody.unwrap().retry_cleanup() {
        Err(issue) => return Err(Store(issue))
        Ok(false) => return Err(Unavailable)
        Ok(true) => ()
      }
      guard self.retained_keyed_original() &&
        content.raw_response is Some(original) &&
        content.raw_custody
        .unwrap()
        .matches_lookup_raw_confirmed(original.metadata) else {
        return Err(Unavailable)
      }
      content.phase = ProjectContent
      self.phase = Received
    }
    _ => return Err(Unavailable)
  }
  Ok(())
}

///|
/// Borrow only the original envelope whose exact bytes this SAME capture has
/// persisted/verified. It is not an adopted page, attempt receipt or permission.
pub fn NativeRelationFileCapture::keyed_raw_response(
  self : Self,
) -> Result[
  @publication_host.ClientKeyedNativeRawResponse,
  NativeRelationFileIssue,
] {
  guard self.current() &&
    self.phase is Captured &&
    self.retained_keyed_original() &&
    self.content is Some(content) &&
    content.raw_response is Some(original) &&
    content.raw_custody is Some(custody) &&
    custody.matches_lookup_raw_confirmed(original.metadata) else {
    return Err(Unavailable)
  }
  Ok(original)
}
