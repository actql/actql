///|
pub(all) enum ResidentEffectProducerExecutionIssue {
  Host(ResidentHostIssue)
  Dispatch(ResidentEffectSourceDispatchIssue)
  Compute(ResidentSourceComputeIssue)
  /// The original journal outcome needs its existing observation/recovery
  /// owner; a new Source executor must not replace that responsibility.
  NotStartable(@remote.DispatchRecord)
}

///|
/// A failed close leaves the same Runtime responsible for Source cleanup.
pub(all) struct ResidentEffectProducerExecutionFailure {
  issue : ResidentEffectProducerExecutionIssue
  pending_runtime : @runtime.NativeRemoteRuntime?
  cleanup_issue : @runtime.NativeRemoteRuntimeIssue?
}

///|
/// Runtime owns the producer output and Source lifetime. The original Source
/// Owner can issue private acquired evidence while that lifetime remains open;
/// it must not be independently closed before Runtime's formal release.
pub(all) struct ResidentEffectProducerExecuted {
  executed : ResidentExecuted
  source : ResidentSourceCompute
}

///|
fn effect_producer_failed(
  issue : ResidentEffectProducerExecutionIssue,
  runtime? : @runtime.NativeRemoteRuntime? = None,
) -> Result[
  ResidentEffectProducerExecuted,
  ResidentEffectProducerExecutionFailure,
] {
  let (pending_runtime, cleanup_issue) = match runtime {
    Some(owner) =>
      match owner.close() {
        Ok(_) => (None, None)
        Err(issue) => (Some(owner), Some(issue))
      }
    None => (None, None)
  }
  Err({ issue, pending_runtime, cleanup_issue, })
}

