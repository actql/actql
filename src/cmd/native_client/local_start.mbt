///|
#borrow(bytes)
extern "C" fn local_utc_now_ffi(bytes : Bytes, length : Int) -> Bool = "actql_native_client_utc_now"

///|
// An empty value on clock failure is refused by the existing timestamp owner.
// It must never be replaced by a caller date or a previously sampled time.
fn local_utc_now() -> String {
  let bytes = Bytes::make(25, 0)
  if local_utc_now_ffi(bytes, bytes.length()) {
    @utf8.decode(bytes[:24].to_owned()) catch {
      _ => ""
    }
  } else {
    ""
  }
}

///|
fn local_submit_allowed(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  scope : String,
) -> Bool {
  local_run_operation_allowed(host, settings, crypto, scope, "submit")
}

///|
fn local_run_operation_allowed(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  scope : String,
  operation : String,
  capture? : @local_host.NativeLocalJournalCapture? = None,
) -> Bool {
  native_timing_count(19)
  if capture is Some(original) {
    return original.authority_scope_cid_in_original_read(
        settings.principal,
        settings.connection,
      )
      is Ok(current) &&
      current == scope &&
      original.authorize_in_original_read({
        principal: settings.principal,
        connection: settings.connection,
        resource: "run",
        operation,
      })
      is Ok(Allow(_))
  }
  host.authority_scope_cid(settings.principal, settings.connection, crypto)
  is Ok(current) &&
  current == scope &&
  host.authorize({
    principal: settings.principal,
    connection: settings.connection,
    resource: "run",
    operation,
  })
  is Ok(Allow(_))
}

///|
// Both literal queries and file-backed text retain the same bounded declaration
// input. Values never infer declarations, defaults or nullability.
fn local_aql_intent_input(
  root : String,
  text : String,
  format : String,
  child : @argparse.Matches,
) -> Json raise ClientStop {
  let input : Map[String, Json] = Map([
    ("text", Json::string(text)),
    ("format", Json::string(format)),
  ])
  if optional(child, "parameter-declarations-file") is Some(file) {
    if format != "aql-text" && format != "sql" {
      stop("external declarations require aql-text or sql")
    }
    input["parameterDeclarations"] = local_input_json_file(root, file, 65536L)
  }
  Json::object(input)
}

///|
fn local_intent_wire(
  root : String,
  operation : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let stop_before = native_requested_stop_before(child)
  let query = local_quick_query_requested(operation, child)
  let input = if query {
    local_aql_intent_input(
      root,
      required(child, "query"),
      if operation == "sql" {
        "sql"
      } else {
        "aql-text"
      },
      child,
    )
  } else if operation == "start" {
    local_input_json_file(root, required(child, "program-file"), 65536L)
  } else {
    let format = required(child, "format")
    guard @frontend.select_format(format) is Ok(_) else {
      stop("UnsupportedLocalSourceFormat")
    }
    local_aql_intent_input(
      root,
      local_input_text_file(root, required(child, "program-file"), 65536L),
      format,
      child,
    )
  }
  let parameters = match optional(child, "parameters-file") {
    Some(file) => local_input_json_file(root, file, 65536L)
    None => Json::null()
  }
  let fields : Map[String, Json] = Map([
    ("kind", Json::string(if operation == "start" { "program" } else { "aql" })),
    ("input", input),
    ("parameters", parameters),
  ])
  if stop_before is Some(boundary) {
    fields["stopBefore"] = Json::string(boundary)
  }
  if query {
    fields["readOnly"] = Json::boolean(true)
  }
  encode_request_json(Json::object(fields), 65536)
}

///|
fn local_publication_field(
  value : @publication.RunEvidenceValue,
  field : String,
) -> String raise ClientStop {
  let root = local_input_cursor(@publication.run_evidence_value_json(value))
  let object = @decode.open_object(root).unwrap_or_else(() => {
    stop("LocalPublicationEvidenceInvalid")
  })
  guard @decode.lookup(object, field) is Some(value) &&
    @decode.text(value) is Ok(text) else {
    stop("LocalPublicationEvidenceInvalid")
  }
  text
}

