///|
/// DATA from the actual retained prefix, not another provider/capacity quote.
pub fn prepared_installed_managed_keyed_prefix_requirements(
  selected : ClientInstalledManagedKeyedPreparation,
) -> Result[Array[Int64], ClientInstalledManagedRunIssue] {
  guard selected.prefix is Some(prefix) else { return Err(Unsupported) }
  Ok([
    0L,
    1L,
    0L,
    0L,
    @execution.execution_capacity_retained_bytes(prefix.capacity),
    @execution.execution_capacity_execution_bytes(prefix.capacity),
  ])
}

///|
/// Reserve on this SAME adopted Run before input binding or provider entry.
/// The existing serialization_prefix slot retains the exact child through a
/// failed current callback, input constructor, provider start or lost return.
/// Source/lookup/Store cleanup duties remain separate original obligations.
pub fn start_installed_managed_keyed_serialization_prefix(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  selected : ClientInstalledManagedKeyedPreparation,
  source : @query.CapturedInputSource,
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[ClientSerializationPrefix, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.content is KeyedContent(plan, _) &&
    physical_equal(plan, selected) &&
    physical_equal(selected.prepared, prepared) &&
    selected.prefix is Some(original_prefix) &&
    physical_equal(
      @publication_host.client_keyed_lookup_acquisition(lookup),
      selected.keyed,
    ) &&
    @publication_host.client_query_requirement_matches_program(
      prepared,
      selected.direct_stage,
      selected.direct_input,
      selected.direct.requirement,
    ) else {
    return Err(ForeignOriginal)
  }
  if owner.source_free_opening || owner.serialization_prefix is Some(_) {
    return Err(AlreadyBound)
  }
  owner.source_free_opening = true
  preparation_module_call(
    () => {
      guard owner.ledger is Some(ledger) &&
        owner.preparation
        is Some(PreparationContentManaged(admission, original)) &&
        physical_equal(original, prepared) else {
        return Err(Retired)
      }
      let preparation = PreparationContentManaged(admission, original)
      let reservation = match
        @resources.reserve_prepared_run_attempt(
          admission,
          prepared,
          ledger,
          0L,
          @execution.execution_capacity_retained_bytes(original_prefix.capacity),
          @execution.execution_capacity_execution_bytes(
            original_prefix.capacity,
          ),
        ) {
        Err(@resources.Resource(issue)) =>
          return Err(SerializationPrefix(Physical(issue)))
        Err(issue) => return Err(Resource(issue))
        Ok(value) => value
      }
      let prefix = serialization_prefix_reservation(ledger, reservation)
      owner.serialization_prefix = Some(prefix)
      let provider_entered = Ref(false)
      preparation_module_call(
        () => {
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          guard owner.content is KeyedContent(current, _) &&
            physical_equal(current, selected) &&
            selected.prefix is Some(current_prefix) &&
            physical_equal(current_prefix, original_prefix) else {
            return Err(ForeignOriginal)
          }
          // Borrow the Query retained at construction, never reissue it from
          // Program text or a same-CID acquisition after physical capture.
          let query = @query.query_sequence_requirement(
            @planning.query_material_owner(
              @planning.query_requirement_material(selected.direct.requirement),
            ),
          )
          let inputs = match
            prepare_acquired_serialization_prefix_inputs(
              prepared,
              selected.serialization_task,
              source,
              original_prefix.sequence,
              query,
              original_prefix.execution,
              original_prefix.measurement,
              ledger,
              Some(lookup),
            ) {
            Err(issue) => return Err(SerializationPrefix(issue))
            Ok(value) => value
          }
          // Input liveness can reenter. This callback-free fence precedes the
          // sole original provider constructor; no extra current probe occurs.
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => return Err(issue)
            Ok(_) => ()
          }
          guard owner.content is KeyedContent(current, _) &&
            physical_equal(current, selected) else {
            return Err(ForeignOriginal)
          }
          provider_entered.val = true
          match
            start_retained_serialization_prefix_provider(
              prefix,
              original_prefix.sequence,
              original_prefix.provider,
              inputs,
              original_prefix.execution,
              original_prefix.measurement,
            ) {
            Err(issue) => return Err(SerializationPrefix(issue))
            Ok(_) => ()
          }
          match
            check_installed_managed_run_original(owner, ledger, preparation) {
            Err(issue) => Err(issue)
            Ok(_) => Ok(prefix)
          }
        },
        () => {
          // These closed input constructors create no physical provider child.
          // A foreign throw after actual provider entry instead keeps the same
          // unknown child/slot pending; None alone never proves cleanup.
          if !provider_entered.val {
            prefix.child_cleaned = true
            ignore(cleanup_client_serialization_prefix(prefix))
          }
        },
      )
    },
    () => owner.source_free_opening = false,
  )
}

///|
/// Retrieve only this original retained child, even after start lost its return.
/// No new read/provider is issued, and no Source or Store ACK is manufactured.
pub fn cleanup_installed_managed_keyed_serialization_prefix(
  owner : ClientInstalledManagedRun,
  selected : ClientInstalledManagedKeyedPreparation,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.content is KeyedContent(plan, _) &&
    physical_equal(plan, selected) &&
    selected.prefix is Some(_) else {
    return Err(ForeignOriginal)
  }
  if owner.source_free_opening {
    return Ok(false)
  }
  match owner.serialization_prefix {
    None => Ok(true)
    Some(prefix) => {
      ignore(cancel_client_serialization_prefix(prefix))
      cleanup_client_serialization_prefix(prefix).map_err(issue => {
        SerializationPrefix(issue)
      })
    }
  }
}
