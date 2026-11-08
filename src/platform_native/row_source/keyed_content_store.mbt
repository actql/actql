///|
/// Original per-occurrence inputs, not another Run, Store or cleanup owner.
/// The installing Source supplies its nominal resolver and the Host's original
/// clocks. Source/Account authorization remains the installing Host's duty.
/// Its caller funds this fixed binding before entry, just as it funds the
/// original prepared physical provider. Request wire is built only after the
/// SAME capture has reserved its full content construction overlap.
struct NativeRelationFileContentInput {
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  keyed : @publication_host.ClientKeyedAcquisition
  request : @publication_host.ClientKeyedRequest
  original_request : @sourceviews.KeyedRowRequest
  store : @store.Store
  fields : NativeRelationFileListingFields
  content_utf8 : String
  binding_wire : String
  reference_limits : @admitted.ReferenceLimits
  max_content_bytes : Int
  now_ms : () -> Int64
  now_utc : () -> String
  resolve_identity : (@admitted.ReferenceValue) -> String?
}

///|
pub fn prepare_native_relation_file_content_input(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  keyed : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  store : @store.Store,
  fields : NativeRelationFileListingFields,
  content_utf8 : String,
  binding_wire : String,
  reference_limits : @admitted.ReferenceLimits,
  max_content_bytes : Int,
  now_ms : () -> Int64,
  now_utc : () -> String,
  resolve_identity : (@admitted.ReferenceValue) -> String?,
) -> Result[NativeRelationFileContentInput, NativeRelationFileIssue] {
  if max_content_bytes < 0 ||
    !file_capture_text(content_utf8, 64) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignOriginal)
  }
  guard @publication_host.client_keyed_request_value(request, keyed)
    is Some(original_request) else {
    return Err(ForeignOriginal)
  }
  Ok({
    compiled,
    definition,
    keyed,
    request,
    original_request,
    store,
    fields,
    content_utf8,
    binding_wire,
    reference_limits,
    max_content_bytes,
    now_ms,
    now_utc,
    resolve_identity,
  })
}

///|
priv enum NativeFileContentPhase {
  ProjectContent
  PrepareContentStore
  PersistContent
  VerifyContent
  RetireContentIO
  IssueContent
  CompleteContentPage
}

///|
// A field of the SAME NativeRelationFileCapture. Every acquired Store child is
// retained here before its first I/O. Escaped issuer closures retain only the
// capture's closed shell after all these optional aliases have been severed.
priv struct NativeRelationFileContent {
  mut input : NativeRelationFileContentInput?
  mut bytes : Bytes?
  mut candidate : @publication_host.ClientCapturedContent?
  mut custody : @store.CapturedContentCustody?
  mut value : @admitted.CheckedValue?
  mut issuer : @admitted.ReferenceIssuer?
  mut phase : NativeFileContentPhase
  mut last_ms : Int64
  mut issuing : Bool
  mut io_complete : Bool
}

///|
fn native_relation_file_content(
  input : NativeRelationFileContentInput,
) -> NativeRelationFileContent {
  {
    input: Some(input),
    bytes: None,
    candidate: None,
    custody: None,
    value: None,
    issuer: None,
    phase: ProjectContent,
    last_ms: -1L,
    issuing: false,
    io_complete: false,
  }
}

