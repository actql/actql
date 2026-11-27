///|
priv struct PortableModelInvocation {
  capacity : @model.OriginalModelPublicationCapacity
  mut issuer : @infer.ObservationIssuance?
  mut binding : @infer.InvocationBinding?
}

///|
// Count the retained executions without allocating the issuer's input list.
// The source-free observation has a 577-byte canonical empty inventory, including its self CID.
// Each original captured artifact and slot adds at most 74 bytes for its
// canonical CID and punctuation. The enclosing invocation has only two
// CID references and its fixed version and self CID.
fn portable_model_invocation_limits(
  run : StoredPortableModelRun,
) -> @infer.ObservationIssuanceLimits? {
  let mut slots = 0
  for task in run.members {
    guard task.publication_output is Some(_) &&
      task.active is Some(active) &&
      @infer.original_observation_issuance_slot_count(active) is Some(count) &&
      count >= 0 &&
      count <= 2147483645 - slots else {
      return None
    }
    slots += count
  }
  // One checked Whole Source adds its evidence CID, two UTC stamps and the
  // longer consistency literal in the same observation writer.
  let source = if run.sources is Some(_) { 144L } else { 0L }
  let wire = 577L + 74L * (slots.to_int64() + run.members.length().to_int64()) + source
  if wire > 16384L {
    return None
  }
  Some({ max_slots: slots, max_wire_bytes: wire.to_int(), max_work: slots + 2, })
}

///|
// Keep the existing issuer allowance, plus the bounded Local adapter and
// its observation/invocation wrappers. No physical evidence output is staged
// through the Python transfer pool. The issuer owns its two canonical
// values; the Local constructor only borrows them.
fn portable_model_invocation_capacity(
  active : @infer.Execution,
  limits : @infer.ObservationIssuanceLimits,
  members : Int,
) -> Result[@model.OriginalModelPublicationCapacity, @infer.Issue] {
  guard @infer.prepared_observation_issuance_metadata_bytes(
      limits,
      owners=members,
    )
    is Some(metadata) &&
    @execution.preparation_array_representation(1L, members.to_int64(), true)
    is Some(array) &&
    @execution.preparation_representation_cost({
      record_headers: array.record_headers + 28L,
      reference_slots: array.reference_slots + 48L,
      scalar_words: array.scalar_words + 24L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(aliases) else {
    return Err(InvalidAdvance)
  }
  @infer.reserve_original_infer_publication_capacity(
    active,
    metadata + aliases,
    metadata + aliases,
  )
}

///|
fn advance_portable_model_invocation(
  value : Instance,
  record : StoredRunInvocation,
  compute : StoredNativeCompute,
  host : @local_run.LocalComputeHost,
  start : @local_run.LocalComputeStart,
  current : StoredRunConfiguration,
  adopted : @local_host.ClientInstalledManagedRun,
) -> Int {
  guard stored_compute_original_run(value, compute) is Some(original) &&
    compute.current_configuration == Some(original.configuration) &&
    portable_compute_task_current(
      value,
      compute,
      original,
      current,
      original.configuration,
    ) ==
    0 &&
    value.preparations.get(original.preparation)
    is Some({ project_request: Some({ model_run: Some(run), .. }), .. }) &&
    run.adopted is Some(retained_run) &&
    physical_equal(retained_run, adopted) &&
    run.members.get(0) is Some({ active: Some(first), .. }) else {
    return -32
  }
  let dag = @local_run.local_compute_run(host)
  let end = @strategy.graph_task_count(@strategy.captured_dag_graph(dag))
  let begin = @strategy.captured_compute_first_task(dag)
  guard end >= begin && end - begin <= value.workspace_slots else { return -4 }
  for task in begin..<end {
    if !@strategy.captured_task_completed(dag, task) {
      return -33
    }
  }
  record.pending = true
  defer {
    record.pending = false
  }
  let progress = match record.model_issuance {
    Some(original) => original
    None => {
      if record.invoked {
        return -33
      }
      record.invoked = true
      let borrow = match record.borrow {
        Ok(borrow) => borrow
        Err(issue) => return issue_code(issue)
      }
      guard input_cursor(value, borrow.slot) is Some(cursor) &&
        @decode.closed_object(cursor, []) is Ok(_) else {
        return -31
      }
      guard portable_model_invocation_limits(run) is Some(limits) else {
        return -32
      }
      let capacity = match
        portable_model_invocation_capacity(first, limits, run.members.length()) {
        Ok(capacity) => capacity
        Err(
          @infer.Model(
            @model.Ledger(@resources.RetentionLimit | @resources.ExecutionLimit)
          )
        ) => return -4
        Err(_) => return -32
      }
      let original = { capacity, issuer: None, binding: None, }
      record.model_issuance = Some(original)
      let owners = Array(capacity=run.members.length())
      for task in run.members {
        guard task.active is Some(active) else { return -32 }
        owners.push(active)
      }
      match
        @infer.start_complete_original_observation_issuance(
          owners, capacity, limits,
        ) {
        Ok(issuer) => original.issuer = Some(issuer)
        Err(_) => return -32
      }
      original
    }
  }
  guard progress.issuer is Some(issuer) && progress.binding is None else {
    return -33
  }
  match @infer.advance_observation_issuance(issuer, 1) {
    Err(_) => return -32
    Ok((false, _)) => return 1
    Ok((true, _)) => ()
  }
  match
    @infer.bind_issued_invocation(first, run.compiled, run.definition, issuer) {
    Err(_) => return -32
    Ok(binding) => progress.binding = Some(binding)
  }
  let binding = progress.binding.unwrap()
  let issued = match run.sources {
    Some(evidence) =>
      @local_run.issue_local_whole_source_model_invocation(
        host, start, binding, evidence.source, evidence.logical,
        evidence.identity, current.account,
      )
    None =>
      @local_run.issue_local_source_free_model_invocation(
        host, start, binding, current.account,
      )
  }
  match issued {
    Err(_) => -32
    Ok(invocation) => {
      guard !value.closing &&
        !value.runtime_closing &&
        !compute.closing &&
        !record.closing else {
        return -5
      }
      match run_configuration_current(value, current) {
        Err(code) => return code
        Ok(_) => ()
      }
      record.invocation = Some(invocation)
      // Zero bytes denotes a ready nominal invocation at the existing
      // transfer port. The retained binding is the only evidence.
      let output = status(
        @buffers.supply_buffer_output(value.pool, record.slot, b""),
      )
      if output == 0 {
        record.produced = true
      }
      output
    }
  }
}

///|
// Existing task retirement waits for this original issuer and its dependants.
// Failed cleanup retains the exact original borrow for its next close.
fn close_portable_model_invocation(value : PortableModelInvocation) -> Bool {
  if value.binding is Some(binding) {
    if !@infer.release_invocation_binding(binding) {
      return false
    }
    value.binding = None
  }
  if value.issuer is Some(issuer) {
    if @infer.cancel_observation_issuance(issuer) {
      @infer.advance_observation_issuance(issuer, 1) |> ignore
    }
    if !(@infer.cleanup_observation_issuance(issuer) is Ok(true)) {
      return false
    }
    value.issuer = None
  }
  @infer.release_original_infer_publication_capacity(value.capacity) is Ok(true)
}
