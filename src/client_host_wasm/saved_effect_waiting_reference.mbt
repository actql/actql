///|
/// Select the waiting state or first committed decision from the same
/// adopted physical row. Other inputs use the saved Submission validator.
fn inspect_saved_effect_checkpoint_candidate(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  current : StoredHostCurrent,
  row : @host.ClientJournalPhysicalRow,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  effect_state : Ref[Bytes?],
) -> Result[@host.ClientRunJournalInspection, Int] {
  let decoded = @host.decode_client_run_journal_row_with_observation_originals(
    row.body,
  )
  guard decoded is Ok((run, policy, observation)) else { return Err(-31) }
  if run.checkpoint is None || run.effect_material_originals is None {
    return validate_sdk_run_row_decoded(decoded).map(original => {
      request: original.request,
      definition: original.definition,
      checkpoint: None,
      cancellation_head: original.cancellation_head,
      task_materials_cid: original.task_materials_cid,
    })
  }
  guard (row.revision == 3L || row.revision == 4L || row.revision >= 9L) &&
    configuration.sdk is Some(sdk) &&
    current.generation is Some((device, inode)) &&
    @host.client_publication_store_binding_body(
      configuration.run_namespace,
      sdk.store_authority_cid,
      device,
      inode,
    )
    is Ok(binding) &&
    run.publication_binding == Some(binding) &&
    record.append_plan is Idle else {
    return Err(-32)
  }
  // The original Run body remains borrowed through its nested join. The
  // returned transport is itself charged by the selected output buffer.
  let initial = 8L * 262144L
  let capacity = match @resources.reserve_capacity(value.root, 0L, initial) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  record.append_plan = Decoding(capacity, Idle)
  let selected = project_original_saved_effect_reference(
    value,
    record,
    configuration,
    row,
    run,
    binding,
    (policy, observation),
    read,
    effect_state,
    initial,
    capacity,
  )
  let closed = close_submission_decode_prefix(value, record)
  match selected {
    Err(issue) => Err(issue)
    Ok(original) => if closed == 0 { Ok(original) } else { Err(closed) }
  }
}

///|
fn project_original_saved_effect_reference(
  value : Instance,
  record : StoredSubmissionProjection,
  configuration : StoredRunConfiguration,
  row : @host.ClientJournalPhysicalRow,
  run : @host.ClientRunJournalEncoding,
  binding : String,
  observations : (String?, String?),
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  effect_state : Ref[Bytes?],
  initial : Int64,
  capacity : @resources.CapacityReservation,
) -> Result[@host.ClientRunJournalInspection, Int] {
  let peak = Ref(initial)
  let fund = (bytes : Int, nodes : Int, _ : Int) => {
    guard @host.client_protocol_metadata_construction_bytes(
        bytes,
        nodes.to_int64(),
      )
      is Some((scratch, _)) &&
      @execution.checked_preparation_add_product(initial, scratch, 1L)
      is Some(next) else {
      return Err(-4)
    }
    if next > peak.val {
      if @resources.grow_capacity_reservation(value.root, capacity, 0L, next)
        is Err(_) {
        return Err(-4)
      }
      peak.val = next
    }
    Ok(())
  }
  let (policy, observation) = observations
  if policy is Some(wire) {
    let bytes = wire.length() * 3
    match fund(bytes, Int::min(8192, bytes), 64) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if @host.validate_client_local_run_policy_original_run(
        @utf8.encode(wire),
        run.request,
        run.definition,
      )
      is Err(_) {
      return Err(-32)
    }
  }
  if observation is Some(wire) {
    let bytes = wire.length() * 3
    match fund(bytes, Int::min(8192, bytes), 64) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if @host.restore_client_run_observation_originals_wire(
        run.definition,
        wire,
        131072,
        8192,
        64,
      )
      is Err(_) {
      return Err(-32)
    }
  }
  if run.publication_policy_originals is Some(wire) {
    let bytes = wire.length() * 3
    match fund(bytes, Int::min(8192, bytes), 64) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    if @host.read_client_run_policy_originals(wire) is Err(_) {
      return Err(-32)
    }
  }
  if row.revision != 3L {
    return @host.observe_client_decided_effect_checkpoint(
      configuration.run_namespace,
      configuration.authority_scope_cid,
      binding,
      row,
      run,
      read,
      -32,
      fund,
      completed=row.revision != 4L,
    ).bind(pair => {
      let (inspection, state) = pair
      if record.kind == 7 {
        guard effect_state.val is None else { return Err(-32) }
        effect_state.val = Some(@utf8.encode(state))
      }
      Ok(inspection)
    })
  }
  @host.read_client_waiting_effect_original(
    configuration.run_namespace,
    configuration.authority_scope_cid,
    @publication.publication_contract_identity(run.definition),
    binding,
    read,
    original => {
      if original.key == row.key &&
        original.revision == row.revision &&
        original.body == row.body {
        Ok(run)
      } else {
        Err(-32)
      }
    },
    -32,
    fund,
  ).bind(original => {
    if record.kind == 7 {
      match fund(65536, 8192, 64) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      guard effect_state.val is None && original.status_wire() is Ok(state) else {
        return Err(-32)
      }
      effect_state.val = Some(@utf8.encode(state))
    }
    Ok(original.inspection())
  })
}
