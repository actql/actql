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
priv struct LocalOriginalRunSelection {
  request : @run_host.ClientRequestIdentity
  submission : @local_host.NativeClientSubmissionReference
  reference : Json
  namespace_id : String
  run_definition_cid : String
}

///|
// Resolve an authenticated original Submission and exact public Run reference.
// The operation's current authority callback supplies its own permission.
fn local_original_run_selection(
  host : @local_host.NativeLocalHostConnection,
  input_root : String,
  child : @argparse.Matches,
  scope : String,
  current : () -> Bool,
  capture? : @local_host.NativeLocalJournalCapture? = None,
  selected_settings? : LocalHostSettings? = None,
) -> LocalOriginalRunSelection raise ClientStop {
  if !current() {
    stop("LocalOriginalRunAuthorizationDenied")
  }
  let submission = @local_host.admit_native_client_submission_reference(
    text_file(input_root, required(child, "submission-ref-file"), 4096L),
  ).unwrap_or_else(() => stop("InvalidSubmissionRef"))
  let (request, run) = match capture {
    Some(original) => {
      let selected_settings = selected_settings.unwrap_or_else(() => {
        stop("LocalOriginalRunUnavailable")
      })
      let (admission, run) = local_host_result(
        original.lookup_submitted_run_for_cancellation_in_original_read(
          selected_settings.principal,
          selected_settings.connection,
          scope,
          submission,
          @env.now().to_double(),
        ),
      )
      (@local_host.native_client_submitted_run_request(admission), run)
    }
    None => {
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
      (request, run)
    }
  }
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
  {
    request,
    submission,
    reference,
    namespace_id: json_text(original, "namespaceId").unwrap(),
    run_definition_cid: json_text(original, "runDefinitionCid").unwrap(),
  }
}

///|
priv struct LocalCancellationSelection {
  request : @run_host.ClientRequestIdentity
  reference : Json
  cancel_ref : Json
  scope : String
  namespace_id : String
  cancel_id : String
  revision : Int
}

