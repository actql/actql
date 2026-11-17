///|
fn original_restored_send_mask_originals(active : Execution) -> Bool {
  guard active.identity_body is Some(_) &&
    active.saved_call_scope is Some(saved) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) &&
    active.original_preparation is Some(original) &&
    original.read is Claimed(_) else {
    return false
  }
  @publication_host.client_infer_saved_call_scope_matches_originals(
    saved,
    bound.compiled,
    bound.definition,
    active.occurrence,
    plan,
  )
}

///|
/// Before the lazy JS boolean map, fund its real restored input count and the
/// two Core copies on the SAME ConsumerStarted Read. Journal current/history
/// authentication retains its existing owner; this count funds no history or
/// permitted maximum attempts. No Model-use/handoff/Ready grow is permitted.
pub fn prepare_original_restored_send_mask(
  active : Execution,
) -> Result[Int, Issue] {
  guard active.durable_calls &&
    !active.reclaimed &&
    !active.cancelled &&
    !active.advancing &&
    execution_input_unadvanced(active) &&
    active.model_send_mask is None &&
    active.identity_body is Some(body) &&
    body.send_mask_funded < 0 else {
    return Err(InvalidAdvance)
  }
  active.advancing = true
  guard @input.client_infer_completed_input(active.input) is Some(input) &&
    original_restored_send_mask_originals(active) &&
    !active.cancelled &&
    !active.reclaimed else {
    active.advancing = false
    return Err(InvalidAdvance)
  }
  let count = @relation.completed_row_count(input)
  guard @relation.preparation_array_representation(
      3L,
      3L * count.to_int64(),
      true,
    )
    is Some(arrays) &&
    @relation.preparation_representation_cost({
      ..arrays,
      record_headers: arrays.record_headers + 12L,
      reference_slots: arrays.reference_slots + 24L,
      scalar_words: arrays.scalar_words + 16L,
    })
    is Some(bytes) &&
    @relation.execution_capacity(bytes, bytes) is Some(next) else {
    active.advancing = false
    return Err(InvalidAdvance)
  }
  let result = grow_original_infer_facts_span(active, next)
  let originals = result is Ok(_) &&
    original_restored_send_mask_originals(active)
  active.advancing = false
  match result {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard originals &&
    !active.cancelled &&
    !active.reclaimed &&
    execution_input_unadvanced(active) else {
    return Err(InvalidAdvance)
  }
  body.send_mask_funded = count
  Ok(count)
}

///|
// Fresh mutable same-Read check immediately before the Core copy. A prior
// count is neither an Allow decision nor a transferable numerical grant.
fn original_restored_send_mask_current(active : Execution, count : Int) -> Bool {
  guard active.identity_body is Some(body) &&
    body.send_mask_funded == count &&
    active.original_preparation is Some(original) &&
    original.read is Claimed(consumer) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    return false
  }
  active.advancing = true
  guard @input.client_infer_completed_input(active.input) is Some(input) &&
    @relation.completed_row_count(input) == count &&
    original_restored_send_mask_originals(active) &&
    !active.cancelled &&
    !active.reclaimed else {
    active.advancing = false
    return false
  }
  let checked = @publication_host.grow_client_model_read_preparation_consumer_capacity(
    body.read,
    consumer,
    bound.compiled,
    bound.definition,
    plan,
    body.retained,
    body.execution,
  )
  let originals = checked is Ok(_) &&
    original_restored_send_mask_originals(active)
  active.advancing = false
  originals &&
  !active.cancelled &&
  !active.reclaimed &&
  execution_input_unadvanced(active)
}
