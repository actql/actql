///|
/// Preparation of the original keyed operation for the existing Local
/// provider. The caller still owns Site selection, capacity reservation,
/// current authority and all borrowed input custody. This is not a Source
/// observation or a completed task and creates no new execution owner.
struct ClientKeyedJoinPreparation {
  lookup : @publication_host.ClientKeyedLookupInput
  sequence : @execution.GeneratedSequence
  provider : @local.ManagedProvider
  capacity : @execution.ExecutionCapacity
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
}

///|
/// Install the original captured task graph in the normal Local Host. Source
/// and keyed holdings stay on the caller's existing Run Ledger. The Host's
/// ordinary task reservation, candidate selection and cleanup remain intact.
pub fn open_client_keyed_local_host(
  prepared : @publication_host.PreparedClientProgram,
  lookup : @publication_host.ClientKeyedLookupInput,
  ledger : @resources.Ledger,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  retained_output? : Bool = false,
  provider_factory? : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ] = _ => [],
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  guard @publication_host.open_client_keyed_lookup_dag(prepared, lookup, ledger)
    is Ok(run) else {
    return None
  }
  let setup = open_checked_local_host(
    prepared,
    None,
    installed_contracts,
    values_body,
    0L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    provider_factory~,
    retained_output~,
    opened_run=Some(run),
  )
  if setup is None {
    reject_client_local_run(run) |> ignore
  }
  setup
}

///|
pub fn prepare_client_keyed_local_join(
  prepared : @publication_host.PreparedClientProgram,
  lookup : @publication_host.ClientKeyedLookupInput,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientKeyedJoinPreparation? {
  prepare_client_keyed_local_join_owned(
    Pure(prepared),
    lookup,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
pub fn prepare_client_effect_keyed_local_join(
  prepared : @publication_host.PreparedClientEffectComputation,
  lookup : @publication_host.ClientKeyedLookupInput,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientKeyedJoinPreparation? {
  prepare_client_keyed_local_join_owned(
    Effect(prepared),
    lookup,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
fn prepare_client_keyed_local_join_owned(
  prepared : ClientLocalSequenceOwner,
  lookup : @publication_host.ClientKeyedLookupInput,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientKeyedJoinPreparation? {
  let acquisition = @publication_host.client_keyed_lookup_acquisition(lookup)
  let matches = match prepared {
    Pure(value) =>
      @publication_host.client_keyed_acquisition_matches_program(
        acquisition, value,
      )
    Effect(value) =>
      @publication_host.client_keyed_acquisition_matches_effect_program(
        acquisition, value,
      )
  }
  guard matches &&
    @publication_host.client_keyed_acquisition_coordinates(acquisition)
    is Some((_, task, step)) &&
    prepare_client_local_sequences_owned(
      prepared,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      selected_task=Some(task),
      // Reuse the existing owned prefix compiler without preparing later
      // consumers as part of this keyed operation's acquisition barrier.
      infer_prefix=Some((task, step)),
    )
    is Some([generated]) &&
    @publication_host.prepare_client_keyed_lookup_join_inputs(lookup, generated)
    is Ok((sequence, _, _)) else {
    return None
  }
  let (_, execution, measurement) = client_local_execution_limits()
  guard @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) &&
    @local.managed_provider_capacity(provider, sequence) is Some(capacity) else {
    return None
  }
  Some({ lookup, sequence, provider, capacity, execution, measurement, })
}

///|
pub fn client_keyed_local_join_capacity(
  prepared : ClientKeyedJoinPreparation,
) -> @execution.ExecutionCapacity {
  prepared.capacity
}

///|
/// The normal dispatch caller reserves the preparation's capacity before this
/// start, retains both acquisition children until provider cleanup, and owns
/// the successful output until its consumers release it. Recheck the original
/// borrowed inputs here; a preparation is not a perpetual liveness grant.
pub fn start_client_keyed_local_join(
  prepared : ClientKeyedJoinPreparation,
  run? : @strategy.CapturedDAG? = None,
) -> Result[@local.ManagedProviderExecution, ClientQueryResidualIssue] {
  let (sequence, left, right) = match
    @publication_host.prepare_client_keyed_lookup_join_inputs(
      prepared.lookup,
      prepared.sequence,
    ) {
    Ok(value) => value
    Err(_) => return Err(InputUnavailable)
  }
  let (left, right) = match run {
    None => (left, right)
    Some(run) => {
      guard @publication_host.client_keyed_lookup_dag_matches(
          prepared.lookup,
          run,
        ) &&
        @publication_host.client_keyed_acquisition_coordinates(
          @publication_host.client_keyed_lookup_acquisition(prepared.lookup),
        )
        is Some((_, task, _)) else {
        return Err(InputUnavailable)
      }
      let left = match @strategy.captured_task_input(run, task, 100, 10000) {
        Ok(value) => value
        Err(_) => return Err(InputUnavailable)
      }
      let right = match
        @strategy.captured_supplied_task_input(run, task, input_index=1) {
        Ok(value) => value
        Err(_) => return Err(InputUnavailable)
      }
      (left, right)
    }
  }
  @local.start_managed_provider_with_inputs_and_execution(
    prepared.provider,
    sequence,
    [
      @local.managed_provider_relation_input(left),
      @local.managed_provider_supplied_relation_input(right),
    ],
    prepared.execution.rows.max_rows,
    prepared.measurement.max_bytes,
    prepared.execution,
  ).map_err(issue => Local(issue))
}