///|
fn native_relation_file_content_capacity(
  input : NativeRelationFileContentInput,
  physical : NativeRelationFilePreparedProvider?,
  response_bytes? : Int? = None,
  storage_candidate? : @publication.CapturedContentReference? = None,
) -> (Int64, Int64)? {
  // The Store child does not exist until its original candidate has been
  // built. Its exact constructor is grown on this SAME reservation below,
  // before the child is prepared or can perform any I/O.
  let storage : @execution.PreparationRepresentationUnits? = match
    (storage_candidate, physical) {
    (None, _) =>
      Some({
        record_headers: 0L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
    (Some(original), Some(provider)) =>
      input.store.captured_content_custody_construction_inventory(
        provider.limits.chunk_bytes,
        candidate=Some(original),
      )
    _ => None
  }
  guard physical is Some(provider) &&
    file_listing_fields_valid(provider, input.fields) &&
    file_content_construction_inventory(
      provider,
      response_bytes
      .map(bytes => Int::min(input.max_content_bytes, Int::max(1, bytes)))
      .unwrap_or(input.max_content_bytes),
      response_bytes,
    )
    is Some(projection) &&
    storage is Some(storage) &&
    @publication_host.client_captured_content_workspace_capacity(
      input.reference_limits.max_bytes,
    )
    is Some((reference_retained, reference_execution)) &&
    @encode.text_writer_construction_inventory(
      provider.limits.page.max_bytes,
      provider.limits.page.max_nodes,
      provider.limits.page.max_depth,
    )
    is Some(page) &&
    @execution.compose_preparation_representation([
      projection,
      storage,
      {
        // Content holder H1/R6/W4 + six Some slots H6/R6/W6; issuer identity,
        // two callbacks and domain delegation H7/R10/W3; page writer and
        // output UTF8 Bytes H1; four-view request/field access and Store/
        // candidate/issuer/clock Result/refusal frontiers H24/R30/W24.
        // SHA block/state/digest/hex live beside projected bytes: H9/R5/W93,
        // B96/T263, with no copied Source text. Core candidate/reference
        // wire/tree construction uses its existing separate workspace below.
        record_headers: page.record_headers + 1L + 6L + 7L + 1L + 24L + 9L,
        reference_slots: page.reference_slots + 6L + 6L + 10L + 30L + 5L,
        scalar_words: page.scalar_words + 4L + 6L + 3L + 24L + 93L,
        owned_utf16_units: page.owned_utf16_units + 263L,
        owned_wire_bytes: provider.limits.page.max_bytes.to_int64() + 96L,
      },
    ])
    is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, reference_retained, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(bytes, reference_execution, 1L)
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
}

///|
fn NativeRelationFileCapture::content_clock(
  self : Self,
  input : NativeRelationFileContentInput,
) -> Result[Int64, NativeRelationFileIssue] {
  let now = (input.now_ms)()
  // This external clock may reenter an ancestor's retirement. Observe the
  // actual parent AFTER that boundary, before another physical operation.
  guard self.current() &&
    self.retained_keyed_original() &&
    self.content is Some(content) &&
    content.input is Some(original) &&
    physical_equal(original, input) &&
    now >= 0L &&
    now >= content.last_ms else {
    return Err(Unavailable)
  }
  content.last_ms = now
  Ok(now)
}

///|
fn NativeRelationFileCapture::content_available(
  self : Self,
  wire : String,
) -> Bool {
  guard self.same() && self.content is Some(content) && !content.issuing else {
    return false
  }
  let prior = self.advancing
  self.advancing = true
  content.issuing = true
  defer {
    content.issuing = false
    self.advancing = prior
  }
  guard content.input is Some(input) &&
    content.candidate is Some(candidate) &&
    content.custody is Some(custody) &&
    @publication_host.client_captured_content_wire(candidate) == wire &&
    custody.matches_confirmed(
      @publication_host.client_captured_content_candidate(candidate),
    ) else {
    return false
  }
  let at = (input.now_utc)()
  self.current() &&
  self.retained_keyed_original() &&
  self.content is Some(original) &&
  physical_equal(original, content) &&
  content.input is Some(retained) &&
  physical_equal(retained, input) &&
  @publication.run_publication_start_current(
    @publication_host.client_compiled_run_admission(input.compiled),
    input.definition,
    at,
  )
}

///|
fn NativeRelationFileCapture::content_issuer(
  self : Self,
) -> @admitted.ReferenceIssuer {
  @admitted.bind_reference_issuer(
    (contract, wire) => {
      self.same() &&
      self.failure is None &&
      !(self.phase is Closing) &&
      !(self.phase is Closed) &&
      contract.shape is @contract.ContentRef(..) &&
      self.content is Some(content) &&
      (content.phase is IssueContent || content.phase is CompleteContentPage) &&
      content.candidate is Some(candidate) &&
      @publication_host.client_captured_content_wire(candidate) == wire
    },
    wire => self.content_available(wire),
  )
}

///|
fn NativeRelationFileCapture::advance_content(
  self : Self,
  content : NativeRelationFileContent,
) -> Result[Unit, NativeRelationFileIssue] {
  guard self.retained_keyed_original() &&
    content.input is Some(input) &&
    self.document is Some(document) &&
    self.acquisition
    is Some(ManagedFileKeyedAcquisition(acquisition, read, provider, _)) &&
    @local.installed_keyed_source_read_request_matches(
      read,
      acquisition,
      input.keyed,
      input.request,
      input.compiled,
      input.definition,
    ) else {
    return Err(ForeignOriginal)
  }
  let request = input.original_request
  guard @sourceviews.keyed_row_request_field(request, "resource")
    is Some(resource) &&
    resource.value is @admitted.Reference(reference) &&
    @admitted.reference_available(reference) &&
    @sourceviews.keyed_row_request_field(request, "version")
    is Some(version_value) &&
    version_value.value is @admitted.Text(version) &&
    self.retained_keyed_original() else {
    return Err(ForeignOriginal)
  }
  match content.phase {
    ProjectContent => {
      let identity = (input.resolve_identity)(reference)
      guard self.retained_keyed_original() && identity is Some(identity) else {
        return Err(ForeignOriginal)
      }
      let (media_type, bytes) = match
        project_native_relation_file_content_bytes(
          provider,
          document,
          input.fields,
          input.content_utf8,
          identity,
          version,
          input.max_content_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      content.bytes = Some(bytes)
      let candidate = match
        @publication_host.prepare_client_run_captured_content(
          input.compiled,
          input.definition,
          input.keyed,
          input.request,
          input.binding_wire,
          media_type,
          "sha256:" + @sha.hex(bytes),
          bytes.length(),
          input.reference_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Content(issue))
      }
      content.candidate = Some(candidate)
      content.phase = PrepareContentStore
    }
    PrepareContentStore => {
      let candidate = content.candidate.unwrap()
      guard self.ledger is Some(ledger) && self.metadata is Some(metadata) else {
        return Err(Unavailable)
      }
      let (retained, execution) = match
        file_capture_construction_capacity(
          self.selection.unwrap(),
          self.limits,
          self.acquisition.unwrap(),
          self.response_provider,
          Some(input),
          Some(self.offset),
          storage_candidate=Some(
            @publication_host.client_captured_content_candidate(candidate),
          ),
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
      // A successful debit remains with the same owner after reentrant close;
      // it never permits a stale Store constructor or another candidate.
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      let holding = match
        @publication_host.client_captured_content_holding_cid(candidate) {
        Some(value) => value
        None => return Err(ForeignOriginal)
      }
      let child = match
        input.store.prepare_captured_content_custody(
          @publication_host.client_captured_content_candidate(candidate),
          holding,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Store(issue))
      }
      content.custody = Some(child)
      content.phase = PersistContent
    }
    PersistContent => {
      match content.custody.unwrap().persist(content.bytes.unwrap()) {
        Err(issue) => return Err(Store(issue))
        Ok(_) => ()
      }
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      content.phase = VerifyContent
    }
    VerifyContent => {
      match content.custody.unwrap().confirm(self.limits.chunk_bytes) {
        Err(issue) => return Err(Store(issue))
        Ok(_) => ()
      }
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      content.phase = RetireContentIO
    }
    RetireContentIO => {
      match content.custody.unwrap().retry_cleanup() {
        Err(issue) => return Err(Store(issue))
        Ok(false) => return Err(Unavailable)
        Ok(true) => ()
      }
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      content.bytes = None
      content.phase = IssueContent
    }
    IssueContent => {
      let value = match
        @publication_host.issue_client_captured_content(
          content.candidate.unwrap(),
          content.issuer.unwrap(),
          input.reference_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Content(issue))
      }
      if !self.retained_keyed_original() {
        return Err(Unavailable)
      }
      content.value = Some(value)
      content.phase = CompleteContentPage
    }
    CompleteContentPage => {
      let body = try {
        let writer = @encode.writer(
          self.limits.page.max_bytes,
          self.limits.page.max_nodes,
          self.limits.page.max_depth,
        )
        @encode.begin_array(writer)
        @encode.begin_object(writer)
        @encode.key(writer, "resource")
        @admitted.emit_checked_wire_value(resource, writer)
        @encode.key(writer, "version")
        @encode.string_value(writer, version)
        @encode.key(writer, "content")
        @admitted.emit_checked_wire_value(content.value.unwrap(), writer)
        @encode.end_object(writer)
        @encode.end_array(writer)
        @utf8.encode(@encode.finish(writer))
      } catch {
        _ => return Err(FileLimit)
      }
      match self.complete_keyed_content_page_original(document, body) {
        Ok(_) => ()
        Err(failure) => return Err(failure.issue())
      }
    }
  }
  Ok(())
}

///|
// Completed Content keeps its original candidate/issuer/value and Store child.
// Retain the Common reference workspace until the Model input receipt; only
// the finished Native projection/page writer/storage constructors disappear.
fn native_relation_file_content_retained_capacity(
  content : NativeRelationFileContent,
) -> (Int64, Int64)? {
  guard content.phase is CompleteContentPage &&
    content.io_complete &&
    !content.issuing &&
    content.bytes is None &&
    content.input is Some(input) &&
    content.candidate is Some(candidate) &&
    content.value is Some(_) &&
    content.issuer is Some(_) &&
    content.custody is Some(custody) &&
    custody.matches_confirmed(
      @publication_host.client_captured_content_candidate(candidate),
    ) &&
    custody.retained_inventory() is Some(storage) &&
    @publication_host.client_captured_content_workspace_capacity(
      input.reference_limits.max_bytes,
    )
    is Some((reference_retained, reference_execution)) &&
    @execution.compose_preparation_representation([
      storage,
      {
        // Same holder H1/R6/W4, six optional slots H6/R6/W6 and original
        // issuer identity/callbacks/domain delegation H7/R10/W3. Input DATA
        // remains borrowed from its original caller-funded occurrence.
        record_headers: 1L + 6L + 7L,
        reference_slots: 6L + 6L + 10L,
        scalar_words: 4L + 6L + 3L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(bytes) &&
    @execution.checked_preparation_add_product(bytes, reference_retained, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(bytes, reference_execution, 1L)
    is Some(execution) else {
    return None
  }
  Some((retained, execution))
}

///|
// Called only in a later advance frame, after raw/page constructors returned.
// The same completed RowRun/Store/ContentRef remain live. Drop finished local
// aliases BEFORE contracting this original reservation; callbacks may retire
// the parent, so success never bypasses the original post-current fence.
fn NativeRelationFileCapture::retire_keyed_content_construction(
  self : Self,
  content : NativeRelationFileContent,
) -> Result[Unit, NativeRelationFileIssue] {
  guard self.retained_keyed_original() &&
    self.phase is Parsed &&
    self.transport_retired &&
    self.transient_retired &&
    self.root is None &&
    self.rejected_root is None &&
    self.reader is None &&
    self.rejected_reader is None &&
    self.observation is None &&
    self.document is None &&
    self.target is None &&
    self.content is Some(original) &&
    physical_equal(original, content) &&
    self.ledger is Some(ledger) &&
    self.metadata is Some(metadata) &&
    file_capture_keyed_retained_capacity(content) is Some((retained, execution)) else {
    return Err(Unavailable)
  }
  self.buffer = None
  self.bytes = None
  self.charge = None
  self.response_provider = None
  self.prepared_contract = None
  self.declaration = None
  self.selection = None
  match
    @resources.shrink_capacity_reservation(
      ledger, metadata, retained, execution,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  guard self.retained_keyed_original() &&
    self.phase is Parsed &&
    self.content is Some(original) &&
    physical_equal(original, content) &&
    self.ledger is Some(original_ledger) &&
    physical_equal(original_ledger, ledger) &&
    self.metadata is Some(original_metadata) &&
    physical_equal(original_metadata, metadata) else {
    return Err(Unavailable)
  }
  Ok(())
}
