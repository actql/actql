///|
// Phase demand on the existing input/Read lifetime, not another resource Owner.
struct OriginalInferIdentityBody {
  read : @publication_host.ClientModelReadPreparation
  base_retained : Int64
  base_execution : Int64
  mut retained : Int64
  mut execution : Int64
  mut snapshot : String?
}

///|
// The additional optional cached-String link belongs to this SAME read. Fund
// its field and Some/return carriers before creating the enlarged body record.
fn prepare_original_infer_identity_body(
  read : @publication_host.ClientModelReadPreparation?,
  consumer : @publication_host.ClientModelReadConsumer,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  retained : Int64,
  execution : Int64,
) -> Result[OriginalInferIdentityBody?, Issue] {
  guard read is Some(read) else { return Ok(None) }
  guard @relation.preparation_representation_cost({
      record_headers: 1L,
      reference_slots: 2L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(link) &&
    @relation.checked_preparation_add_product(retained, link, 1L) is Some(r) &&
    @relation.checked_preparation_add_product(execution, link, 1L) is Some(e) else {
    return Err(InvalidAdvance)
  }
  match
    @publication_host.grow_client_model_read_preparation_consumer_capacity(
      read, consumer, compiled, definition, plan, r, e,
    ) {
    Err(issue) => return Err(OriginalCapacity(@publication_host.Read(issue)))
    Ok(_) => ()
  }
  Ok(
    Some({
      read,
      base_retained: r,
      base_execution: e,
      retained: r,
      execution: e,
      snapshot: None,
    }),
  )
}

///|
// Preserve all already-held input/identity material beside the next fact
// constructor. This is an additive span, never substitution by max(old,new).
fn grow_original_infer_facts_span(
  active : Execution,
  next : @relation.ExecutionCapacity,
) -> Result[Unit, Issue] {
  guard active.identity_body is Some(body) &&
    @relation.execution_capacity(
      body.retained - body.base_retained,
      body.execution - body.base_execution,
    )
    is Some(previous) &&
    @relation.add_execution_capacity(previous, next) is Some(coheld) else {
    return Err(InvalidAdvance)
  }
  grow_original_infer_identity_body_capacity(active, coheld).map(_ => ())
}

///|
// Actual Scope/row inventory is now known but the Read is still Started.
// Its original reservation remains charged after Model handoff and cleanup;
// the enclosing Host settles it only after the continuation's aliases retire.
fn prepare_original_infer_scope_snapshot(
  active : Execution,
) -> Result[Unit, Issue] {
  guard active.identity_body is Some(body) else { return Ok(()) }
  guard body.snapshot is None &&
    active.call_scope is Some(scope) &&
    active.rows is Some(rows) else {
    return Err(InvalidAdvance)
  }
  guard @publication_host.client_infer_scope_snapshot_measurement_capacity()
    is Some(start) else {
    return Err(InvalidAdvance)
  }
  match grow_original_infer_facts_span(active, start) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @publication_host.client_infer_scope_snapshot_construction_capacity(
      scope,
      @relation.prepared_infer_rows_count(rows),
    )
    is Some(next) else {
    return Err(InvalidAdvance)
  }
  match grow_original_infer_facts_span(active, next) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let snapshot = match
    @publication_host.client_infer_call_scope_snapshot(scope) {
    Err(issue) => return Err(CallScope(issue))
    Ok(value) => value
  }
  // Keep completed construction charged even when a real current callback
  // stopped this execution. No Model/start/handoff may follow that change.
  body.snapshot = Some(snapshot)
  if active.cancelled ||
    active.reclaimed ||
    !(active.identity_body is Some(same) && physical_equal(same, body)) ||
    !@publication_host.client_infer_call_scope_matches_rows(
      scope,
      rows,
      active.fixed_request_cid,
    ) {
    return Err(InvalidAdvance)
  }
  Ok(())
}

///|
// Called inside the existing latched advance, before the scan constructor.
// Preserve the whole original prefix/input allowance and add its actual next
// optional body demand, without charging the legacy scan a second time. Covered steps neither resize nor call current again.
fn grow_original_infer_identity_body_capacity(
  active : Execution,
  next : @relation.ExecutionCapacity,
) -> Result[@relation.ExecutionCapacity, Issue] {
  guard active.advancing &&
    !active.cancelled &&
    !active.reclaimed &&
    active.identity_body is Some(body) &&
    active.original_preparation is Some(original) &&
    original.read is Claimed(consumer) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    return Err(InvalidAdvance)
  }
  let r = @relation.execution_capacity_retained_bytes(next)
  let e = @relation.execution_capacity_execution_bytes(next)
  if r > 9223372036854775807L - body.base_retained ||
    e > 9223372036854775807L - body.base_execution {
    return Err(InvalidAdvance)
  }
  let retained = Int64::max(body.retained, body.base_retained + r)
  let execution = Int64::max(body.execution, body.base_execution + e)
  if retained > body.retained || execution > body.execution {
    match
      @publication_host.grow_client_model_read_preparation_consumer_capacity(
        body.read,
        consumer,
        bound.compiled,
        bound.definition,
        plan,
        retained,
        execution,
      ) {
      Err(issue) => return Err(OriginalCapacity(@publication_host.Read(issue)))
      Ok(_) => ()
    }
    // Preserve an actual completed grow even if its current callback cancelled
    // the original Execution. No constructor follows that reentrant stop.
    body.retained = retained
    body.execution = execution
    if active.cancelled ||
      active.reclaimed ||
      !(active.identity_body is Some(same) && physical_equal(same, body)) {
      return Err(InvalidAdvance)
    }
  }
  match
    @relation.execution_capacity(
      body.retained - body.base_retained,
      body.execution - body.base_execution,
    ) {
    Some(capacity) => Ok(capacity)
    None => Err(InvalidAdvance)
  }
}
