///|
pub(all) enum NativeClientModelHttpIssue {
  ForeignOriginal
  Original(NativeLocalAdoptionIssue)
  Dispatch(@model.ModelExecutionIssue)
  RawPolicy(@host.ClientModelRawCaptureIssue)
  Raw(@model.ModelRawCaptureSaveIssue)
  Http(@http.NativeHttpIssue)
}

///|
// One Client and one consumed Entry. The Native command uses its existing
// outer loop to pump the socket on the Read which owns the Library. Core
// callbacks only register custody, observe the result or request local stop.
struct NativeClientModelHttpCall {
  capture : NativeLocalJournalCapture
  request : @model.ModelRequest
  prepared : @model.PreparedModelHttpChatRequest
  raw_registration : @host.ClientModelRawCaptureRegistration
  endpoint : String
  credential : @filesystem.PrivateFileProjection
  expires_at : Int64
  wire : Bytes
  mut original : @model.ModelPhysicalCall?
  mut next_in_runtime : NativeClientModelHttpCall?
  mut client : @http.Client?
  mut cancelled : Bool
  mut started : Bool
  mut start_refusal : NativeClientModelHttpIssue?
  mut advancing : Bool
  mut stop_scope_pending : Bool
  mut response : @http.NativeHttpResponse?
  mut raw : @model.ModelRawCaptureSave?
  mut decode_attempted : Bool
  mut outcome : @model.ModelPhysicalCallPoll?
}

///|
struct NativeModelHttpInstallation {
  capture : NativeLocalJournalCapture
  provider : @model.AdmittedStructuredModelProvider
  credential : @filesystem.PrivateFileProjection
}

///|
/// Borrow the original private-file projection through the existing installed
/// credential journal. The trusted installer funds this configuration/record
/// read in the same original Read preparation before calling this method.
pub fn NativeLocalJournalCapture::restore_model_http_installation_in_original_read(
  self : NativeLocalJournalCapture,
  provider : @model.AdmittedStructuredModelProvider,
  installation_setting : String,
) -> Result[NativeModelHttpInstallation, NativeClientModelHttpIssue] {
  self
  .with_current_adoption_material_in_original_read((host, _, operations) => {
    let files = host.session.settings.files
    guard files.iter().find_first(file => file.name == installation_setting)
      is Some(file) &&
      local_preparation_installation_selection(file.body) is Ok(selected) &&
      files.iter().find_first(file => file.name == selected.provider_file)
      is Some(provider_file) &&
      !files.any(candidate => candidate.name == selected.credential_file) &&
      selected.credential_file != host.session.source_name else {
      return Err(CustodyLost)
    }
    let wire = @utf8.decode(provider_file.body) catch {
      _ => return Err(Encoding)
    }
    guard @model.model_http_original_credential_reference(provider, wire)
      is Some(reference) &&
      reference == "file:" + selected.credential_file else {
      return Err(CustodyLost)
    }
    host.journal
    .transaction_with_reads(
      () => {
        host.installation_original_locked(
          file,
          provider_file,
          selected,
          false,
          () => self.check_original_read_lifetime().map_err(_ => CustodyLost),
        )
      },
      reads=Some(operations.reads),
    )
    .map_err(issue => NativeLocalAdoptionIssue::Journal(issue))
    .map(credential => { capture: self, provider, credential, })
  })
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
}