///|
// Allocate a new opaque generation once, before the existing Store persists
// its payload custody. Replayed submissions never enter this allocation path.
fn local_generation_cid(
  crypto : @local_crypto.Library,
) -> String raise ClientStop {
  native_timing_begin(23)
  defer native_timing_end(23)
  let nonce = crypto
    .random_bytes(32)
    .unwrap_or_else(() => stop("LocalGenerationUnavailable"))
  let digest = crypto
    .sha256_hasher()
    .unwrap_or_else(() => stop("LocalGenerationUnavailable"))
  digest.update(nonce).unwrap_or_else(() => stop("LocalGenerationUnavailable"))
  "sha256:" +
  digest.finish_hex().unwrap_or_else(() => stop("LocalGenerationUnavailable"))
}

///|
fn local_submission_start(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  sqlite : @local_sqlite.Library,
  environment : @checked.CheckEnvironment,
  input_root : String,
  operation : String,
  child : @argparse.Matches,
  public_run? : Bool = false,
  business? : LocalCommandBusinessPreparation? = None,
) -> String raise ClientStop {
  let scope = match business {
    None =>
      local_host_result(
        host.authority_scope_cid(
          settings.principal,
          settings.connection,
          crypto,
        ),
      )
    Some(original) => {
      if !public_run || !original.current(host, settings, environment) {
        stop("LocalBusinessOriginalUnavailable")
      }
      original.scope
    }
  }
  let current = () => {
    match business {
      None => local_submit_allowed(host, settings, crypto, scope)
      Some(original) => original.current(host, settings, environment)
    }
  }
  if !current() {
    stop("LocalSubmissionAuthorizationDenied")
  }
  let selection = local_select_run_submission(
    host,
    settings,
    crypto,
    scope,
    input_root,
    child,
    public_run,
    business~,
  )
  let reference = selection.reference
  let attempt = selection.attempt
  let observe_original = () => {
    let capture = business.map(value => value.capture)
    let reply = if selection.fresh || capture is Some(_) {
      local_submission_lookup_selected(
        host,
        settings,
        crypto,
        () => reference,
        capture~,
      )
    } else {
      local_submission_lookup(host, settings, crypto, input_root, child)
    }
    local_public_run_state_reply(
      host,
      settings,
      crypto,
      reference,
      public_run,
      reply,
      capture~,
    )
  }
  try {
    let intent = match business {
      Some(original) => original.intent
      None =>
        @run_host.prepare_client_submitted_intent(
          local_intent_wire(input_root, operation, child),
          65536,
          8192,
          64,
        ).unwrap_or_else(() => stop("LocalSubmittedInputNotAdmitted"))
    }
    let (journal, epoch) = match business {
      None =>
        (
          local_host_result(host.run_journal()),
          local_host_result(host.epoch_authority()),
        )
      Some(original) =>
        local_host_result(
          original.capture.submission_originals_in_original_read(),
        )
    }
    // Legacy preparation follows its durable intent as before. The selected
    // business route reuses the exact preflight intent/preparation; neither
    // an error nor an unresolved saved Run permits another identity or send.
    let original = match business {
      None =>
        journal
        .record_submitted_intent(
          epoch,
          reference,
          intent,
          scope,
          current(),
          @env.now().to_double(),
        )
        .unwrap_or_else(() => stop("LocalSubmissionAcceptanceUnavailable"))
      Some(selected) => {
        if !current() {
          stop("LocalSubmissionAuthorizationDenied")
        }
        match
          selected.capture.record_submitted_intent_in_original_read(
            settings.principal,
            settings.connection,
            scope,
            reference,
            intent,
            @env.now().to_double(),
          ) {
          Ok(value) => value
          Err(issue) => {
            local_report_submission_failure(issue)
            match issue {
              @local_host.Journal(TransactionUnknown)
              | @local_host.Journal(Epoch(TransactionUnknown))
              | @local_host.InstallationReadTransactionFailure(
                _,
                TransactionUnknown
              ) => stop("LocalSubmissionAcceptanceUnknown")
              _ => stop("LocalSubmissionAcceptanceUnavailable")
            }
          }
        }
      }
    }
    if !current() {
      stop("LocalSubmissionAuthorizationDenied")
    }
    if @local_host.native_client_submitted_preparation_problem(original)
      is Some(_) {
      stop("LocalSubmissionPreparationFailed")
    }
    if @local_host.native_client_submitted_run_admission(original) is Some(_) {
      // Observe the original Run; never recompile its lifetime or reopen Source.
      return observe_original()
    }
    let run_file = settings.run_file.unwrap_or_else(() => {
      stop("LocalRunInstallationRequired")
    })
    let run = match business {
      Some(original) =>
        original.configuration.run_installation(
          run_file,
          local_host_result(
            original.capture.selected_configuration_in_original_read(run_file),
          ),
        )
      None =>
        local_run_installation(
          @utf8.decode(local_host_result(host.selected_configuration(run_file))) catch {
            _ => stop("InvalidLocalRunInstallation")
          },
        )
    }
    let preparation = match business {
      None => local_prepare_submitted_run_program(intent, environment)
      Some(original) => original.preparation
    }
    guard @local_host.native_client_submitted_preparation(preparation)
      is Computation(prepared) else {
      match
        local_effect_prepare_start(
          host, settings, crypto, preparation, reference, run, scope, business~,
        ) {
        AlreadyAccepted => return observe_original()
        AuthoritySupplierUnavailable => ()
      }
      // No accepted Run or physical Source work is created until the selected
      // Local capture/reviewer supplier is connected. Compilation is not approval.
      stop("LocalEffectAuthoritySupplierUnavailable")
    }
    let source_free = @run_host.prepared_client_acquisition_count(prepared) == 0
    if source_free &&
      !@local_host.native_client_local_values_profile_supported(prepared) {
      stop("LocalValuesExecutionProfileNotSupported")
    }
    if !source_free &&
      !@source_owner.resident_source_compute_shape_supported(prepared) {
      stop("LocalSourceExecutionProfileNotSupported")
    }
    let source = if source_free {
      None
    } else {
      let source_file = settings.source_file.unwrap_or_else(() => {
        stop("LocalSourceInstallationRequired")
      })
      let installed = local_source_installation(
        @utf8.decode(
          local_host_result(host.selected_configuration(source_file)),
        ) catch {
          _ => stop("InvalidLocalSourceInstallation")
        },
      )
      Some(installed)
    }
    if source_free && run.source_free is None {
      stop("LocalValuesInstallationRequired")
    }
    let runtime_selection = match business {
      None =>
        host.packaged_runtime_assets_for_submission(
          reference, preparation, 1000,
        )
      Some(original) =>
        local_business_policy_result(
          original,
          original.capture.runtime_submission_assets_in_original_read(
            reference, preparation, 1000,
          ),
        )
    }
    let run = match runtime_selection {
      Ok(Accepted) => return observe_original()
      Ok(Pending(None)) => run
      Ok(Pending(Some((assets, installed_contracts)))) => {
        let installed = run.source_free.unwrap_or_else(() => {
          stop("LocalValuesInstallationRequired")
        })
        {
          ..run,
          source_free: Some(
            local_current_values_installation(
              installed, assets, installed_contracts,
            ),
          ),
        }
      }
      Err(_) => stop("LocalRuntimeSubmissionUnavailable")
    }
    // The current installed profile must genuinely have zero semantic
    // completions. No test-side lowering or fabricated empty journal is used.
    match business {
      None =>
        @run_host.issue_prepared_client_local_normalization(prepared).unwrap_or_else(() => {
            stop("LocalOriginalNormalizationNotInstalled")
          },
        )
        |> ignore
      Some(original) =>
        // Business preparation already admitted normalization on this exact
        // checked owner before acquiring execution or a durable attempt.
        if !(@local_host.native_client_submitted_preparation(original.preparation)
            is Computation(original_prepared) && physical_equal(original_prepared, prepared)) {
          stop("LocalBusinessOriginalUnavailable")
        }
    }
    let request = @run_host.prepare_source_free_client_request_identity(
      prepared,
      scope,
      @local_host.native_client_submission_request_id(reference),
    ).unwrap_or_else(() => stop("LocalRequestIdentityUnavailable"))
    let policy_binding = local_run_policy_binding(
      host,
      settings,
      crypto,
      business~,
    )
    let (run, now) = match policy_binding {
      None => (run, local_utc_now())
      Some(binding) => {
        let prepared_policy = match business {
          None =>
            binding.prepare_submission_policy(
              reference,
              preparation,
              request,
              local_utc_now(),
              @env.now().to_double(),
            )
          Some(original) =>
            local_business_policy_result(
              original,
              original.capture.prepare_run_policy_in_original_read(
                binding,
                reference,
                preparation,
                request,
                local_utc_now(),
                @env.now().to_double(),
              ),
            )
        }
        match prepared_policy {
          Ok(Accepted(_)) => return observe_original()
          Ok(Pending(policy, issued_at)) =>
            ({ ..run, retention: policy, }, issued_at)
          Err(_) => stop("LocalRunPolicyPreparationUnavailable")
        }
      }
    }
    if !@publication.result_retention_intervals_valid(run.retention) ||
      !(@publication.result_retention_interval_state(run.retention, now)
      is Ok("available")) {
      stop("LocalResultRetentionUnavailable")
    }
    let retention = @decode.open_object(
      local_input_cursor(@publication.publication_contract_json(run.retention)),
    ).unwrap_or_else(() => stop("InvalidLocalResultRetentionPolicy"))
    let until = run_text(retention, "available_until")
    let compilation = match business {
      Some(original) => original.request_compilation()
      None => {
        let manifests = @run_host.admit_client_compilation_manifests(
          @compiler_environment.compiler_grammar_manifest_wire(),
          @compiler_environment.compiler_barrier_contract_manifest_wire(),
          10000,
          1000,
          20,
        ).unwrap_or_else(() => stop("LocalCompilerManifestUnavailable"))
        let original = @run_host.issue_prepared_client_task_compilation(
          prepared,
          manifests,
          @run_host.prepared_client_values_sequence_limits(prepared),
          1000,
          1000,
          65536,
          8192,
          64,
        ).unwrap_or_else(() => stop("LocalCompilationNotReady"))
        @run_host.Tasks(original)
      }
    }
    let (compiled, definition) = {
      let configuration_cid = local_host_result(
        match business {
          None => host.configuration()
          Some(original) => original.capture.configuration_in_original_read()
        },
      ).configuration_cid()
      let compiled = match compilation {
        @run_host.Values(original) =>
          @run_host.issue_client_values_compiled_run(
            prepared, original, scope, configuration_cid, until,
          )
        @run_host.Tasks(original) =>
          @run_host.issue_client_task_compiled_run(
            prepared, original, scope, configuration_cid, until,
          )
        @run_host.Effects(_) => stop("LocalBusinessProgramUnavailable")
      }
      let compiled = compiled.unwrap_or_else(() => {
        stop("LocalCompiledRunNotReady")
      })
      let compiled = if source_free {
        let values = run.source_free.unwrap()
        @run_host.with_client_source_free_result_policy(
          compiled,
          values.result_policy_cid,
          values.result_policy_wire,
          65536,
          8192,
          64,
        ).unwrap_or_else(() => stop("LocalValuesResultPolicyNotAdmitted"))
      } else {
        compiled
      }
      let definition = @run_host.issue_client_compiled_run_definition(
        compiled,
        run.namespace_id,
        @local_host.native_client_submission_request_id(reference),
        now,
        until,
      ).unwrap_or_else(() => stop("LocalRunDefinitionNotReady"))
      (compiled, definition)
    }
    if business is Some(original) {
      original.adopt_request_run(request)
    }
    let accepted : Result[
      @local_host.NativeClientSubmittedIntentRecord,
      @local_host.NativeClientRunJournalIssue,
    ] = match policy_binding {
      None =>
        match business {
          None =>
            journal.accept_submitted_run(
              epoch,
              reference,
              preparation,
              request,
              compiled,
              definition,
              scope,
              current(),
              @env.now().to_double(),
            )
          Some(original) =>
            match
              original.capture.accept_submitted_run_in_original_read(
                settings.principal,
                settings.connection,
                scope,
                reference,
                preparation,
                request,
                compiled,
                definition,
                @env.now().to_double(),
              ) {
              Ok(value) => Ok(value)
              Err(@local_host.Journal(issue)) => Err(issue)
              Err(issue) => {
                original.original.retain_primary(CommandAdoption(issue))
                match issue {
                  @local_host.InstallationReadTransactionFailure(
                    _,
                    TransactionUnknown
                  ) => Err(@local_host.TransactionUnknown)
                  _ => stop("LocalRunAdmissionUnavailable")
                }
              }
            }
        }
      Some(binding) =>
        match business {
          None =>
            binding.accept_issued_submitted_run_policy(
              reference,
              preparation,
              request,
              compiled,
              definition,
              run.retention,
              now,
              @env.now().to_double(),
            )
          Some(original) =>
            local_business_policy_result(
              original,
              original.capture.accept_issued_policy_run_in_original_read(
                binding,
                reference,
                preparation,
                request,
                compiled,
                definition,
                run.retention,
                now,
                @env.now().to_double(),
              ),
            )
        }
    }
    match accepted {
      Ok(_) => ()
      // Another accepted observer wins the same request. Its immutable original
      // is the only result to return; this candidate never begins physical work.
      Err(ForeignRun | ChangedIntent) if policy_binding is Some(binding) => {
        let saved_policy = match business {
          None =>
            binding.lookup_submitted_run_policy(
              reference,
              request,
              @env.now().to_double(),
            )
          Some(original) =>
            local_business_policy_result(
              original,
              original.capture.lookup_run_policy_in_original_read(
                binding,
                reference,
                request,
                @env.now().to_double(),
              ),
            )
        }
        saved_policy.unwrap_or_else(() => stop("LocalRunAdmissionUnavailable"))
        |> ignore
        return observe_original()
      }
      Err(_) => stop("LocalRunAdmissionUnavailable")
    }
    if !current() {
      stop("LocalSubmissionAuthorizationDenied")
    }
    if source_free {
      local_retain_values_policy_originals(
        host,
        settings,
        crypto,
        request,
        prepared,
        compiled,
        definition,
        business~,
      )
    }
    if settings.read_file is Some(file) {
      let read = local_read_installation_or_stop(
        @utf8.decode(
          local_host_result(
            match business {
              None => host.selected_configuration(file)
              Some(original) =>
                original.capture.selected_configuration_in_original_read(file)
            },
          ),
        ) catch {
          _ => stop("InvalidLocalReadPolicyOriginal")
        },
      )
      if read.enabled() && !source_free {
        local_retain_values_policy_originals(
          host,
          settings,
          crypto,
          request,
          prepared,
          compiled,
          definition,
          business~,
        )
      }
    }
    let managed_path = match business {
      None => host.managed_root_path()
      Some(original) => original.capture.managed_root_path_in_original_read()
    }
    let managed = local_host_result(managed_path).unwrap_or_else(() => {
      stop("LocalManagedRootRequired")
    })
    let store = match business {
      Some(original) => original.open_store(sqlite, managed, run)
      None => {
        let root = @local_filesystem.open_private_root(managed).unwrap_or_else(() => {
          stop("LocalManagedRootUntrusted")
        })
        if root
          .inspect_directory(run.store_name)
          .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
          is None {
          root
          .create_directory(run.store_name)
          .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
          |> ignore
        }
        root
        .open_child(run.store_name)
        .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
        .private_ownership()
        .unwrap_or_else(() => stop("LocalStoreCustodyUnavailable"))
        |> ignore
        @local_store.open_store(
          sqlite,
          managed + "/" + run.store_name,
          run.store_authority_cid,
          run.store_capacity_bytes,
          run.store_objects,
          run.store_record_bytes,
        ).unwrap_or_else(() => stop("LocalResultStoreUnavailable"))
      }
    }
    let reply = {
      errdefer (if business is None && !(store.close() is Ok(true)) {
        stop("LocalResultStoreCleanupPending")
      })
      let binding = @local_host.install_native_client_cancellation_publication(
        store,
        run.namespace_id,
        65536,
        8192,
        64,
      ).unwrap_or_else(() => stop("LocalPublicationBindingUnavailable"))
      match business {
        None =>
          journal
          .bind_installed_publication(request, binding, current)
          .unwrap_or_else(() => stop("LocalPublicationBindingUnavailable"))
        Some(original) =>
          local_host_result(
            original.capture.bind_installed_publication_in_original_read(
              settings.principal,
              settings.connection,
              request,
              binding,
            ),
          )
      }
      if source_free {
        match business {
          Some(original) =>
            local_execute_original_publish_values(
              original, settings, run, compiled, definition, request, reference,
              attempt, store,
            )
          None =>
            local_execute_publish_values(
              host, settings, run, prepared, compiled, definition, request, reference,
              attempt, crypto, store, current,
            )
        }
      } else {
        let source = source.unwrap()
        guard host.authorize({
            principal: settings.principal,
            connection: settings.connection,
            resource: source.source_ref,
            operation: "read",
          })
          is Ok(Allow(_)) else {
          stop("LocalSourceAuthorizationDenied")
        }
        let library = @duckdb.load_library(source.library_path).unwrap_or_else(() => {
          stop("NativeLocalSourceUnavailable")
        })
        let configuration = (source.configuration)(
          library,
          managed + "/" + source.database_file,
        )
        let work = host
          .open_source_work(
            crypto,
            settings.principal,
            settings.connection,
            request,
            prepared,
            compiled,
            definition,
            configuration,
            attempt,
            local_utc_now,
          )
          .unwrap_or_else(() => stop("LocalOriginalSourceWorkUnavailable"))
        let result = {
          errdefer (if !work.close() { stop("LocalSourceCleanupPending") })
          for
            task in 1..<@strategy.graph_task_count(
              @run_host.prepared_client_graph(prepared),
            ) {
            work
            .execute_task(task)
            .unwrap_or_else(() => stop("LocalSourceComputeUnavailable"))
          }
          local_publish_source(
            work, host, settings, run, configuration, compiled, definition, request,
            reference, attempt, crypto, store,
          )
        }
        if !work.close() {
          stop("LocalSourceCleanupPending")
        }
        result
      }
    }
    if business is None && !(store.close() is Ok(true)) {
      stop("LocalResultStoreCleanupPending")
    }
    match business {
      Some(_) => reply
      None =>
        local_public_run_state_reply(
          host, settings, crypto, reference, public_run, reply,
        )
    }
  } catch {
    ClientStop(message) =>
      stop(local_run_submission_failure(selection, message))
  }
}

