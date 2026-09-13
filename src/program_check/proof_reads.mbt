///|
/// Candidate proofs remain conditional on their original admitted application.
/// Reading a canonical claim does not discharge any dependency or preflight.
pub fn publication_proof_count(value : PublicationExecution) -> Int {
  value.proofs.length()
}

///|
pub fn publication_proof_at(
  value : PublicationExecution,
  index : Int,
) -> ReidentifiedStep? {
  value.proofs.get(index)
}

///|
pub fn proof_claim(value : ReidentifiedStep) -> @wire.ProgramProofClaim {
  value.proof
}

///|
pub fn proof_application(value : ReidentifiedStep) -> @step_bounds.StepBound {
  value.original
}

///|
pub fn proof_source(value : ReidentifiedStep) -> UnitOperationSource {
  value.location
}

///|
/// Step dependencies and Graph-input dependencies have separate indexed views.
/// Their interleaving is retained by the original application's input sequence.
pub fn proof_input_count(value : ReidentifiedStep) -> Int {
  value.inputs.length()
}

///|
pub fn proof_input_at(
  value : ReidentifiedStep,
  index : Int,
) -> ReidentifiedStep? {
  value.inputs.get(index)
}

///|
pub fn proof_graph_input_count(value : ReidentifiedStep) -> Int {
  value.graph_inputs.length()
}

///|
pub fn proof_graph_input_at(
  value : ReidentifiedStep,
  index : Int,
) -> ReidentifiedGraphInput? {
  value.graph_inputs.get(index)
}

///|
/// Persistent external source occurrences retained by the checked application.
/// These are dependencies, not new Host authorization or runtime evidence.
pub fn proof_external_input_count(value : ReidentifiedStep) -> Int {
  value.external_inputs.length()
}

///|
pub fn proof_external_input_at(
  value : ReidentifiedStep,
  index : Int,
) -> @wire.WireWitness? {
  value.external_inputs.get(index)
}

///|
pub fn graph_proof_application(
  value : ReidentifiedGraphInput,
) -> @graph_input.InputBound {
  value.original
}

///|
pub fn graph_proof_witness(value : ReidentifiedGraphInput) -> @wire.WireWitness {
  value.witness
}

///|
pub fn graph_proof_limit(value : ReidentifiedGraphInput) -> @wire.LimitClaim {
  value.limit
}