///|
/// The installed caller supplies its already prepared, dedicated Client and
/// the exact bytes retained by its paid portable HTTP codec preflight. This
/// constructor funds the Call controls and the response copy made by the FFI.
/// The Client's curl/TLS backing stays in its original physical allocation.
pub fn NativeLocalJournalCapture::prepare_model_http_call_in_original_read(
  self : NativeLocalJournalCapture,
  runtime : NativeLocalPackagedRuntime,
  client : @http.Client,
  request : @model.ModelRequest,
  installation : NativeModelHttpInstallation,
  prepared : @model.PreparedModelHttpChatRequest,
  raw_registration : @host.ClientModelRawCaptureRegistration,
  expires_at : Int64,
) -> Result[NativeClientModelHttpCall, NativeClientModelHttpIssue] {
  match self.check_original_read_lifetime() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  guard physical_equal(installation.capture, self) &&
    self.original_resources is Some(original) &&
    runtime.original_resources is Some(pair) &&
    physical_equal(pair, original.pair) &&
    runtime.original_read is Some((host, read)) &&
    physical_equal(host, original.host) &&
    physical_equal(read, original.read) &&
    runtime.model_http_load is Some(Ok(loaded)) &&
    !loaded.stopping &&
    client.uses_library(loaded.library) &&
    @model.prepared_model_http_chat_material(
      prepared,
      request,
      installation.provider,
    )
    is Some((endpoint, profile, wire)) else {
    return Err(ForeignOriginal)
  }
  // A dedicated Client may back only one retained Call. The list is bounded
  // by the same funded originals, including those awaiting physical close.
  let mut attached = loaded.calls
  while attached is Some(previous) {
    if previous.client is Some(original) && physical_equal(original, client) {
      return Err(ForeignOriginal)
    }
    attached = previous.next_in_runtime
  }
  let limits = @environment.model_response_profile_limits(profile)
  if expires_at < 1L ||
    !(client.response_limit() is Ok(maximum) &&
    maximum == limits.response_bytes.to_int64()) {
    return Err(ForeignOriginal)
  }
  let maximum_body = limits.response_bytes.to_int64()
  let (header, _, _, _, _) = @bootstrap.native_managed_value_layout()
  // poll_bearer_post copies curl's body into one managed Bytes before the
  // Client closes. Its whole allocation may overlap every other retained Call.
  guard header > 0L &&
    @execution.preparation_representation_cost({
      record_headers: 10L,
      reference_slots: 28L,
      scalar_words: 10L,
      owned_utf16_units: 0L,
      owned_wire_bytes: maximum_body + 1L,
    })
    is Some(copy) else {
    return Err(Original(ConfigurationLimit))
  }
  self
  .fund_model_http_material_in_original_read(copy, header + maximum_body + 1L)
  .map(_ => {
    let call : NativeClientModelHttpCall = {
      capture: self,
      request,
      prepared,
      raw_registration,
      endpoint,
      credential: installation.credential,
      expires_at,
      wire,
      original: None,
      next_in_runtime: loaded.calls,
      client: Some(client),
      cancelled: false,
      started: false,
      start_refusal: None,
      advancing: false,
      stop_scope_pending: false,
      response: None,
      raw: None,
      decode_attempted: false,
      outcome: None,
    }
    loaded.calls = Some(call)
    call
  })
}

///|
fn NativeLocalJournalCapture::fund_model_http_material_in_original_read(
  self : NativeLocalJournalCapture,
  retained : Int64,
  contiguous : Int64,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard self.original_resources is Some(original) else {
    return Err(Original(OriginalResourceScopePending))
  }
  self
  .check_original_read_lifetime()
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  .bind(_ => {
    original.host
    .prepare_domain_original_read_retained_construction(
      original.read,
      retained,
      retained,
      contiguous,
    )
    .map_err(issue => Original(OriginalResources(@arena.Read(issue))))
  })
}

///|
/// Use as the fixed transport start of this request's original physical Plan.
/// The Core gate has consumed the Entry before this binding can succeed.
pub fn NativeClientModelHttpCall::start_for_entry(
  self : NativeClientModelHttpCall,
  entry : @model.ModelCallEntry,
) -> @model.ModelPhysicalCall? {
  guard self.original is None && self.client is Some(_) && !self.cancelled else {
    return None
  }
  let original = @model.register_model_physical_call_for_request(
    entry,
    self.request,
    () => {
      let result = if self.cancelled && !self.started {
        // Local stop of the original unsent Call, after the outer driver
        // retained its typed refusal. No provider result was observed.
        @model.PhysicalRejected(@model.Cancelled, {
          input_tokens: None,
          output_tokens: None,
        })
      } else {
        self.outcome.unwrap_or(@model.PhysicalPending)
      }
      guard self.original is Some(call) else { return result }
      if self.client is None && !self.stop_scope_pending {
        @model.PhysicalIoQuiescent(call, result)
      } else {
        @model.PhysicalIoPending(call, result)
      }
    },
    () => self.cancelled = true,
    _ => self.client is None && !self.stop_scope_pending,
  )
  self.original = original
  original
}

