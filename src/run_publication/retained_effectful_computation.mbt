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

///|
/// Same retained final proof, with the actual stored request/attempt/index.
/// This loans existing Core view/current/release machinery, not a state wire,
/// publisher authority or an Effect-free computation. Caller funds the fixed
/// controls and binding-reference snapshot before entry on its original Read.
pub fn prepare_retained_effectful_publication_commit_check(
  original : EffectfulFinalRunEvidence,
  bindings : Array[PublicationContract],
  request : PublicationContract,
  attempt : PublicationContract,
  index : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[PublicationCommitPreparation, EffectfulPublicationCommitIssue] {
  // The existing observed-state protocol projects a successfully completed
  // Run. Rejected/unknown Effect outcomes must keep their original disposition.
  if effect_set_apply_receipt_disposition(original.outcomes) != 0 {
    return Err(
      Index(CommitReferenceMismatch("Effectful outcome is not successful")),
    )
  }
  let need = 13L + bindings.length().to_int64()
  if need >= max_workspace.to_int64() {
    return Err(Index(CommitEncoding))
  }
  match
    validate_retained_effectful_publication_materials(
      original,
      original.run_definition,
      original.invocation,
      original.definitions,
      original.artifacts,
      original._observed_derivations,
      original.orderings,
      original.retentions,
      original.manifest,
      original.final_receipt,
      original.captured_run,
      limits=Some((max_wire_bytes, max_nodes, max_depth)),
    ) {
    Err(issue) => return Err(Index(issue))
    Ok(_) => ()
  }
  let bindings = bindings.copy()

  let value = new_publication_commit_preparation(
    {
      origin: OwnedInputs,
      computation: {
        run_definition: original.run_definition,
        invocation: original.invocation,
        definitions: original.definitions,
        artifacts: original.artifacts,
        manifest: original.manifest,
        receipt: original.final_receipt,
        captured_run: original.captured_run,
        preview: None,
        max_wire_bytes,
        max_nodes,
        max_depth,
      },
      derivations: original._observed_derivations,
      orderings: original.orderings,
      retentions: original.retentions,
      bindings,
      request,
      attempt,
      index_entry: index,
    },
    max_workspace,
  )
  value.retained_effectful = Some(original)
  // All Result, binding and reference work stays in the existing bounded
  // phases. Only the immutable computation fact is retained, not re-executed.
  value.live = need.to_int()
  value.peak = value.live
  Ok(value)
}
