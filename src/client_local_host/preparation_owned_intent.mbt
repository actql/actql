///|
/// Same funded original snapshot/intent phase, same semantic envelope/CID
/// engine. The fixed manager proves the immutable body belongs to this owner
/// before rendering this wire; caller numeric limits cannot enter this API.
pub fn[I] prepare_closed_values_submitted_intent(
  owner : ClientClosedValuesPreparation[I],
  wire : String,
) -> Result[String, ClientClosedValuesPreparationIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.input is Some(input) else {
    return Err(ForeignOriginal)
  }
  if owner.retiring ||
    owner.work is Some(_) ||
    owner.parsed is Some(_) ||
    owner.document is None ||
    owner.submitted_intent is Some(_) ||
    !owner.text_checked {
    return Err(WrongPhase)
  }
  guard owner.envelope is Some(envelope) &&
    closed_values_intent_source_facts(envelope) is Some(facts) else {
    return Err(Policy)
  }
  if wire.length() > facts.input_bytes {
    return Err(Policy)
  }
  // This receipt bounds the admitted wire extent, not aggregate CPU. Existing
  // source/canonical/writer node and depth budgets separately bound traversal.
  let work = match
    @resources.begin_preparation_phase_work(
      owner.capacity,
      input,
      @resources.IntentIdentity,
      wire.length(),
    ) {
    Ok(work) => work
    Err(issue) => return Err(Work(issue))
  }
  owner.work = Some(work)
  match @resources.spend_preparation_phase_work(work, wire.length()) {
    Ok(_) => ()
    Err(issue) => return Err(Work(issue))
  }
  let intent = @publication_host.prepare_client_submitted_intent(
    wire,
    facts.input_bytes,
    facts.node_upper,
    facts.depth_upper,
  )
  match @resources.finish_preparation_phase_work(work) {
    Ok(_) => owner.work = None
    Err(issue) => return Err(Work(issue))
  }
  match intent {
    Ok(value) => {
      owner.submitted_intent = Some(value)
      Ok(@publication_host.client_submitted_intent_cid(value))
    }
    Err(issue) => Err(Intent(issue))
  }
}

///|
/// Borrowed only by the fixed active submission consumer under its registered
/// Core holder. No per-epoch cache or independently retained alias is authorized.
pub fn[I] closed_values_submitted_intent_original(
  owner : ClientClosedValuesPreparation[I],
) -> @publication_host.ClientSubmittedIntent? {
  if owner.original is Some(original) &&
    physical_equal(original, owner) &&
    !owner.retiring {
    owner.submitted_intent
  } else {
    None
  }
}
