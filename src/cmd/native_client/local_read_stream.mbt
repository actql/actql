///|
fn local_read_issue(issue : @local_host.NativeLocalReadBindingIssue) -> String {
  match issue {
    MaterialUnavailable => "LocalResultMaterialUnavailable"
    FileOutputUnavailable => "LocalResultFileOutputUnavailable"
    FileOutput(_) => "LocalResultFileOutputFailed"
    Adoption(issue) => local_host_issue(issue)
    OriginalRead(primary, _) =>
      "LocalReadOriginalReturnPending" +
      (match primary {
        Some(issue) => " original=" + local_read_issue(issue)
        None => ""
      })
    Journal(CustodyLost) => "LocalReadCustodyLost"
    Journal(TransactionUnknown) => "LocalReadAdmissionUnknown"
    Journal(CapacityExceeded) => "LocalReadCapacityExceeded"
    Journal(ForeignRun) => "LocalReadOriginalMismatch"
    AuthorizationDenied | Journal(AuthorizationDenied) =>
      "LocalReadAuthorizationDenied"
    Disabled => "LocalReadDisabled"
    PolicyExpired => "LocalReadPolicyExpired"
    PolicyNotSelected => "LocalReadPolicyNotSelected"
    SelectionMismatch => "LocalReadSelectionMismatch"
    InvalidObservationTime => "LocalReadInvalidObservationTime"
    _ => "LocalReadRefused"
  }
}

///|
fn local_same_read_request(
  left : @local_result.NativeResultAccessRequest,
  right : @local_result.NativeResultAccessRequest,
) -> Bool {
  left.namespace_id == right.namespace_id &&
  left.authority_scope_cid == right.authority_scope_cid &&
  left.run_definition_cid == right.run_definition_cid &&
  left.principal_id == right.principal_id &&
  left.purpose == right.purpose &&
  left.result_name == right.result_name &&
  left.format == right.format &&
  left.attempt_id == right.attempt_id
}

///|
// A row cannot exceed the selected total output ceiling. Keep the existing
// durable framer's independent16MiB implementation limit. This is working
// geometry only: the same original authority still admits max_output against
// its actual grant before any delivery or payload read starts.
fn local_result_row_frame_limit(max_output : Int) -> Int {
  Int::min(max_output, 16777216)
}

///|
// Payload and metadata lookup remain separate operations. An existing attempt
// is never reopened, even after a lost start reply or uncertain sink ACK.
fn local_result_stream(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  sqlite : @local_sqlite.Library,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let file = settings.read_file.unwrap_or_else(() => {
    stop("LocalReadPolicyOriginalNotSelected")
  })
  let scope = local_host_result(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
  )
  let result_name = required(child, "result-name")
  let purpose = required(child, "purpose")
  let format = required(child, "format")
  let attempt_id = required(child, "attempt-id")
  let max_output = positive_int(
    required(child, "max-output-bytes"),
    "max-output-bytes",
  )
  if result_name.length() > 128 ||
    purpose.length() > 256 ||
    attempt_id.length() > 256 ||
    max_output > 536870912 ||
    !(format == "jsonl" || format == "json" || format == "csv") {
    stop("InvalidLocalReadSelection")
  }
  let current = () => {
    local_delivery_lookup_allowed(host, settings, crypto, scope, result_name)
  }
  let selected = local_original_run_selection(
    host, input_root, child, scope, current,
  )
  local_selected_result_stream(
    host~,
    settings~,
    crypto~,
    sqlite~,
    file~,
    scope~,
    selected~,
    purpose~,
    result_name~,
    format~,
    attempt_id~,
    max_output~,
    current~,
  )
}

