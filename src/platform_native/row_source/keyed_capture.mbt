///|
// Callback-free post-current/charge fence. Entry observes the actual parent;
// local handoffs retain that observation instead of rechecking it in helpers.
fn NativeRelationFileCapture::retained_keyed_original(self : Self) -> Bool {
  self.normal_original() &&
  self.failure is None &&
  !(self.phase is Closing) &&
  !(self.phase is Closed) &&
  self.acquisition is Some(ManagedFileKeyedAcquisition(acquisition, read, _, _)) &&
  @local.installed_keyed_source_read_acquisition_matches(read, acquisition)
}

///|
/// Use the original managed keyed read on this Native execution's SAME Ledger.
/// The Source retains its original nominal Resource resolver/issuer and its
/// Store child separately; physical Text-row declaration is not Content schema.
/// The caller funds this constructor before entry. The existing capture owns
/// its full raw provider reservation before any filesystem I/O can begin.
pub fn prepare_native_managed_relation_file_keyed_capture(
  arena : @arena.InstalledArenaHost,
  execution : @arena.InstalledArenaRetainedExecution,
  declaration : @rows.RowDeclaration,
  source_ref : String,
  read : @local.ClientInstalledKeyedSourceRead,
  acquisition : @rows.RowKeyedAcquisition,
  physical : NativeRelationFilePreparedProvider,
  issuer : @admitted.ReferenceIssuer,
  nonce : String,
) -> Result[NativeRelationFileCapture, NativeRelationFileFailure] {
  if !file_capture_text(nonce, 128) ||
    !file_capture_text(source_ref, 1024) ||
    !file_capture_selected_input_valid(physical.selection, physical.limits) {
    return Err({ issue: InvalidInput, owner: None, })
  }
  let ledger = match arena.borrow_domain_retained_execution_ledger(execution) {
    Ok(value) => value
    Err(issue) => return Err({ issue: Execution(issue), owner: None, })
  }
  match @local.check_installed_keyed_source_read_ledger(read, ledger) {
    Ok(_) => ()
    Err(issue) => return Err({ issue: ManagedRead(issue), owner: None, })
  }
  if !@local.installed_keyed_source_read_acquisition_matches(read, acquisition) {
    return Err({ issue: ForeignOriginal, owner: None, })
  }
  match @rows.check_row_keyed_acquisition_original(acquisition, declaration) {
    Ok(_) => ()
    Err(issue) => return Err({ issue: Row(issue), owner: None, })
  }
  prepare_native_relation_file_capture_original(
    arena,
    execution,
    declaration,
    source_ref,
    ManagedFileKeyedAcquisition(acquisition, read, physical, issuer),
    nonce,
    physical.selection,
    physical.limits,
    prepared_provider=Some(physical),
  )
}

///|
/// Borrow the original fully received/charged physical document. The Source
/// must resolve its own nominal Resource, enforce the original version and
/// retain/fund its Store custody before projection or persistence. This is not
/// a successful keyed response, issued ContentRef or cleanup acknowledgement.
pub fn NativeRelationFileCapture::keyed_content_document(
  self : Self,
) -> Result[@rows.RelationDocument, NativeRelationFileIssue] {
  guard self.current() &&
    self.phase is ContentReady &&
    self.acquisition is Some(ManagedFileKeyedAcquisition(_, _, _, _)) &&
    self.document is Some(original) else {
    return Err(Unavailable)
  }
  Ok(original)
}

///|
/// Continue the SAME keyed RowRun only after Source/Store produced its page.
/// The original raw receive ticket is consumed once, without charging the
/// derived ContentRef wire again. Common still admits schema/cardinality and
/// the original issuer; no projection may fabricate Source authority.
pub fn NativeRelationFileCapture::complete_keyed_content_page(
  self : Self,
  original : @rows.RelationDocument,
  body : Bytes,
) -> Result[Unit, NativeRelationFileFailure] {
  if !self.same() {
    return Err({ issue: ForeignOriginal, owner: None, })
  }
  if self.failure is Some(failure) {
    return Err(failure)
  }
  if !self.current() ||
    !(self.phase is ContentReady) ||
    !(self.acquisition is Some(ManagedFileKeyedAcquisition(_, _, _, _))) ||
    !(self.document is Some(retained) && physical_equal(retained, original)) ||
    !(self.charge is Some(_)) {
    return Err(self.fail(ForeignOriginal))
  }
  let run = self.run.unwrap()
  match
    @rows.begin_charged_row_run_keyed_page(run, self.charge.unwrap(), body) {
    Err(issue) => Err(self.fail(Row(issue)))
    Ok(_) => {
      // Keyed currentness can reenter the native owner. Never revive a closed
      // frame or replace its original document after a successful Core call.
      if !self.same() ||
        !(self.phase is ContentReady) ||
        self.failure is Some(_) ||
        !(self.document is Some(retained) && physical_equal(retained, original)) ||
        !(self.run is Some(retained_run) && physical_equal(retained_run, run)) {
        return Err(self.fail(Unavailable))
      }
      self.charge = None
      self.bytes = Some(body)
      self.phase = KeyedPage
      Ok(())
    }
  }
}

///|
/// The same completed keyed capture remains available only through this live
/// original. Its existing supplied-read gate closes with child retirement.
pub fn NativeRelationFileCapture::keyed_capture(
  self : Self,
) -> Result[@rows.RowKeyedSourceCapture, NativeRelationFileIssue] {
  guard self.current() &&
    self.phase is Captured &&
    self.keyed_result is Some(original) else {
    return Err(Unavailable)
  }
  Ok(original)
}
