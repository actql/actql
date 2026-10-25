///|
/// Site-controlled bounds for a single Effect. Selecting this computation
/// family never authorizes the later external write.
fn resident_effect_limits(
  admission : @resident_host.ResidentRunAdmission,
) -> @host.ClientEffectComputationLimits {
  {
    program: admission.limits.preparation,
    max_members: 1,
    max_header_work: 1000,
    mapping: {
      max_bytes: 20000,
      max_nodes: 2000,
      max_depth: 100,
      max_members: 100,
    },
    max_mapping_work: 1000,
    effects: {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  }
}

///|
/// Retain the typed primary failure and its original cleanup Owner across
/// family selection. Diagnostic strings are only projections of this value.
priv enum HolderExecutionIssue {
  Ordinary(@resident_host.ResidentHostIssue)
  Effect(@resident_host.ResidentEffectProducerExecutionIssue)
}

///|
priv enum HolderExecutionFailure {
  Ordinary(@resident_host.ResidentExecutionFailure)
  Effect(@resident_host.ResidentEffectProducerExecutionFailure)
}

///|
fn holder_issue_code(issue : HolderExecutionIssue) -> String {
  match issue {
    Ordinary(value) => host_code(value)
    Effect(Host(value)) => host_code(value)
    Effect(Dispatch(Refused(value))) => "refused-" + refusal_code(value)
    Effect(Dispatch(Materials(_))) => "effect-materials"
    Effect(Dispatch(Dispatch(_))) => "effect-source-dispatch"
    Effect(Dispatch(Source(value))) => source_code(value)
    Effect(Compute(Source(value))) => source_code(value)
    Effect(Compute(value)) =>
      "effect-source-" + source_compute_issue_code(value)
    Effect(NotStartable(_)) => "effect-source-not-startable"
  }
}

///|
// Fixed diagnostic codes preserve the typed primary issue without logging
// provider messages, source paths, credentials or arbitrary nested causes.
fn source_compute_issue_code(
  issue : @resident_host.ResidentSourceComputeIssue,
) -> String {
  match issue {
    UnsupportedGraph => "unsupported-graph"
    Unavailable => "unavailable"
    Source(value) => source_code(value)
    EffectRun(_) => "run-binding"
    EffectInput(_) => "input-binding"
    ForeignEffectMaterials => "foreign-effect-materials"
    Acquisition(_) => "acquisition-open"
    Execution(_) => "acquisition-execution"
    Capture => "capture"
    RetainedInput(_) => "retained-input"
    Run(_) => "run"
    Dispatch(_) => "dispatch"
    Compute(_) => "compute"
    Export(_) => "export"
    Capacity(_) => "capacity"
    ObservationUnrecorded(_) => "observation-unrecorded"
  }
}

///|
fn HolderExecutionFailure::issue(
  self : HolderExecutionFailure,
) -> HolderExecutionIssue {
  match self {
    Ordinary(value) => Ordinary(value.issue)
    Effect(value) => Effect(value.issue)
  }
}

///|
fn HolderExecutionFailure::runtime(
  self : HolderExecutionFailure,
) -> @runtime.NativeRemoteRuntime? {
  match self {
    Ordinary(value) => value.pending_runtime
    Effect(value) => value.pending_runtime
  }
}

///|
/// The saved envelope selects its original family; no semantic rejection is
/// retried under another Owner and no new Run or materials are issued here.
fn saved_dispatch_family(
  journal : @journal.Journal,
  admission : @resident_host.ResidentRunAdmission,
  attempt : String,
) -> Result[@host.ClientRunExecutionFamily, @resident_host.ResidentHostIssue] {
  let body = match journal.dispatch_envelope(attempt) {
    Ok(Some(body)) => body
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(body) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  if @remote.dispatch_request_attempt_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) !=
    Ok(attempt) {
    return Err(EnvelopeMissing)
  }
  @resident_host.resident_dispatch_execution_family(admission, dispatch)
}

///|
fn accept_site_dispatch(
  journal : @journal.Journal,
  client : @http.Client,
  observation_url : String,
  delegation : @resident.ResidentSiteDelegation,
  generation : Int,
  queue : @resident.ResidentAcceptedQueue,
  admission : @resident_host.ResidentRunAdmission,
  configuration : @resident_host.ResidentSourceComputeConfiguration?,
  dispatch : @remote.RemotePollDispatch,
  now : String,
) -> Result[@resident_host.ResidentAcceptance, HolderExecutionIssue] {
  if @remote.remote_poll_dispatch_run_materials(dispatch) is None {
    return Ok(Refused(@resident.MaterialsMissing))
  }
  let family = match
    @resident_host.resident_dispatch_execution_family(admission, dispatch) {
    Ok(value) => value
    Err(Refused(refusal)) => return Ok(Refused(refusal))
    Err(issue) => return Err(Ordinary(issue))
  }
  match family {
    EffectFreeComputation =>
      @resident_host.accept_resident_dispatch(
        journal, client, observation_url, delegation, generation, queue, admission,
        dispatch, now,
      ).map_err(issue => Ordinary(issue))
    EffectComputation => {
      guard configuration is Some(configuration) else {
        return Ok(Refused(@resident.ForeignSource))
      }
      @resident_host.accept_resident_effect_source_dispatch(
        journal,
        client,
        observation_url,
        delegation,
        generation,
        queue,
        admission,
        resident_effect_limits(admission),
        dispatch,
        now,
        configuration.installed_contracts,
        configuration.values_body,
        configuration.source.fragment_contract_body,
      ).map_err(issue => Effect(issue))
    }
  }
}

///|
fn prepare_holder_producer_context(
  journal : @journal.Journal,
  admission : @resident_host.ResidentRunAdmission,
  configuration : @resident_host.ResidentSourceComputeConfiguration?,
  delegation : @resident.ResidentSiteDelegation,
  generation : Int,
  intent : @remote.RemoteRetainedInputIntent,
  at : String,
) -> Result[
  @resident_host.ResidentRetainedProducerContext,
  HolderExecutionIssue,
] {
  let attempt = match
    @remote.dispatch_request_attempt_identity(
      @remote.remote_retained_input_intent_request(intent),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Ordinary(Protocol(issue)))
  }
  let family = match saved_dispatch_family(journal, admission, attempt) {
    Ok(value) => value
    Err(issue) => return Err(Ordinary(issue))
  }
  match family {
    EffectFreeComputation =>
      @resident_host.prepare_resident_retained_producer_context(
        journal, admission, intent, at,
      ).map_err(issue => Ordinary(issue))
    EffectComputation => {
      guard configuration is Some(configuration) else {
        return Err(Ordinary(Refused(@resident.ForeignSource)))
      }
      @resident_host.prepare_resident_effect_retained_producer_context(
        journal,
        admission,
        resident_effect_limits(admission),
        delegation,
        generation,
        intent,
        at,
        configuration.installed_contracts,
        configuration.values_body,
        configuration.source.fragment_contract_body,
      ).map_err(issue => Effect(issue))
    }
  }
}

