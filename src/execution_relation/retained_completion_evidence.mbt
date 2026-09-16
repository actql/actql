///|
/// Immutable fact projected from a genuine completed retained output. This
/// object intentionally contains no CompletedStore, output rows, physical-copy
/// callback or logical-use callback. Keeping the fact is not keeping a reader
/// alive, and neither this fact nor its descriptor can construct a completion.
struct RetainedCompletionEvidence {
  result_identity : Ref[Unit]
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  target : @pipeline.Target
  input_bindings : Array[ProducerBindingIdentity]
  receipt : AdmittedOutputStreamReceipt
}

///|
/// Transportable facts only, not a completion/retention/admission grant. An
/// installed Host must separately bind the issuing execution, exact producer,
/// output occurrence and physical holding. Equal descriptors confer no rights.
pub(all) struct RetainedCompletionDescriptor {
  registry_cid : String
  values_contract_cid : String
  rows_cid : String
  output_step : Int
  input_count : Int
  columns : Int
  rows : Int
  bytes : Int
  nodes : Int
  depth : Int
  values : ValueUsage
} derive(Eq, Debug)

///|
pub(all) enum RetainedCompletionEvidenceIssue {
  Unavailable
  NotRetained
  MetadataLimit
  InvalidTarget
} derive(Eq, Debug)

///|
/// Snapshot only while the exact result and retained copy remain available.
/// The bounded input-binding copy contains identity tokens, not producer data.
pub fn retain_completion_evidence(
  output : CompletedOutput,
  max_inputs : Int,
  max_columns : Int,
) -> Result[RetainedCompletionEvidence, RetainedCompletionEvidenceIssue] {
  if max_inputs < 0 || max_columns < 0 {
    return Err(MetadataLimit)
  }
  if !completed_output_available(output) {
    return Err(Unavailable)
  }
  guard output.representation is Some(material) else { return Err(NotRetained) }
  guard output.target is Step(_) else { return Err(InvalidTarget) }
  let completion = output.completion
  if completion.input_bindings.length() > max_inputs ||
    @lower.preparation_input_count(
      @lower.bound_preparation(@lower.sequence_owner(completion.sequence)),
    ) >
    max_inputs ||
    @schema.field_count(material.receipt.schema) > max_columns {
    return Err(MetadataLimit)
  }
  Ok({
    result_identity: completion.result_identity,
    contracts: completion.contracts,
    sequence: completion.sequence,
    target: output.target,
    input_bindings: completion.input_bindings.copy(),
    receipt: material.receipt,
  })
}

///|
pub fn retained_completion_descriptor(
  evidence : RetainedCompletionEvidence,
) -> RetainedCompletionDescriptor {
  let receipt = evidence.receipt
  let output_step = match evidence.target {
    Step(index) => index
    Input(_) => abort("retained completion evidence has a step target")
  }
  {
    registry_cid: evidence.contracts.registry_cid,
    values_contract_cid: evidence.contracts.values_contract_cid,
    rows_cid: receipt.cid,
    output_step,
    input_count: @lower.preparation_input_count(
      @lower.bound_preparation(receipt.owner),
    ),
    columns: @schema.field_count(receipt.schema),
    rows: receipt.rows,
    bytes: receipt.bytes,
    nodes: receipt.nodes,
    depth: receipt.depth,
    values: receipt.usage,
  }
}

///|
/// Exact completed occurrence, not merely equal contents or the same bound
/// producer. A verified representation conversion preserves this relationship.
/// The answer says nothing about whether either copy is currently readable.
pub fn retained_completion_matches_output(
  evidence : RetainedCompletionEvidence,
  output : CompletedOutput,
) -> Bool {
  if !physical_equal(
      evidence.result_identity,
      output.completion.result_identity,
    ) ||
    !physical_equal(evidence.sequence, output.completion.sequence) ||
    evidence.target != output.target ||
    evidence.input_bindings.length() !=
    output.completion.input_bindings.length() {
    return false
  }
  for index, binding in evidence.input_bindings {
    if !physical_equal(binding, output.completion.input_bindings[index]) {
      return false
    }
  }
  true
}

///|
/// For issuing a handoff, the exact completed result must still own the exact
/// admitted retained content and its logical/physical use checks must pass.
/// This is not permission for a new consumer or authority after process loss.
pub fn retained_completion_can_handoff(
  evidence : RetainedCompletionEvidence,
  output : CompletedOutput,
) -> Bool {
  if !retained_completion_matches_output(evidence, output) ||
    !completed_output_available(output) {
    return false
  }
  match output.representation {
    Some(material) => physical_equal(material.receipt, evidence.receipt)
    None => false
  }
}

///|
/// Exact physical material for installed custody wiring. Descriptor equality
/// cannot select this handle, and revoked outputs expose no new handoff.
pub fn retained_completion_material(
  evidence : RetainedCompletionEvidence,
  output : CompletedOutput,
) -> RetainedOutputMaterial? {
  if retained_completion_can_handoff(evidence, output) {
    output.representation
  } else {
    None
  }
}
