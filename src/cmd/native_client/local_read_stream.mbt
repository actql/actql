///|
fn local_read_issue(issue : @local_host.NativeLocalReadBindingIssue) -> String {
  match issue {
    Adoption(issue) => local_host_issue(issue)
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
  let binding = match
    host.bind_result_read_policy(
      crypto,
      file,
      settings.principal,
      settings.connection,
    ) {
    Ok(value) => value
    Err(issue) => stop(local_read_issue(issue))
  }
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
  {
    errdefer (if !(store.close() is Ok(true)) {
      stop("LocalReadStoreCleanupPending attempt-id=" + attempt_id)
    })
    let refusal : Ref[@local_host.NativeLocalReadBindingIssue?] = Ref(None)
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
            refusal.val = Some(issue)
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
              refusal.val = Some(@local_host.SelectionMismatch)
              return None
            }
            Some(value)
          }
          Err(issue) => {
            refusal.val = Some(issue)
            None
          }
        }
      },
      delivery => {
        if !local_same_read_request(delivery.request, request) {
          return false
        }
        match
          binding.authorize_read_delivery(selected.request, store, delivery) {
          Ok(_) => true
          Err(issue) => {
            refusal.val = Some(issue)
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
      store, authority, local_utc_now, 65536, 8192, 64, 65536, 16384,
    ).unwrap_or_else(() => stop("LocalReadServiceUnavailable"))
    let journal = local_host_result(host.run_journal())
    let epoch = local_host_result(host.epoch_authority())
    let prior = journal
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
    if prior is Some(_) {
      stop(
        "LocalReadAttemptAlreadyStarted attempt-id=" +
        attempt_id +
        " lookup=delivery-attempt",
      )
    }
    let session = journal
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
    let sink = match native_local_stdout_sink(session, max_output) {
      Ok(value) => value
      Err(_) => {
        if session.close() is Err(_) {
          stop("LocalReadSessionCleanupPending attempt-id=" + attempt_id)
        }
        stop("LocalReadSinkUnavailable attempt-id=" + attempt_id)
      }
    }
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
  }
  if !(store.close() is Ok(true)) {
    stop("LocalReadStoreCleanupPending attempt-id=" + attempt_id)
  }
  ""
}