///|
// This is Host glue around the original admission and cancellation Owner.
// A selection is neither a new execution nor an authorization capability.
fn local_cancellation_selection(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> LocalCancellationSelection raise ClientStop {
  let scope = local_host_result(
    match capture {
      None =>
        host.authority_scope_cid(
          settings.principal,
          settings.connection,
          crypto,
        )
      Some(original) =>
        original.authority_scope_cid_in_original_read(
          settings.principal,
          settings.connection,
        )
    },
  )
  let current = () => {
    local_run_operation_allowed(
      host,
      settings,
      crypto,
      scope,
      "cancel",
      capture~,
    )
  }
  if !current() {
    stop("LocalCancellationAuthorizationDenied")
  }
  let selected = local_original_run_selection(
    host,
    input_root,
    child,
    scope,
    current,
    capture~,
    selected_settings=Some(settings),
  )
  guard selected.reference is Object(original) else {
    stop("LocalOriginalRunUnavailable")
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
  {
    request: selected.request,
    reference: selected.reference,
    cancel_ref,
    scope,
    namespace_id: selected.namespace_id,
    cancel_id,
    revision,
  }
}

///|
fn local_cancellation_record_fields(
  selection : LocalCancellationSelection,
  kind : String,
  observed : @local_host.NativeClientCancellationRecord?,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([
    ("kind", Json::string(kind)),
    ("ref", selection.reference),
    ("cancelRef", selection.cancel_ref),
  ])
  match observed {
    None => fields["history"] = Json::string("unresolved")
    Some(record) => {
      fields["history"] = Json::string("retained")
      fields["action"] = Json::string(
        match @local_host.native_client_cancellation_action(record) {
          AcceptCancellation => "accepted"
          AlreadyRequested => "already_requested"
          AlreadyTerminal => "already_terminal"
        },
      )
      // The immutable original observation is not a newly sampled Run control
      // revision or an atomic multi-Owner snapshot.
      fields["recordedControlRevision"] = Json::string(
        @local_host.native_client_cancellation_revision(record).to_string(),
      )
    }
  }
  fields
}

///|
// Lookup observes only original operation custody. It never opens the Store,
// sends cancellation, refreshes the control revision or replays any Provider.
fn local_cancellation_lookup(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  input_root : String,
  child : @argparse.Matches,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> String raise ClientStop {
  let selected = local_cancellation_selection(
    host,
    settings,
    crypto,
    input_root,
    child,
    capture~,
  )
  let current = () => {
    local_run_operation_allowed(
      host,
      settings,
      crypto,
      selected.scope,
      "cancel",
      capture~,
    )
  }
  let result = match capture {
    Some(original) =>
      match
        original.lookup_cancellation_in_original_read(
          settings.principal,
          settings.connection,
          selected.scope,
          selected.request,
          selected.namespace_id,
          selected.cancel_id,
          selected.revision,
        ) {
        Ok(value) => Ok(value)
        Err(@local_host.Journal(issue)) => Err(issue)
        Err(_) => stop("LocalCancellationLookupUnavailable")
      }
    None => {
      let journal = local_host_result(host.run_journal())
      journal.lookup_cancellation(
        selected.request,
        selected.namespace_id,
        selected.cancel_id,
        selected.revision,
        current,
      )
    }
  }
  let observed = match result {
    Ok(UnresolvedCancellationHistory) => None
    Ok(OriginalCancellation(value)) => Some(value)
    Err(CancellationOperation(_)) => stop("LocalCancellationIntentConflict")
    Err(AuthorizationDenied) => stop("LocalCancellationAuthorizationDenied")
    _ => stop("LocalCancellationLookupUnavailable")
  }
  if capture is None && !current() {
    stop("LocalCancellationAuthorizationDenied")
  }
  encode_request_json(
    Json::object(
      local_cancellation_record_fields(
        selected, "local_cancellation_lookup", observed,
      ),
    ),
    4096,
  )
}

///|
fn local_cancellation_unknown(reference : String) -> String {
  "LocalCancellationUnknown cancel-ref=" +
  reference +
  " lookup=lookup-cancellation"
}

///|
// Open only the original retained Store. Missing formats, database originals,
// changed generations or differing installed bindings cannot initialize state.
fn local_cancellation_operation(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  sqlite : @local_sqlite.Library,
  input_root : String,
  child : @argparse.Matches,
  recovery_reference : Ref[String?],
  capture? : @local_host.NativeLocalJournalCapture? = None,
  prepared? : (LocalCommandPreparationOriginal, LocalCommandConfiguration)? = None,
) -> String raise ClientStop {
  let selected = local_cancellation_selection(
    host,
    settings,
    crypto,
    input_root,
    child,
    capture~,
  )
  let invocation = Json::object(
    Map([
      ("operation", Json::string("cancel")),
      ("attemptId", Json::string(required(child, "operation-attempt-id"))),
    ]),
  )
  if !wire_operation_attempt_ref_shape(invocation) {
    stop("InvalidOperationAttemptReference")
  }
  let current = () => {
    local_run_operation_allowed(
      host,
      settings,
      crypto,
      selected.scope,
      "cancel",
      capture~,
    )
  }
  if !current() {
    stop("LocalCancellationAuthorizationDenied")
  }
  let store = match (capture, prepared) {
    (Some(original), Some((owner, configuration))) => {
      guard owner.journal is Some(actual) &&
        physical_equal(actual, original) &&
        original.original_host() is Some(actual_host) &&
        physical_equal(actual_host, host) &&
        owner.runtime is Some(runtime) else {
        stop("LocalRunObservationOriginalUnavailable")
      }
      let run_file = settings.run_file.unwrap_or_else(() => {
        stop("LocalRunInstallationRequired")
      })
      local_host_result(
        original.bind_packaged_runtime_in_original_read(
          runtime,
          settings.principal,
          settings.connection,
          configuration.environment_name,
          run_file,
          "runtime.json",
        ),
      )
      |> ignore
      let run = configuration.run_installation(
        run_file,
        local_host_result(
          original.selected_configuration_in_original_read(run_file),
        ),
      )
      if run.namespace_id != selected.namespace_id {
        stop("LocalOriginalRunReferenceMismatch")
      }
      let managed = local_host_result(
        original.managed_root_path_in_original_read(),
      ).unwrap_or_else(() => stop("LocalManagedRootRequired"))
      owner.open_run_observation_store(sqlite, managed, run)
    }
    (None, None) =>
      local_original_result_store(host, settings, sqlite, selected.namespace_id)
    _ => stop("LocalRunObservationOriginalUnavailable")
  }
  let reply = {
    errdefer (if capture is None && !(store.close() is Ok(true)) {
      stop("LocalCancellationStoreCleanupPending")
    })
    let publication = @local_host.install_native_client_cancellation_publication(
      store,
      selected.namespace_id,
      65536,
      8192,
      64,
    ).unwrap_or_else(() => stop("LocalPublicationBindingUnavailable"))
    // Keep the exact submitted operation key before the transaction. If its
    // outcome or a later close is lost, recovery observes this same key only.
    let reference_wire = encode_request_json(selected.cancel_ref, 4096)
    match (capture, prepared) {
      (Some(original), Some((owner, _))) => {
        if !physical_equal(recovery_reference, owner.cancellation_recovery) {
          stop("LocalRunObservationOriginalUnavailable")
        }
        command_preparation_result(
          owner.retain_cancellation_recovery(original, reference_wire),
        )
      }
      (None, None) => recovery_reference.val = Some(reference_wire)
      _ => stop("LocalRunObservationOriginalUnavailable")
    }
    let result = match capture {
      Some(original) =>
        match
          original.cancel_operation_in_original_read(
            settings.principal,
            settings.connection,
            selected.scope,
            selected.request,
            selected.namespace_id,
            selected.cancel_id,
            selected.revision,
            publication,
          ) {
          Ok(value) => Ok(value)
          Err(@local_host.Journal(issue)) => Err(issue)
          Err(_) => stop("LocalCancellationRecordUnconfirmed")
        }
      None => {
        let journal = local_host_result(host.run_journal())
        journal.cancel_operation(
          selected.request,
          selected.namespace_id,
          selected.cancel_id,
          selected.revision,
          current,
          publication,
        )
      }
    }
    let recorded = match result {
      Ok(value) => value
      Err(CancellationOperation(RevisionConflict)) =>
        stop("LocalCancellationControlRevisionConflict")
      Err(CancellationOperation(ChangedIntent)) | Err(ChangedIntent) =>
        stop("LocalCancellationIntentConflict")
      Err(AuthorizationDenied) => stop("LocalCancellationAuthorizationDenied")
      _ => stop("LocalCancellationRecordUnconfirmed")
    }
    if !current() {
      stop("LocalCancellationAuthorizationDenied")
    }
    let fields = local_cancellation_record_fields(
      selected,
      "local_cancellation_operation",
      Some(recorded),
    )
    // Correlation only: the original-operation record is durable. This field
    // does not claim an independent durable invocation refusal certificate.
    fields["invocationRef"] = invocation
    encode_request_json(Json::object(fields), 4096)
  }
  if capture is None && !(store.close() is Ok(true)) {
    stop("LocalCancellationStoreCleanupPending")
  }
  if !current() {
    stop("LocalCancellationAuthorizationDenied")
  }
  reply
}
