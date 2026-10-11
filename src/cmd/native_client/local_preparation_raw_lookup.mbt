///|
// Current-authorized observation metadata only. No raw body, credential,
// issuer configuration or protected request is copied into CLI stdout.
priv struct LocalPreparationRawMetadata {
  use_cid : String
  outcome : String
  use_status : Int?
  raw_use_cid : String
  raw_status : Int
  body_bytes : Int
  body_digest : String
}

///|
fn local_preparation_raw_metadata(
  operation_cid : String,
  use_id : String,
  recovered : @raw_resource.NativeLocalPreparationRawRecovery,
) -> String raise ClientStop {
  local_preparation_raw_metadata_record(operation_cid, use_id, {
    use_cid: recovered.original_use.use_cid,
    outcome: recovered.original_use.outcome,
    use_status: recovered.original_use.status,
    raw_use_cid: recovered.observation.use_cid,
    raw_status: recovered.observation.status,
    body_bytes: recovered.observation.body.length(),
    body_digest: recovered.observation.body_digest,
  })
}

///|
fn local_preparation_raw_metadata_record(
  operation_cid : String,
  use_id : String,
  metadata : LocalPreparationRawMetadata,
) -> String raise ClientStop {
  if metadata.use_cid != metadata.raw_use_cid {
    stop("LocalPreparationRawUseMismatch")
  }
  encode_request_json(
    Json::object(
      Map([
        ("kind", Json::string("local_preparation_raw_lookup")),
        ("operationCid", Json::string(operation_cid)),
        ("useId", Json::string(use_id)),
        ("useCid", Json::string(metadata.use_cid)),
        ("originalUseOutcome", Json::string(metadata.outcome)),
        (
          "originalUseStatus",
          metadata.use_status
          .map(value => Json::number(value.to_double()))
          .unwrap_or(Json::null()),
        ),
        (
          "rawResponse",
          Json::object(
            Map([
              ("status", Json::number(metadata.raw_status.to_double())),
              ("bodyBytes", Json::number(metadata.body_bytes.to_double())),
              ("bodyDigest", Json::string(metadata.body_digest)),
            ]),
          ),
        ),
      ]),
    ),
    4096,
  )
}

///|
fn local_preparation_raw_lookup_issue(
  issue : @local_host.NativeLocalPreparationRawReadIssue,
) -> String {
  match issue {
    UnavailableOriginalGrant => "LocalPreparationRawOriginalGrantUnavailable"
    UnavailableOriginalTarget => "LocalPreparationRawOriginalTargetUnavailable"
    Preparation(AuthorizationDenied) =>
      "LocalPreparationRawReadAuthorizationDenied"
    Preparation(ForeignInstallation) => "LocalPreparationRawReferenceMismatch"
    Preparation(Adoption(issue)) => local_host_issue(issue)
    Journal(ChangedIntent | ForeignRun) =>
      "LocalPreparationRawReferenceMismatch"
    Journal(TransactionUnknown) => "LocalPreparationRawLookupUnknown"
    Journal(CustodyLost) => "LocalPreparationRawCustodyLost"
    Resource(AccessDenied) => "LocalPreparationRawReadAuthorizationDenied"
    Resource(Credential(_)) => "LocalPreparationRawOriginalUseUnavailable"
    Resource(RawObservation(_)) => "LocalPreparationRawObservationUnavailable"
    _ => "LocalPreparationRawLookupUnavailable"
  }
}

///|
// Join only the submitted original Run and its immutable grant/use. The
// existing reader has no send capability; an unavailable record never causes
// another GET, grant issue, ordinal, Source acquisition or Run preparation.
fn local_preparation_raw_lookup(
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
  let current = () => {
    local_run_operation_allowed(host, settings, crypto, scope, "read")
  }
  if !current() {
    stop("LocalPreparationRawReadAuthorizationDenied")
  }
  let use_id = required(child, "use-id")
  if use_id.is_empty() || use_id.length() > 256 {
    stop("InvalidLocalPreparationUseId")
  }
  let reference = @local_host.admit_native_local_preparation_grant_reference(
    crypto,
    required(child, "operation-cid"),
    @utf8.encode(
      text_file(input_root, required(child, "grant-ref-file"), 49152L),
    ),
  ).unwrap_or_else(() => stop("InvalidLocalPreparationGrantReference"))
  let selected = local_original_run_selection(
    host, input_root, child, scope, current,
  )
  if !reference.matches_original_request(selected.request) {
    stop("LocalPreparationRawReferenceMismatch")
  }
  if !current() {
    stop("LocalPreparationRawReadAuthorizationDenied")
  }
  match
    host.authorize_preparation_raw_reference(
      crypto,
      settings.principal,
      settings.connection,
      reference,
    ) {
    Ok(_) => ()
    Err(issue) => stop(local_preparation_raw_lookup_issue(issue))
  }
  let store = local_original_result_store(
    host,
    settings,
    sqlite,
    selected.namespace_id,
  )
  let (reply, reader) = {
    errdefer (if !(store.close() is Ok(true)) {
      stop("LocalPreparationRawStoreCleanupPending")
    })
    let reader = match
      host.restore_preparation_raw_reader(
        crypto,
        settings.principal,
        settings.connection,
        reference,
        store,
        selected.namespace_id,
      ) {
      Ok(value) => value
      Err(issue) => stop(local_preparation_raw_lookup_issue(issue))
    }
    let observation = match reader.lookup(use_id) {
      Ok(value) => value
      Err(issue) => stop(local_preparation_raw_lookup_issue(issue))
    }
    let result = local_preparation_raw_metadata(
      reference.operation_cid(),
      use_id,
      observation,
    )
    if !current() {
      stop("LocalPreparationRawReadAuthorizationDenied")
    }
    (result, reader)
  }
  if !(store.close() is Ok(true)) {
    stop("LocalPreparationRawStoreCleanupPending")
  }
  match reader.authorize_return(use_id) {
    Ok(_) => ()
    Err(issue) => stop(local_preparation_raw_lookup_issue(issue))
  }
  reply
}