///|
/// Execute the original saved Effect Source dispatch through the existing
/// journal and exclusive start claim. Current delegation is supplied by the
/// trusted Host owner and is checked again at the protected start boundary.
/// Acquisition completion is private input evidence, never Effect approval or
/// a published Named Result. No consumer is executed by this entry point.
pub fn execute_resident_effect_source_attempt(
  journal : @journal.Journal,
  execution : ResidentExecution,
  admission : ResidentRunAdmission,
  effect_limits : @host.ClientEffectComputationLimits,
  configuration : ResidentSourceComputeConfiguration,
  current_delegation : () -> @resident.ResidentSiteDelegation,
  attempt_identity : String,
  claimant : String,
  current_time : () -> String,
  executor_entry : ((String) -> Bool)?,
  source_observe? : (ResidentSourceComputeEvent) -> Bool,
) -> Result[
  ResidentEffectProducerExecuted,
  ResidentEffectProducerExecutionFailure,
] {
  let envelope = match journal.dispatch_envelope(attempt_identity) {
    Ok(Some(value)) => value
    Ok(None) => return effect_producer_failed(Host(EnvelopeMissing))
    Err(issue) => return effect_producer_failed(Host(Journal(issue)))
  }
  guard @remote.admit_remote_poll_dispatch_json(envelope) is Ok(dispatch) &&
    @remote.remote_poll_dispatch_run_materials(dispatch) is Some(wire) else {
    return effect_producer_failed(Host(EnvelopeMissing))
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  if @remote.dispatch_request_attempt_identity(request) != Ok(attempt_identity) {
    return effect_producer_failed(Host(EnvelopeMissing))
  }
  // For an already accepted but expired Run, the ordinary Runtime must claim
  // and settle the refused start. Returning before that boundary would leave
  // an Accepted queue head retryable forever. No physical factory is called.
  let record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return effect_producer_failed(Host(Journal(issue)))
  }
  let (state, _, _, _, _) = @remote.dispatch_record_state(record)
  if state != @remote.Accepted {
    return effect_producer_failed(NotStartable(record))
  }
  let accepted_at = current_time()
  let (materials, bound) = match
    admit_resident_effect_source_dispatch_owned(
      admission,
      effect_limits,
      current_delegation(),
      @site.site_generation(execution.site),
      request,
      wire,
      binding,
      accepted_at,
      configuration.registry_body,
      configuration.values_body,
      configuration.source.fragment_contract_body,
      require_current=false,
    ) {
    Ok(value) => value
    Err(issue) => return effect_producer_failed(Dispatch(issue))
  }
  guard admission.source is Some(expected_source) &&
    expected_source ==
    (configuration.source.source_ref, configuration.source.source_contract_cid) &&
    configuration.source.retained_output_root is Some(root) else {
    return effect_producer_failed(Compute(Source(ForeignInput)))
  }
  let retained : Ref[ResidentSourceCompute?] = Ref(None)
  let failure : Ref[ResidentSourceComputeIssue?] = Ref(None)
  let factory = match
    @output.register_native_remote_standard_dispatch_run_factory(
      request,
      binding,
      () => {
        let started = current_time()
        let source = match
          open_resident_effect_source_compute(
            bound,
            configuration,
            @remote.dispatch_request_identity(request),
            observe=event => {
              match source_observe {
                Some(observer) => observer(event)
                None => true
              }
            },
          ) {
          Ok(value) => value
          Err((issue, cleanup)) => {
            failure.val = Some(issue)
            return Err(cleanup)
          }
        }
        retained.val = Some(source)
        let reject = fn(code : String) {
          @output.prepare_native_remote_standard_input_failure(code, () => {
            source.close()
          }).unwrap()
        }
        guard source.capture is Some(captured) &&
          source.effect_source is Some(original) &&
          @duckdb_host.prepare_native_source_evidence_context(
            original.requirement,
          )
          is Ok(context) &&
          @planning.query_requirement_source_evidence_facts(
            original.requirement,
          )
          is Some(facts) else {
          return Err(reject("effect-source-context"))
        }
        let completed = current_time()
        let limits = execution.limits.output.output_export
        guard @query.identify_captured_source_relation(
            captured,
            limits.max_rows,
            limits.values,
            limits.payload_wire,
            limits.logical_wire,
            limits.schema,
            limits.max_batch_bytes,
          )
          is Ok(identity) &&
          @host.issue_captured_source_input_logical(
            @strategy.captured_dag_graph(source.run),
            captured,
            identity,
            original.requirement,
          )
          is Ok(logical) &&
          @duckdb_host.issue_native_host_source_evidence(
            original.capture,
            context,
            identity,
            logical,
            @remote.dispatch_request_journal_key(request)[0],
            @planning.query_source_evidence_fact_values(facts)[3],
            completed,
          )
          is Ok(evidence) else {
          return Err(reject("effect-source-observation"))
        }
        @output.prepare_native_remote_standard_acquired_task_owner(
          source.run,
          0,
          captured,
          () => source.close(),
          source_observation=Some(dispatch => {
            @remote.prepare_remote_source_observation(
              dispatch, 0, evidence, logical, started, completed,
            )
          }),
          output_storage=Some(() => {
            @retained_file.begin_native_retained_task_file(
              root,
              @remote.dispatch_request_identity(request)[7:].to_owned(),
              execution.limits.output.max_retained_bytes,
            ).map_err(_ => "effect-source-output-storage")
          }),
        ).map_err(_ => reject("effect-source-owner"))
      },
    ) {
    Ok(value) => value
    Err(issue) => return effect_producer_failed(Host(Source(Standard(issue))))
  }
  let executor = match
    @output.install_native_remote_standard_bound_task_executor(
      @remote.dispatch_request_task_scope(request).0,
      @remote.dispatch_request_task_scope(request).1,
      0,
      factory,
      execution.limits.output,
    ) {
    Ok(value) => value
    Err(issue) => return effect_producer_failed(Host(Source(Standard(issue))))
  }
  let runtime = match
    @output.open_native_remote_standard_site_runtime(
      execution.site,
      execution.active_runtime,
      execution.operation_capability_cid,
      execution.issuer_capability_cid,
      [executor],
      journal,
      execution.bundles,
      execution.budgets,
    ) {
    Ok(value) => value
    Err(issue) => return effect_producer_failed(Host(Source(Standard(issue))))
  }
  // Reuse the same Run's original lifetime. The caller cannot refresh it by
  // reconstructing materials or by acquiring a new current delegation.
  match
    runtime.guard_executor_start(() => {
      @resident.check_resident_dispatch_delegation(
        current_delegation(),
        request,
        @site.site_generation(execution.site),
      )
      is Ok(_) &&
      @host.client_effect_run_start_current(
        materials.allowed,
        materials.run_definition,
        accepted_at,
      ) &&
      @host.client_effect_run_start_current(
        materials.allowed,
        materials.run_definition,
        current_time(),
      )
    }) {
    Ok(_) => ()
    Err(issue) =>
      return effect_producer_failed(Host(Runtime(issue)), runtime=Some(runtime))
  }
  match runtime.claim_starts_as(claimant) {
    Ok(_) => ()
    Err(issue) =>
      return effect_producer_failed(Host(Runtime(issue)), runtime=Some(runtime))
  }
  if executor_entry is Some(observer) {
    match runtime.observe_executor_entry(observer) {
      Ok(_) => ()
      Err(issue) =>
        return effect_producer_failed(
          Host(Runtime(issue)),
          runtime=Some(runtime),
        )
    }
  }
  let completion = match runtime.start(request, binding) {
    Ok(value) => value
    Err(issue) =>
      return effect_producer_failed(
        match failure.val {
          Some(primary) => Compute(primary)
          None => Host(Runtime(issue))
        },
        runtime=Some(runtime),
      )
  }
  guard retained.val is Some(source) else {
    return effect_producer_failed(Compute(Unavailable), runtime=Some(runtime))
  }
  Ok({
    executed: { runtime, completion, request, result_definition_cid: None, },
    source,
  })
}