///|
fn NativeClientModelHttpCall::start_in_original_read(
  self : NativeClientModelHttpCall,
  call : @model.ModelPhysicalCall,
  client : @http.Client,
) -> Result[Unit, NativeClientModelHttpIssue] {
  @model.check_prepared_model_http_chat_dispatch_current(
    call,
    self.prepared,
    self.raw_registration,
  )
  .map_err(issue => {
    match issue {
      @model.Dispatch(issue) => NativeClientModelHttpIssue::Dispatch(issue)
      @model.Raw(issue) => RawPolicy(issue)
    }
  })
  .bind(_ => {
    self.capture
    .check_original_read_lifetime()
    .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  })
  .bind(_ => {
    if self.cancelled {
      return Err(ForeignOriginal)
    }
    client
    .start_projected_bearer_post(
      self.endpoint,
      self.wire,
      self.credential,
      self.expires_at,
    )
    .map_err(issue => Http(issue))
  })
}

///|
fn NativeClientModelHttpCall::observe_unknown(
  self : NativeClientModelHttpCall,
) -> Unit {
  self.outcome = Some(
    @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
  )
}

///|
/// The existing outer Native loop calls once per readiness step, outside the
/// Core poll. A failed physical close retains the same Client for its next
/// cleanup step. A missing response can never schedule a replacement send.
pub fn NativeClientModelHttpCall::drive_in_original_read(
  self : NativeClientModelHttpCall,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard self.original is Some(call) && !self.advancing else {
    return Err(ForeignOriginal)
  }
  if !self.cancelled && self.start_refusal is Some(original) {
    return Err(original)
  }
  guard self.client is Some(client) else { return Ok(()) }
  match self.capture.check_original_read_lifetime() {
    Ok(_) => ()
    Err(issue) => {
      let failure = NativeClientModelHttpIssue::Original(issue)
      if !self.started && !self.cancelled {
        self.start_refusal = Some(failure)
      }
      return Err(failure)
    }
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  if self.cancelled {
    return Err(ForeignOriginal)
  }
  if self.response is None && self.outcome is None {
    if !self.started {
      if self.start_in_original_read(call, client) is Err(issue) {
        // The managed preflight and the C setup return errors before multi
        // performs I/O. Cleanup can still be pending (for example, a failed
        // credential descriptor close). Keep the original cause and Client.
        self.start_refusal = Some(issue)
        return Err(issue)
      }
      self.started = true
    }
    match client.poll_bearer_post() {
      Ok(None) => return Ok(())
      Ok(Some(response)) => self.response = Some(response)
      Err(issue) => {
        self.observe_unknown()
        return Err(Http(issue))
      }
    }
  }
  self.close_client_in_original_read(client)
}

///|
/// The outer command retires physical children before the original Core
/// cleanup poll. This uses the same captured Read in cleanup mode, independent
/// of whether the Journal still authorizes dispatch, observation or disclosure.
pub fn NativeClientModelHttpCall::close_in_original_cleanup(
  self : NativeClientModelHttpCall,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard !self.advancing && self.capture.original_resources is Some(original) else {
    return Err(Original(OriginalResourceScopePending))
  }
  self.cancelled = true
  if self.started && self.outcome is None {
    self.observe_unknown()
  }
  // A completed Client has no claim on another child's pending Read leave.
  // Still finish the failed scope return from our own stop before ACK.
  if self.client is None && !self.stop_scope_pending {
    return Ok(())
  }
  self.advancing = true
  defer {
    self.advancing = false
  }
  if original.interrupted {
    match original.finish_pending_leave() {
      Ok(_) => self.stop_scope_pending = false
      Err(issue) => return Err(Original(issue))
    }
  }
  guard self.client is Some(client) else { return Ok(()) }
  let stopped = original.stage(
    @arena.HostRead,
    () => {
      Ok(
        client
        .close_bearer_post_in_original_scope()
        .map(_ => self.client = None)
        .map_err(issue => Http(issue)),
      )
    },
    cleanup=true,
  )
  self.stop_scope_pending = original.interrupted
  stopped
  .map_err(issue => NativeClientModelHttpIssue::Original(issue))
  .bind(result => result)
}

///|
/// Retire HTTP children before returning to the business execution's Core
/// cleanup. A failed return retains the same head and all remaining children.
pub fn NativeLocalPackagedRuntime::close_model_http_calls(
  self : NativeLocalPackagedRuntime,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard self.model_http_load is Some(Ok(loaded)) else { return Ok(()) }
  loaded.stopping = true
  while loaded.calls is Some(call) {
    match call.close_in_original_cleanup() {
      Err(issue) => return Err(issue)
      Ok(_) => {
        loaded.calls = call.next_in_runtime
        call.next_in_runtime = None
      }
    }
  }
  Ok(())
}

///|
fn NativeClientModelHttpCall::close_client_in_original_read(
  self : NativeClientModelHttpCall,
  client : @http.Client,
) -> Result[Unit, NativeClientModelHttpIssue] {
  client
  .close_checked()
  .map(_ => self.client = None)
  .map_err(issue => Http(issue))
}

///|
/// A discarded preflight may close its dedicated Client before an Entry
/// exists. Once registered, cleanup instead follows the same physical call.
pub fn NativeClientModelHttpCall::close_unentered_in_original_read(
  self : NativeClientModelHttpCall,
) -> Result[Unit, NativeClientModelHttpIssue] {
  if self.original is Some(_) || self.started || self.advancing {
    return Err(ForeignOriginal)
  }
  guard self.client is Some(client) else { return Ok(()) }
  match self.capture.check_original_read_lifetime() {
    Ok(_) => self.close_client_in_original_read(client)
    Err(issue) => Err(Original(issue))
  }
}

///|
/// The Raw adapter borrows only the physically observed body and status from
/// this retained Client. Persist and acknowledge this same view before any
/// typed decoder result can be published.
pub fn NativeClientModelHttpCall::observe_raw_in_original_read(
  self : NativeClientModelHttpCall,
  observed_at : String,
) -> Result[(@model.ModelRawCaptureSave, Bytes), NativeClientModelHttpIssue] {
  match self.capture.check_original_read_lifetime() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  guard !self.cancelled &&
    self.client is None &&
    self.original is Some(call) &&
    self.response is Some(response) &&
    self.outcome is None else {
    return Err(ForeignOriginal)
  }
  let saved = match self.raw {
    Some(original) => Ok(original)
    None =>
      @model.observe_model_raw_capture(
        call,
        self.raw_registration,
        "sha256:" + @sha.hex(response.body),
        response.body.length(),
        response.status,
        true,
        observed_at,
      ).map_err(issue => Raw(issue))
  }
  saved.map(value => {
    self.raw = Some(value)
    (value, response.body)
  })
}

///|
/// Borrow the confirmed receipt on the original Read. The decoded text stays
/// on that Read until the same original Model observes the settled Call.
pub fn NativeClientModelHttpCall::adopt_saved_chat(
  self : NativeClientModelHttpCall,
  receipt : @model.ModelSavedRawReceipt,
) -> Result[Unit, NativeClientModelHttpIssue] {
  guard !self.cancelled &&
    !self.decode_attempted &&
    self.client is None &&
    self.original is Some(call) &&
    self.raw is Some(raw) &&
    self.response is Some(response) &&
    self.outcome is None &&
    @model.model_saved_raw_receipt_matches(
      receipt,
      call,
      @publication.model_raw_response_value(
        @model.model_raw_capture_save_binding(raw),
      ),
    ) else {
    return Err(ForeignOriginal)
  }
  let units = response.body.length().to_int64()
  let (header, unit, terminator, _, _) = @bootstrap.native_managed_value_layout()
  // The pinned decoder fills one UInt16 array then presents its backing as a
  // String. Reserve for the largest exact-body decode and retained carrier.
  guard header > 0L &&
    unit == 2L &&
    terminator == unit &&
    @execution.preparation_representation_cost({
      record_headers: 6L,
      reference_slots: 13L,
      scalar_words: 3L,
      owned_utf16_units: units + 1L,
      owned_wire_bytes: 0L,
    })
    is Some(decoded) else {
    return Err(Original(ConfigurationLimit))
  }
  self.decode_attempted = true
  if self.capture.fund_model_http_material_in_original_read(
      decoded,
      header + units * unit + terminator,
    )
    is Err(issue) {
    return Err(issue)
  }
  let body = @utf8.decode(response.body, ignore_bom=true) catch {
    _ => {
      // The original Raw was confirmed even when the provider used
      // non-UTF8. An observed complete HTTP reply still has a known outcome.
      let failure = if response.status >= 200 && response.status < 300 {
        @model.SchemaInvalid
      } else {
        @model.ProviderError
      }
      self.outcome = Some(
        @model.PhysicalRejected(failure, {
          input_tokens: None,
          output_tokens: None,
        }),
      )
      return Ok(())
    }
  }
  @model.model_saved_raw_chat_response(receipt, body, None)
  .map(value => self.outcome = Some(@model.PhysicalChatResponse(value)))
  .map_err(issue => Raw(issue))
}