///|
fn local_publish_source(
  work : @local_host.NativeClientSourceWork,
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  run : LocalRunInstallation,
  configuration : @source_owner.ResidentSourceComputeConfiguration,
  compiled : @run_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @run_host.ClientRequestIdentity,
  reference : @local_host.NativeClientSubmissionReference,
  attempt : String,
  crypto : @local_crypto.Library,
  store : @local_store.Store,
) -> String raise ClientStop {
  let limits = local_result_output_limits(run, configuration)
  let (_, logical, observation, _) = work
    .publication_invocation(limits, 65536, 8192, 64)
    .unwrap_or_else(() => stop("LocalSourcePublicationEvidenceUnavailable"))
  let policy = local_publication_field(observation, "data_policy_cid")
  let input = local_publication_field(logical, "logical_relation_cid")
  let result : @local_publication.NativeCapturedResultPublicationContext = {
    retention: run.retention,
    computation_contract_cid: @publication.publication_contract_identity(
      @run_host.client_compiled_run_plan(compiled),
    ),
    input_relation_cids: [input],
    scope_cid: @publication.publication_contract_identity(definition),
    effective_data_policy_cid: policy,
    store_authority_cid: run.store_authority_cid,
    material_generation_cid: local_generation_cid(crypto),
    max_payload_bytes: run.result_payload_bytes,
  }
  let authoring = @publication.seal_run_evidence_value(
    "authoring_context",
    encode_request_json(
      Json::object(
        Map([
          ("version", Json::string("actql-authoring-context/0.1")),
          (
            "program_definition_cid",
            Json::string(@run_host.client_request_program_cid(request)),
          ),
          ("annotations", Json::array([])),
        ]),
      ),
      65536,
    ),
    65536,
    8192,
    64,
  ).unwrap_or_else(() => stop("LocalAuthoringEvidenceUnavailable"))
  let publisher = host
    .bind_run_publisher(
      crypto,
      settings.principal,
      settings.connection,
      request,
      definition,
      settings.run_file.unwrap_or_else(() => {
        stop("LocalRunInstallationRequired")
      }),
      store,
    )
    .unwrap_or_else(() => stop("LocalPublisherAuthorityUnavailable"))
  let now = local_utc_now()
  let intent : @local_publication.NativeRunPublicationIntent = {
    namespace_id: run.namespace_id,
    authority_scope_cid: @run_host.client_request_authority_scope_cid(request),
    publication_policy_cid: publisher.publication_policy_cid(),
    publication_target_cid: run.store_authority_cid,
    requested_at: now,
  }
  let occurrence : @local_publication.NativeRunPublicationOccurrence = {
    attempt_id: attempt,
    fence_cid: local_generation_cid(crypto),
    external_idempotency_key: None,
    started_at: now,
    committed_at: now,
  }
  let service = work
    .install_publication_service(
      store,
      run.namespace_id,
      _ => publisher.current(),
      65536,
      8192,
      64,
      request_authorize=Some((context, facts) => {
        publisher.authorize_request(context, facts)
      }),
    )
    .unwrap_or_else(() => stop("LocalPublicationAuthorityUnavailable"))
  let pending = work
    .prepare_local_publication(
      service, result, authoring, intent, occurrence, limits, 65536, 8192, 64,
    )
    .unwrap_or_else(() => stop("LocalResultPublicationNotReady"))
  // A commit error is not proof of no publication. Leave the original private
  // material/attempt with its Store for formal reconciliation, never delete it.
  let published = pending
    .commit()
    .unwrap_or_else(() => stop("LocalPublicationNeedsReconciliation"))
  if !published.committed {
    stop("LocalPublicationNeedsReconciliation")
  }
  local_run_publication_reply(
    definition, request, reference, run, compiled, published,
  )
}