///|
fn execute_holder_source(
  journal : @journal.Journal,
  execution : @resident_host.ResidentExecution,
  admission : @resident_host.ResidentRunAdmission,
  configuration : @resident_host.ResidentSourceComputeConfiguration?,
  delegation : () -> @resident.ResidentSiteDelegation,
  attempt : String,
  claimant : String,
  clock : () -> String,
  entry : ((String) -> Bool)?,
  observe : (@resident_host.ResidentSourceComputeEvent) -> Bool,
  retain_effect_producer? : (@resident_host.ResidentEffectProducerExecuted) -> Unit,
) -> Result[@resident_host.ResidentExecuted, HolderExecutionFailure] {
  let family = match saved_dispatch_family(journal, admission, attempt) {
    Ok(value) => value
    Err(issue) => return Err(Ordinary({ issue, pending_runtime: None, }))
  }
  match family {
    EffectFreeComputation =>
      @resident_host.execute_resident_attempt(
        journal,
        execution,
        admission,
        attempt,
        claimant,
        clock,
        entry,
        source_observe=observe,
      ).map_err(issue => Ordinary(issue))
    EffectComputation => {
      guard configuration is Some(configuration) else {
        return Err(
          Ordinary({
            issue: Refused(@resident.ForeignSource),
            pending_runtime: None,
          }),
        )
      }
      // Runtime retains the original Source Owner until formal cleanup. The
      // private output is not a published Result or an approved Effect.
      @resident_host.execute_resident_effect_source_attempt(
        journal,
        execution,
        admission,
        resident_effect_limits(admission),
        configuration,
        delegation,
        attempt,
        claimant,
        clock,
        entry,
        source_observe=observe,
        acquisition_limits=resident_effect_acquisition_limits(),
      )
      .map(value => {
        match retain_effect_producer {
          Some(retain) => retain(value)
          None => ()
        }
        value.executed
      })
      .map_err(issue => Effect(issue))
    }
  }
}

///|
/// A finite Site-owned acquisition profile. The same Native receiver enforces
/// these bounds and derives its capacity; no dispatch can enlarge them. The
/// complete capture is capped rather than charged as a streaming receipt.
fn resident_effect_acquisition_limits() -> @acquisition_host.NativeHostLimits {
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  {
    physical: {
      max_rows: 100,
      max_cells: 1000,
      max_nodes: 1000,
      max_text_bytes: 10000,
    },
    metadata_work: 10000,
    measurement,
    completion: {
      demand: measurement,
      receipts: {
        max_columns: 10,
        max_order_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
      max_received_rows: 100,
      max_received_bytes: 100000,
      max_retained_wire_bytes: 100000,
      records: {
        max_work: 1000000,
        max_fields: 100,
        max_parameters: 100,
        max_bytes: 65536,
        max_nodes: 4096,
        max_depth: 100,
      },
      capture: { max_bytes: 65536, max_nodes: 4096, max_depth: 100, },
    },
    retention: {
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
      max_work: 1000000,
    },
    output_rows: 100,
    output_entries: 100,
    output_name_bytes: 10000,
    transport: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_columns: 10,
      max_rows: 100,
      max_text_bytes: 100000,
    },
  }
}
