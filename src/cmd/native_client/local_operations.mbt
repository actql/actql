///|
// Resolve only the immutable original admission and retained Run. Both public
// submission lookup and operation lookup use this binding; neither prepares,
// claims physical execution or derives a Run from current installation settings.
fn local_resolve_admitted_run(
  journal : @local_host.NativeClientRunJournal,
  admission : @local_host.NativeClientSubmittedRunAdmission,
  scope : String,
  current : () -> Bool,
) -> (@run_host.ClientRequestIdentity, @local_host.NativeClientRunRecord) raise ClientStop {
  if !current() {
    stop("LocalOriginalRunAuthorizationDenied")
  }
  let request = @local_host.native_client_submitted_run_request(admission)
  if @run_host.client_request_authority_scope_cid(request) != scope {
    stop("LocalOriginalRunScopeMismatch")
  }
  let run = match journal.lookup(request, current()) {
    Ok(Retained(run)) => run
    _ => stop("LocalOriginalRunUnavailable")
  }
  if @publication.publication_contract_identity(
      @local_host.native_client_run_definition(run),
    ) !=
    @local_host.native_client_submitted_run_definition_cid(admission) {
    stop("LocalOriginalRunUnavailable")
  }
  if !current() {
    stop("LocalOriginalRunAuthorizationDenied")
  }
  (request, run)
}

///|
// Read the original cancellation record through the existing journal. An
// unresolved history is not a refusal certificate, stop observation, cleanup
// result or permission to issue another operation. No Store or Provider opens.
fn local_cancellation_lookup(
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
    local_run_operation_allowed(host, settings, crypto, scope, "cancel")
  }
  if !current() {
    stop("LocalCancellationAuthorizationDenied")
  }
  let submission = @local_host.admit_native_client_submission_reference(
    text_file(input_root, required(child, "submission-ref-file"), 4096L),
  ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
  let journal = local_host_result(host.run_journal())
  let epoch = local_host_result(host.epoch_authority())
  let admission = match
    journal.lookup_submitted_intent(
      epoch,
      submission,
      scope,
      current(),
      @env.now().to_double(),
    ) {
    Ok(Submitted(original)) =>
      @local_host.native_client_submitted_run_admission(original).unwrap_or_else(() => {
          stop("LocalOriginalRunUnavailable")
        },
      )
    _ => stop("LocalOriginalRunUnavailable")
  }
  let (request, run) = local_resolve_admitted_run(
    journal, admission, scope, current,
  )
  let reference = local_original_run_reference(
    @local_host.native_client_run_definition(run),
    scope,
  )
  guard reference is Object(original) else {
    stop("LocalOriginalRunUnavailable")
  }
  let supplied = json_file(input_root, required(child, "ref-file"), 4096L)
  guard wire_run_ref_shape(supplied) &&
    supplied is Object(supplied) &&
    same_cancellation_target(supplied, original) else {
    stop("LocalOriginalRunReferenceMismatch")
  }
  let cancel_id = required(child, "cancel-id")
  let revision = cancellation_revision(required(child, "expected-revision"))
  let cancel_fields : Map[String, Json] = Map([])
  for key, value in original {
    cancel_fields[key] = value
  }
  cancel_fields["cancelId"] = Json::string(cancel_id)
  cancel_fields["expectedRevision"] = Json::number(revision.to_double())
  let cancel_ref = Json::object(cancel_fields)
  if !wire_cancellation_ref_shape(cancel_ref) {
    stop("InvalidCancellationRef")
  }
  let observed = match
    journal.lookup_cancellation(
      request,
      json_text(original, "namespaceId").unwrap(),
      cancel_id,
      revision,
      current,
    ) {
    Ok(value) => value
    Err(CancellationOperation(_)) => stop("LocalCancellationIntentConflict")
    Err(AuthorizationDenied) => stop("LocalCancellationAuthorizationDenied")
    _ => stop("LocalCancellationLookupUnavailable")
  }
  if !current() {
    stop("LocalCancellationAuthorizationDenied")
  }
  let fields : Map[String, Json] = Map([
    ("kind", Json::string("local_cancellation_lookup")),
    ("ref", reference),
    ("cancelRef", cancel_ref),
  ])
  match observed {
    UnresolvedCancellationHistory =>
      fields["history"] = Json::string("unresolved")
    OriginalCancellation(record) => {
      fields["history"] = Json::string("retained")
      fields["action"] = Json::string(
        match @local_host.native_client_cancellation_action(record) {
          AcceptCancellation => "accepted"
          AlreadyRequested => "already_requested"
          AlreadyTerminal => "already_terminal"
        },
      )
      // The immutable original observation is not a newly sampled Run control
      // revision and is never combined into an atomic multi-Owner snapshot.
      fields["recordedControlRevision"] = Json::string(
        @local_host.native_client_cancellation_revision(record).to_string(),
      )
    }
  }
  encode_request_json(Json::object(fields), 4096)
}