///|
fn local_run_publication_reply(
  definition : @publication.PublicationContract,
  request : @run_host.ClientRequestIdentity,
  reference : @local_host.NativeClientSubmissionReference,
  run : LocalRunInstallation,
  compiled : @run_host.ClientCompiledRun,
  published : @local_publication.NativeRunPublicationResult,
) -> String raise ClientStop {
  let run_ref = local_original_run_reference(
    definition,
    @run_host.client_request_authority_scope_cid(request),
  )
  let submission_ref = @json.parse(
    @local_host.native_client_submission_reference_wire(reference),
  ) catch {
    _ => stop("InvalidSubmissionRef")
  }
  encode_request_json(
    Json::object(
      Map([
        ("kind", Json::string("local_run_published")),
        ("mode", Json::string("local")),
        ("ref", run_ref),
        ("submissionRef", submission_ref),
        ("requestId", Json::string(@run_host.client_request_caller_id(request))),
        (
          "runDefinitionCid",
          Json::string(@publication.publication_contract_identity(definition)),
        ),
        ("namespaceId", Json::string(run.namespace_id)),
        (
          "authorityScopeCid",
          Json::string(@run_host.client_request_authority_scope_cid(request)),
        ),
        ("publicIndexEntryCid", Json::string(published.public_index_entry_cid)),
        (
          "publicationAttemptCid",
          Json::string(published.publication_attempt_cid),
        ),
        (
          "resultNames",
          Json::array(
            @run_host.client_compiled_run_result_names(compiled).map(
              Json::string,
            ),
          ),
        ),
      ]),
    ),
    8192,
  )
}
