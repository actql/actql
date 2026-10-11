///|
// Metadata-only CLI operation. Original Submission and full Run reference
// select the retained row; no preparation, grant, Preview or send is requested.
fn local_checkpoint_metadata_lookup(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let scope = local_host_result(
    host.authority_scope_cid(settings.principal, settings.connection, crypto),
  )
  let current = () => {
    local_run_operation_allowed(host, settings, crypto, scope, "read")
  }
  let selected = local_original_run_selection(
    host, input_root, child, scope, current,
  )
  let original = match
    host.lookup_submitted_checkpoint_metadata(
      crypto,
      settings.principal,
      settings.connection,
      selected.submission,
      selected.request,
      @env.now().to_double(),
    ) {
    Ok(value) => value
    Err(Journal(AuthorizationDenied)) =>
      stop("LocalCheckpointReadAuthorizationDenied")
    Err(_) => stop("LocalOriginalCheckpointUnavailable")
  }
  let fields : Map[String, Json] = Map([
    ("ref", selected.reference),
    (
      "submissionRef",
      @json.parse(
        @local_host.native_client_submission_reference_wire(selected.submission),
      ) catch {
        _ => stop("LocalOriginalCheckpointUnavailable")
      },
    ),
  ])
  match original {
    None => fields["checkpoint"] = Json::null()
    Some(value) => {
      if @local_host.native_client_original_checkpoint_run_cid(value) !=
        selected.run_definition_cid {
        stop("LocalOriginalRunReferenceMismatch")
      }
      fields["checkpoint"] = Json::object(
        Map([
          (
            "checkpointCid",
            Json::string(
              @local_host.native_client_original_checkpoint_cid(value),
            ),
          ),
          (
            "controlRevision",
            Json::string(
              @local_host.native_client_original_checkpoint_revision(value).to_string(),
            ),
          ),
          (
            "cancellationRequested",
            Json::boolean(
              @local_host.native_client_original_checkpoint_cancellation_requested(
                value,
              ),
            ),
          ),
          (
            "state",
            @json.parse(
              @local_host.native_client_original_checkpoint_state(value).wire,
            ) catch {
              _ => stop("LocalOriginalCheckpointUnavailable")
            },
          ),
        ]),
      )
    }
  }
  let reply = encode_request_json(Json::object(fields), 65536)
  if !current() {
    stop("LocalCheckpointReadAuthorizationDenied")
  }
  reply
}
