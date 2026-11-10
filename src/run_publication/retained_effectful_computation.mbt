///|
/// SAME full computation check and its successful Result transfers. This is
/// immutable evidence DATA, never a Request, execution, permission or Store ACK.
struct RetainedEffectfulComputation {
  inputs : ComputationEvidenceInputs
  snapshots : Array[CapturedResultSnapshot?]
}

///|
/// Replace the validation-only call at the original Saved intake boundary.
/// Complete all chain checks before exposing any successful child snapshot.
/// The caller funds and retains this original with its existing captured Read.
pub fn admit_retained_effectful_computation(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  computation_receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[RetainedEffectfulComputation, RunEvidenceChainIssue] {
  let inputs : ComputationEvidenceInputs = {
    run_definition,
    invocation,
    definitions: definitions.copy(),
    artifacts: artifacts.copy(),
    manifest,
    receipt: computation_receipt,
    captured_run,
    preview: Some(preview),
    max_wire_bytes,
    max_nodes,
    max_depth,
  }
  let check = start_computation_evidence_check(
    inputs,
    publication_evidence_workspace(max_nodes),
  )
  match check.retain_result_snapshots() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  while true {
    match check.advance(256) {
      Err(issue) => return Err(issue)
      Ok((false, _)) => ()
      Ok((true, _)) => {
        let snapshots = match check.finish_result_snapshots() {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        return Ok({ inputs, snapshots, })
      }
    }
  } nobreak {
    Err(EvidenceEncoding)
  }
}

///|
pub fn retained_effectful_computation_result_count(
  value : RetainedEffectfulComputation,
) -> Int {
  value.snapshots.length()
}

///|
/// Borrow the original successfully checked snapshot; no parse, execution or
/// field/row array copy is performed. Immutable rows stay with this original.
pub fn retained_effectful_computation_result_at(
  value : RetainedEffectfulComputation,
  index : Int,
) -> CapturedResultSnapshot? {
  match value.snapshots.get(index) {
    Some(value) => value
    None => None
  }
}

///|
fn publication_contract_data_equal(
  a : PublicationContract,
  b : PublicationContract,
) -> Bool {
  a.name == b.name && a.identity == b.identity && a.wire == b.wire
}

///|
fn publication_contract_inventory_equal(
  a : Array[PublicationContract],
  b : Array[PublicationContract],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for index in 0..<a.length() {
    if !publication_contract_data_equal(a[index], b[index]) {
      return false
    }
  }
  true
}

///|
fn retained_effectful_computation_matches(
  value : RetainedEffectfulComputation,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  preview : EffectPreviewIdentity,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  let i = value.inputs
  publication_contract_data_equal(i.run_definition, run_definition) &&
  publication_contract_data_equal(i.invocation, invocation) &&
  publication_contract_inventory_equal(i.definitions, definitions) &&
  publication_contract_inventory_equal(i.artifacts, artifacts) &&
  publication_contract_data_equal(i.manifest, manifest) &&
  publication_contract_data_equal(i.receipt, receipt) &&
  publication_contract_data_equal(i.captured_run, captured_run) &&
  i.preview is Some(original) &&
  original.semantic_cid == preview.semantic_cid &&
  original.run_identity_cid == preview.run_identity_cid &&
  original.authoring_context_cid == preview.authoring_context_cid &&
  i.max_wire_bytes == max_wire_bytes &&
  i.max_nodes == max_nodes &&
  i.max_depth == max_depth
}

///|
/// Callback-free full canonical DATA correspondence for the Native physical
/// publisher. A matching CID is not authority; service/current checks remain.
pub fn validate_retained_effectful_publication_materials(
  value : EffectfulFinalRunEvidence,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  manifest : PublicationContract,
  final_receipt : PublicationContract,
  captured_run : PublicationContract,
  limits? : (Int, Int, Int)? = None,
) -> Result[Unit, PublicationCommitIssue] {
  if limits is Some((bytes, nodes, depth)) {
    for
      contract in [
        run_definition, invocation, manifest, final_receipt, captured_run,
      ] {
      if publication_contract_check_limits(contract, bytes, nodes, depth)
        is Err(_) {
        return Err(CommitEncoding)
      }
    }
    for
      contracts in [definitions, artifacts, derivations, orderings, retentions] {
      for contract in contracts {
        if publication_contract_check_limits(contract, bytes, nodes, depth)
          is Err(_) {
          return Err(CommitEncoding)
        }
      }
    }
  }
  if publication_contract_data_equal(value.run_definition, run_definition) &&
    publication_contract_data_equal(value.invocation, invocation) &&
    publication_contract_inventory_equal(value.definitions, definitions) &&
    publication_contract_inventory_equal(value.artifacts, artifacts) &&
    publication_contract_inventory_equal(
      value._observed_derivations,
      derivations,
    ) &&
    publication_contract_inventory_equal(value.orderings, orderings) &&
    publication_contract_inventory_equal(value.retentions, retentions) &&
    publication_contract_data_equal(value.manifest, manifest) &&
    publication_contract_data_equal(value.final_receipt, final_receipt) &&
    publication_contract_data_equal(value.captured_run, captured_run) {
    Ok(())
  } else {
    Err(CommitReferenceMismatch("retained Effectful materials"))
  }
}