///|
// Keep the original selected Run and current callback together; callers do not
// replace the admission, delivery history or exact-handle cleanup below.
fn local_selected_result_stream(
  host~ : @local_host.NativeLocalHostConnection,
  settings~ : LocalHostSettings,
  crypto~ : @local_crypto.Library,
  sqlite~ : @local_sqlite.Library,
  file~ : String,
  scope~ : String,
  selected~ : LocalOriginalRunSelection,
  purpose~ : String,
  result_name~ : String,
  format~ : String,
  attempt_id~ : String,
  max_output~ : Int,
  current~ : () -> Bool,
) -> String raise ClientStop {
  let binding = local_read_binding_for_original(
    host~,
    settings~,
    crypto~,
    file~,
    selected~,
  )
  let request : @local_result.NativeResultAccessRequest = {
    namespace_id: selected.namespace_id,
    authority_scope_cid: scope,
    run_definition_cid: selected.run_definition_cid,
    principal_id: settings.principal,
    purpose,
    result_name,
    format,
    attempt_id,
  }
  match
    binding.authorize_read_request(
      selected.request,
      request,
      local_utc_now(),
      max_output_bytes=Some(max_output),
    ) {
    Ok(_) => ()
    Err(issue) => stop(local_read_issue(issue))
  }
  let store = local_original_result_store(
    host,
    settings,
    sqlite,
    selected.namespace_id,
  )
  let reply = {
    errdefer local_result_store_close(store, attempt_id)
    local_admitted_result_stream(
      host~,
      settings~,
      selected~,
      binding~,
      request~,
      scope~,
      purpose~,
      result_name~,
      format~,
      attempt_id~,
      max_output~,
      current~,
      store~,
    )
  }
  local_result_store_close(store, attempt_id)
  reply
}

///|
fn local_read_binding_for_original(
  host~ : @local_host.NativeLocalHostConnection,
  settings~ : LocalHostSettings,
  crypto~ : @local_crypto.Library,
  file~ : String,
  selected~ : LocalOriginalRunSelection,
) -> @local_host.NativeLocalReadPolicyBinding raise ClientStop {
  let binding_result = match local_run_policy_binding(host, settings, crypto) {
    None =>
      host.bind_result_read_policy(
        crypto,
        file,
        settings.principal,
        settings.connection,
      )
    Some(policy) =>
      if policy
        .original_run_requires_finite_policy(selected.request)
        .unwrap_or_else(() => stop("LocalRunPolicyOriginalUnavailable")) {
        host.bind_result_read_policy_for_run(
          policy,
          selected.submission,
          selected.request,
          @env.now().to_double(),
        )
      } else {
        host.bind_result_read_policy(
          crypto,
          file,
          settings.principal,
          settings.connection,
        )
      }
  }
  match binding_result {
    Ok(value) => value
    Err(issue) => stop(local_read_issue(issue))
  }
}

///|
// Only this original Store's ACK settles its cleanup. Keep the call directly
// around work so no additional callback holds decoded material through close.
fn local_result_store_close(
  store : @local_store.Store,
  attempt_id : String,
) -> Unit raise ClientStop {
  if !(store.close() is Ok(true)) {
    stop("LocalReadStoreCleanupPending attempt-id=" + attempt_id)
  }
}

