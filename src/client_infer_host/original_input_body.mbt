///|
// Phase demand on the existing input/Read lifetime, not another resource Owner.
struct OriginalInferIdentityBody {
  read : @publication_host.ClientModelReadPreparation
  base_retained : Int64
  base_execution : Int64
  mut retained : Int64
  mut execution : Int64
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
