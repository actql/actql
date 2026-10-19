///|
// Result lookup has explicit current Run and named-Result authority. A
// Submission, grant reference or historical attempt supplies no permission.
fn local_delivery_lookup_allowed(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  scope : String,
  result_name : String,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> Bool {
  local_run_operation_allowed(host, settings, crypto, scope, "read", capture~) &&
  (match capture {
    None =>
      host.authorize({
        principal: settings.principal,
        connection: settings.connection,
        resource: "result/" + result_name,
        operation: "read",
      })
    Some(original) =>
      original.authorize_in_original_read({
        principal: settings.principal,
        connection: settings.connection,
        resource: "result/" + result_name,
        operation: "read",
      })
  })
  is Ok(Allow(_))
}

///|
fn local_original_result_store(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  sqlite : @local_sqlite.Library,
  namespace_id : String,
) -> @local_store.Store raise ClientStop {
  let file = settings.run_file.unwrap_or_else(() => {
    stop("LocalRunOriginalNotSelected")
  })
  let original = local_host_result(host.selected_configuration(file))
  let run = local_run_installation(
    @utf8.decode(original) catch {
      _ => stop("InvalidLocalRunInstallation")
    },
  )
  if run.namespace_id != namespace_id {
    stop("LocalOriginalRunReferenceMismatch")
  }
  let managed = local_host_result(host.managed_root_path()).unwrap_or_else(() => {
    stop("LocalManagedRootRequired")
  })
  let root = @local_filesystem.open_private_root(managed).unwrap_or_else(() => {
    stop("LocalManagedRootUntrusted")
  })
  root
  .open_child(run.store_name)
  .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
  .private_ownership()
  .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
  |> ignore
  @local_store.open_existing_store(
    sqlite,
    managed + "/" + run.store_name,
    run.store_authority_cid,
    run.store_capacity_bytes,
    run.store_objects,
    run.store_record_bytes,
  ).unwrap_or_else(() => stop("LocalOriginalStoreUnavailable"))
}

///|
fn local_delivery_contract_json(
  contract : @publication.PublicationContract,
) -> Json raise ClientStop {
  let text = @publication.publication_contract_json(contract)
  guard @source.parse_json_bytes_preserving(@utf8.encode(text), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    })
    is Ok(_) else {
    stop("LocalDeliveryOriginalInvalid")
  }
  @json.parse(text) catch {
    _ => stop("LocalDeliveryOriginalInvalid")
  }
}

///|
// Metadata-only use of the existing original-Submission/Result owners. Read
// admission, byte disclosure and receipt creation are deliberately unavailable
// in this service; lookup cannot invoke any of these hooks or advance a Run.
fn local_delivery_attempt_lookup(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  sqlite : @local_sqlite.Library,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let scope = local_host_result(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
  )
  if !local_run_operation_allowed(host, settings, crypto, scope, "read") {
    stop("LocalDeliveryLookupAuthorizationDenied")
  }
  let result_name = required(child, "result-name")
  let purpose = required(child, "purpose")
  let attempt_id = required(child, "attempt-id")
  if result_name.is_empty() ||
    result_name.length() > 128 ||
    purpose.is_empty() ||
    purpose.length() > 256 ||
    attempt_id.is_empty() ||
    attempt_id.length() > 256 {
    stop("InvalidLocalDeliveryLookup")
  }
  let current = () => {
    local_delivery_lookup_allowed(host, settings, crypto, scope, result_name)
  }
  if !current() {
    stop("LocalDeliveryLookupAuthorizationDenied")
  }
  let selected = local_original_run_selection(
    host, input_root, child, scope, current,
  )
  if !current() {
    stop("LocalDeliveryLookupAuthorizationDenied")
  }
  let store = local_original_result_store(
    host,
    settings,
    sqlite,
    selected.namespace_id,
  )
  let reply = {
    errdefer (if !(store.close() is Ok(true)) {
      stop("LocalDeliveryStoreCleanupPending")
    })
    let authority = @local_result.install_native_result_access_authority(
      _ => false,
      _ => None,
      _ => false,
      authorize_lookup=Some(queried => {
        queried.namespace_id == selected.namespace_id &&
        queried.authority_scope_cid == scope &&
        queried.run_definition_cid == selected.run_definition_cid &&
        queried.principal_id == settings.principal &&
        queried.purpose == purpose &&
        queried.result_name == result_name &&
        queried.attempt_id == attempt_id &&
        current()
      }),
    )
    let service = @local_result.install_native_result_access_service(
      store, authority, local_utc_now, 65536, 8192, 64, 65536, 16384,
    ).unwrap_or_else(() => stop("LocalDeliveryLookupUnavailable"))
    let journal = local_host_result(host.run_journal())
    let epoch = local_host_result(host.epoch_authority())
    let observed = journal
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
      .unwrap_or_else(() => stop("LocalDeliveryLookupUnavailable"))
    if !current() {
      stop("LocalDeliveryLookupAuthorizationDenied")
    }
    let fields : Map[String, Json] = Map([
      ("kind", Json::string("local_delivery_attempt_lookup")),
      ("ref", selected.reference),
      ("resultName", Json::string(result_name)),
      ("purpose", Json::string(purpose)),
      ("attemptId", Json::string(attempt_id)),
    ])
    match observed {
      None => fields["history"] = Json::string("unresolved")
      Some(original) => {
        fields["history"] = Json::string("retained")
        fields["attempt"] = local_delivery_contract_json(original.attempt)
        fields["record"] = match original.record {
          None => Json::null()
          Some(record) => local_delivery_contract_json(record)
        }
        fields["hostReleaseReceipt"] = match original.host_release_receipt {
          None => Json::null()
          Some(receipt) => local_delivery_contract_json(receipt)
        }
      }
    }
    encode_request_json(Json::object(fields), 65536)
  }
  if !(store.close() is Ok(true)) {
    stop("LocalDeliveryStoreCleanupPending")
  }
  if !current() {
    stop("LocalDeliveryLookupAuthorizationDenied")
  }
  reply
}