///|
// The caller retains Store cleanup; this is the existing admission/delivery
// body, including lookup-first and the exact session/sink close sequence.
fn local_admitted_result_stream(
  host~ : @local_host.NativeLocalHostConnection,
  settings~ : LocalHostSettings,
  selected~ : LocalOriginalRunSelection,
  binding~ : @local_host.NativeLocalReadPolicyBinding,
  request~ : @local_result.NativeResultAccessRequest,
  scope~ : String,
  purpose~ : String,
  result_name~ : String,
  format~ : String,
  attempt_id~ : String,
  max_output~ : Int,
  current~ : () -> Bool,
  store~ : @local_store.Store,
  retained? : LocalCommandBusinessOriginal? = None,
  captured_selection? : @local_host.NativeClientOriginalRunSelection? = None,
  material? : @local_result.NativeResultMaterialReceiver? = None,
  file_destination? : LocalResultFileSelection? = None,
) -> String raise ClientStop {
  if captured_selection is Some(_) && retained is None {
    stop("LocalReadOriginalCustodyUnavailable")
  }
  if retained is Some(original) {
    guard original.store is Some(actual) &&
      physical_equal(actual, store) &&
      original.operation is Some(_) &&
      original.store_root_operation is Some(_) &&
      (
        original.result_binding is None ||
        (
          (material is Some(_) || file_destination is Some(_)) &&
          original.result_binding is Some(prior) &&
          physical_equal(prior, binding)
        )
      ) &&
      original.result_service is None &&
      original.result_session is None &&
      original.result_sink is None &&
      original.result_refusal is None &&
      original.result_cleanup_issue is None else {
      stop("LocalReadOriginalCustodyUnavailable")
    }
  }
  let refusal : Ref[@local_host.NativeLocalReadBindingIssue?] = Ref(None)
  if retained is Some(original) {
    original.result_binding = Some(binding)
    original.result_refusal = Some(refusal)
  }
  if file_destination is Some(destination) {
    guard retained is Some(_) &&
      captured_selection is Some(_) &&
      material is None else {
      stop("LocalReadOriginalCustodyUnavailable")
    }
    let location = local_result_file_location(destination.path)
    match
      binding.open_file_output_parent(
        selected.request,
        store,
        request,
        local_utc_now(),
        destination.path,
        location.parent_path,
        location.directory_name,
      ) {
      Ok(_) => ()
      Err(issue) => stop(local_read_issue(issue))
    }
  }
  let authority = @local_result.install_native_result_access_authority(
    queried => {
      if !local_same_read_request(queried, request) {
        return false
      }
      match
        binding.authorize_read_request(
          selected.request,
          queried,
          local_utc_now(),
        ) {
        Ok(_) => true
        Err(issue) => {
          if refusal.val is None {
            refusal.val = Some(issue)
          }
          false
        }
      }
    },
    facts => {
      if !local_same_read_request(facts.request, request) {
        return None
      }
      match binding.admit_read(selected.request, store, facts) {
        Ok(value) => {
          // An explicit sink limit can be smaller, never larger than the
          // adopted ceiling. The original grant's identity is unchanged.
          if max_output > value.max_bytes {
            if refusal.val is None {
              refusal.val = Some(@local_host.SelectionMismatch)
            }
            return None
          }
          Some(value)
        }
        Err(issue) => {
          if refusal.val is None {
            refusal.val = Some(issue)
          }
          None
        }
      }
    },
    delivery => {
      if !local_same_read_request(delivery.request, request) {
        return false
      }
      match binding.authorize_read_delivery(selected.request, store, delivery) {
        Ok(_) => true
        Err(issue) => {
          if refusal.val is None {
            refusal.val = Some(issue)
          }
          false
        }
      }
    },
    authorize_lookup=Some(queried => {
      queried.namespace_id == request.namespace_id &&
      queried.authority_scope_cid == scope &&
      queried.run_definition_cid == request.run_definition_cid &&
      queried.principal_id == request.principal_id &&
      queried.purpose == purpose &&
      queried.result_name == result_name &&
      queried.attempt_id == attempt_id &&
      current()
    }),
  )
  let service = @local_result.install_native_result_access_service(
    store,
    authority,
    local_utc_now,
    65536,
    8192,
    64,
    local_result_row_frame_limit(max_output),
    16384,
  ).unwrap_or_else(() => stop("LocalReadServiceUnavailable"))
  if retained is Some(original) {
    original.result_service = Some(service)
  }
  // Captured reads already route the same Journal/Epoch through the original
  // Read/SQLite exchange. The legacy getters perform an unscoped full binding
  // check and must run only for their separate legacy branch.
  let legacy_originals = match captured_selection {
    None =>
      Some(
        (
          local_host_result(host.run_journal()),
          local_host_result(host.epoch_authority()),
        ),
      )
    Some(_) => None
  }
  let prior = {
    native_timing_begin(24)
    defer native_timing_end(24)
    match captured_selection {
      Some(original) =>
        binding
        .lookup_submitted_result_delivery_in_original_read(
          original,
          service,
          request,
          local_utc_now(),
          @env.now().to_double(),
        )
        .unwrap_or_else(() => {
          stop("LocalReadHistoryUnknown attempt-id=" + attempt_id)
        })
      None => {
        guard legacy_originals is Some((journal, epoch)) else {
          stop("LocalReadOriginalCustodyUnavailable")
        }
        journal
        .lookup_submitted_result_delivery(
          epoch,
          selected.submission,
          scope,
          current,
          @env.now().to_double(),
          service,
          {
            namespace_id: selected.namespace_id,
            principal_id: settings.principal,
            purpose,
            result_name,
            attempt_id,
          },
        )
        .unwrap_or_else(() => {
          stop("LocalReadHistoryUnknown attempt-id=" + attempt_id)
        })
      }
    }
  }
  if prior is Some(_) {
    if file_destination is Some(_) && captured_selection is Some(original) {
      return binding.completed_file_receipt_in_original_read(
          original,
          service,
          request,
          local_utc_now(),
          @env.now().to_double(),
        )
        |> local_result_read_value
    }
    stop(
      "LocalReadAttemptAlreadyStarted attempt-id=" +
      attempt_id +
      " lookup=delivery-attempt",
    )
  }
  if file_destination is Some(_) {
    match binding.create_file_output_writer(local_utc_now()) {
      Ok(_) => ()
      Err(issue) => stop(local_read_issue(issue) + " attempt-id=" + attempt_id)
    }
    match
      binding.authorize_read_request(
        selected.request,
        request,
        local_utc_now(),
        max_output_bytes=Some(max_output),
      ) {
      Ok(_) => ()
      Err(issue) => stop(local_read_issue(issue) + " attempt-id=" + attempt_id)
    }
  }
  let session = {
    native_timing_begin(25)
    defer native_timing_end(25)
    match captured_selection {
      Some(original) => {
        match
          binding.resolve_submitted_result_in_original_read(
            original,
            service,
            request,
            local_utc_now(),
            @env.now().to_double(),
          ) {
          Ok(_) => ()
          Err(issue) =>
            stop(local_read_issue(issue) + " attempt-id=" + attempt_id)
        }
        // The actual session is acquired outside the Journal callback and
        // retained immediately below, before sink construction or polling.
        @local_result.open_native_result_access(service, request).unwrap_or_else(() => {
            if refusal.val is Some(issue) {
              stop(local_read_issue(issue) + " attempt-id=" + attempt_id)
            }
            stop(
              "LocalReadStartUnknown attempt-id=" +
              attempt_id +
              " lookup=delivery-attempt",
            )
          },
        )
      }
      None => {
        guard legacy_originals is Some((journal, epoch)) else {
          stop("LocalReadOriginalCustodyUnavailable")
        }
        journal
        .open_submitted_result(
          epoch,
          selected.submission,
          scope,
          current,
          @env.now().to_double(),
          service,
          {
            namespace_id: selected.namespace_id,
            principal_id: settings.principal,
            purpose,
            result_name,
            format,
            attempt_id,
          },
        )
        .unwrap_or_else(() => {
          if refusal.val is Some(issue) {
            stop(local_read_issue(issue) + " attempt-id=" + attempt_id)
          }
          stop(
            "LocalReadStartUnknown attempt-id=" +
            attempt_id +
            " lookup=delivery-attempt",
          )
        })
      }
    }
  }
  // Retain the acquired session before sink construction or another callback.
  if retained is Some(original) {
    original.result_session = Some(session)
  }
  if material is Some(receiver) {
    match receiver.attach(session) {
      Err(_) =>
        stop("LocalResultMaterialSessionUnavailable attempt-id=" + attempt_id)
      Ok(_) => ()
    }
    while true {
      match receiver.poll() {
        Ok(true) => break
        Ok(false) => ()
        Err(_) => {
          if refusal.val is Some(issue) {
            stop(local_read_issue(issue) + " attempt-id=" + attempt_id)
          }
          stop("LocalResultMaterialReadUnknown attempt-id=" + attempt_id)
        }
      }
    }
    match receiver.write_table(max_output) {
      Err(_) => stop("LocalResultTableOutputUnknown attempt-id=" + attempt_id)
      Ok(_) => ()
    }
    if receiver.close() is Err(_) {
      stop("LocalReadSessionCleanupPending attempt-id=" + attempt_id)
    }
    return ""
  }
  let sink_result = if file_destination is Some(_) {
    binding.install_file_result_sink(session, max_output).map_err(_ => ())
  } else {
    native_local_stdout_sink(session, max_output).map_err(_ => ())
  }
  let sink = match sink_result {
    Ok(value) => value
    Err(_) => {
      if session.close() is Err(_) {
        stop("LocalReadSessionCleanupPending attempt-id=" + attempt_id)
      }
      stop("LocalReadSinkUnavailable attempt-id=" + attempt_id)
    }
  }
  if retained is Some(original) {
    original.result_sink = Some(sink)
  }
  native_timing_begin(26)
  defer native_timing_end(26)
  let mut result : String? = None
  while true {
    match sink.poll() {
      Ok(SinkProgress) => ()
      Ok(SinkComplete(_)) => break
      Ok(SinkFailed(_, _)) => {
        result = Some("LocalReadInterrupted")
        break
      }
      Err(_) => {
        result = Some("LocalReadConfirmationUnknown")
        break
      }
    }
  }
  // Close this exact handle; no new read, repeated write or receipt retry.
  if sink.close() is Err(_) {
    stop("LocalReadSessionCleanupPending attempt-id=" + attempt_id)
  }
  if result is Some(reason) {
    if refusal.val is Some(issue) {
      stop(local_read_issue(issue) + " attempt-id=" + attempt_id)
    }
    stop(reason + " attempt-id=" + attempt_id + " lookup=delivery-attempt")
  }
  if file_destination is Some(_) && captured_selection is Some(original) {
    return binding.completed_file_receipt_in_original_read(
        original,
        service,
        request,
        local_utc_now(),
        @env.now().to_double(),
      )
      |> local_result_read_value
  }
  ""
}
