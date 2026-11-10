///|
/// Reuse the issuer's exact computation validator for an admitted capture.
/// Inputs are borrowed and must remain unchanged until finish or cancel.
pub fn start_effect_free_run_evidence_check(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> ComputationEvidenceCheck {
  start_computation_evidence_check(
    {
      run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      captured_run,
      preview: None,
      max_wire_bytes,
      max_nodes,
      max_depth,
    },
    max_workspace,
  )
}

///|
/// Borrow completed immutable computation facts only from this same capture.
/// Foreign, restored, changed or unsupported tighter inputs use the full check.
pub fn start_effect_free_run_evidence_check_retained(
  original : CapturedRunIssuancePreparation,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> ComputationEvidenceCheck {
  let preparation = start_effect_free_run_evidence_check(
    run_definition, invocation, definitions, artifacts, manifest, receipt, captured_run,
    max_wire_bytes, max_nodes, max_depth, max_workspace,
  )
  if max_workspace > preparation.live &&
    original.matches_computation(preparation.inputs.unwrap()) {
    preparation.retained_capture = Some(original)
    preparation.live += 1
    preparation.peak = Int::max(preparation.peak, preparation.live)
    preparation.phase = Done
  }
  preparation
}

///|
/// Only the stored loader constructs inventories with no caller-owned mutable
/// array aliases. This describes input ownership, never current Store authority.
priv enum PublicationCommitInputOrigin {
  BorrowedInputs
  OwnedInputs
  StoredInputs
}

///|
priv struct PublicationCommitInputs {
  origin : PublicationCommitInputOrigin
  computation : ComputationEvidenceInputs
  derivations : Array[PublicationContract]
  orderings : Array[PublicationContract]
  retentions : Array[PublicationContract]
  bindings : Array[PublicationContract]
  request : PublicationContract
  attempt : PublicationContract
  index_entry : PublicationContract
}

///|
priv enum PublicationCommitPhase {
  OriginalStored
  BeginResultEvidence
  ResultEvidence(ResultEvidencePreparation)
  BeginBindings
  Bindings(DurableBindingPreparation)
  Computation(ComputationEvidenceCheck)
  BeginReferences
  References(PublicationReferencePreparation)
  Done
}

///|
/// Complete commit validation, not durability or permission to install an
/// index. Store custody remains with the existing publication commit owner.
struct PublicationCommitPreparation {
  mut inputs : PublicationCommitInputs?
  mut retained_capture : CapturedRunIssuancePreparation?
  mut retained_effectful : EffectfulFinalRunEvidence?
  max_workspace : Int
  mut phase : PublicationCommitPhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
  mut view : PublicationCommitReadView?
}

///|
/// Borrow original inputs through finish/cancel, or through release_view when
/// finish_view retains them. The caller must not mutate the borrowed arrays.
pub fn start_effect_free_publication_commit_check(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  bindings : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> PublicationCommitPreparation {
  new_publication_commit_preparation(
    {
      origin: BorrowedInputs,
      computation: {
        run_definition,
        invocation,
        definitions,
        artifacts,
        manifest,
        receipt,
        captured_run,
        preview: None,
        max_wire_bytes,
        max_nodes,
        max_depth,
      },
      derivations,
      orderings,
      retentions,
      bindings,
      request,
      attempt,
      index_entry,
    },
    max_workspace,
  )
}

///|
/// Reuse only the captured computation fact. Result dependencies, bindings and
/// each new request/attempt/Index remain with their original commit validators.
pub fn start_effect_free_publication_commit_check_retained(
  original : CapturedRunIssuancePreparation,
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  derivations : Array[PublicationContract],
  orderings : Array[PublicationContract],
  retentions : Array[PublicationContract],
  bindings : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  request : PublicationContract,
  attempt : PublicationContract,
  index_entry : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> PublicationCommitPreparation {
  let preparation = start_effect_free_publication_commit_check(
    run_definition, invocation, definitions, artifacts, derivations, orderings, retentions,
    bindings, manifest, receipt, captured_run, request, attempt, index_entry, max_wire_bytes,
    max_nodes, max_depth, max_workspace,
  )
  if max_workspace > preparation.live &&
    original.matches_computation(preparation.inputs.unwrap().computation) {
    preparation.retained_capture = Some(original)
    preparation.live += 1
    preparation.peak = Int::max(preparation.peak, preparation.live)
  }
  preparation
}

///|
fn PublicationCommitPreparation::step(
  preparation : PublicationCommitPreparation,
) -> Result[Unit, PublicationCommitIssue] {
  let inputs = preparation.inputs.unwrap()
  let chain = inputs.computation
  if preparation.max_workspace < preparation.live {
    return Err(CommitEncoding)
  }
  match preparation.phase {
    // The parent completed every validator over these private inventories.
    // Consume one bounded step; the original observed-child lifetime remains.
    OriginalStored => preparation.phase = Done
    BeginResultEvidence => {
      let child = start_result_evidence_preparation(
        chain.definitions,
        chain.artifacts,
        inputs.derivations,
        inputs.orderings,
        inputs.retentions,
        Some(preparation.max_workspace - preparation.live),
      )
      preparation.phase = ResultEvidence(child)
      match preparation.advance_result_evidence(child) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    ResultEvidence(child) =>
      match preparation.advance_result_evidence(child) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    BeginBindings => {
      let child = start_durable_binding_preparation(
        {
          run_definition: chain.run_definition,
          invocation: chain.invocation,
          definitions: chain.definitions,
          artifacts: chain.artifacts,
          orderings: inputs.orderings,
          retentions: inputs.retentions,
          bindings: inputs.bindings,
          index_entry: inputs.index_entry,
        },
        Some(preparation.max_workspace - preparation.live),
      )
      preparation.phase = Bindings(child)
      match preparation.advance_bindings(child, chain) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    Bindings(child) =>
      match preparation.advance_bindings(child, chain) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    Computation(child) =>
      match child.advance(1) {
        Err(issue) => return Err(CommitEvidence(issue))
        Ok((done, _)) => {
          preparation.peak = Int::max(
            preparation.peak,
            preparation.live + child.peak,
          )
          if done {
            match child.finish() {
              Err(issue) => return Err(CommitEvidence(issue))
              Ok(_) => preparation.phase = BeginReferences
            }
          }
        }
      }
    BeginReferences => {
      let child = start_publication_reference_preparation(
        {
          run_definition: chain.run_definition,
          invocation: chain.invocation,
          definitions: chain.definitions,
          manifest: chain.manifest,
          receipt: chain.receipt,
          captured_run: chain.captured_run,
          request: inputs.request,
          attempt: inputs.attempt,
          index_entry: inputs.index_entry,
        },
        Some(preparation.max_workspace - preparation.live),
      )
      preparation.phase = References(child)
      match preparation.advance_references(child) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    References(child) =>
      match preparation.advance_references(child) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    Done => ()
  }
  Ok(())
}

///|
fn PublicationCommitPreparation::advance_result_evidence(
  preparation : PublicationCommitPreparation,
  child : ResultEvidencePreparation,
) -> Result[Unit, PublicationCommitIssue] {
  match child.advance(1) {
    Err(issue) => return Err(issue)
    Ok((done, _)) => {
      // A successful budgeted child never exceeds the Int workspace bound.
      preparation.peak = Int::max(
        preparation.peak,
        preparation.live + child.peak.to_int(),
      )
      if done {
        child.cancel()
        preparation.phase = BeginBindings
      }
    }
  }
  Ok(())
}

///|
fn PublicationCommitPreparation::advance_bindings(
  preparation : PublicationCommitPreparation,
  child : DurableBindingPreparation,
  chain : ComputationEvidenceInputs,
) -> Result[Unit, PublicationCommitIssue] {
  match child.advance(1) {
    Err(issue) => return Err(issue)
    Ok((done, _)) => {
      preparation.peak = Int::max(
        preparation.peak,
        preparation.live + child.peak,
      )
      if done {
        child.cancel()
        if preparation.retained_effectful is Some(original) {
          let inputs = preparation.inputs.unwrap()
          match
            validate_retained_effectful_publication_commit(
              original,
              inputs.bindings,
              inputs.request,
              inputs.attempt,
              inputs.index_entry,
            ) {
            Err(_) =>
              return Err(
                CommitReferenceMismatch("retained Effectful observation"),
              )
            Ok(_) => preparation.phase = Done
          }
        } else if preparation.retained_capture is Some(original) &&
          original.matches_computation(chain) {
          preparation.phase = BeginReferences
        } else {
          preparation.phase = Computation(
            start_computation_evidence_check(
              chain,
              preparation.max_workspace - preparation.live,
            ),
          )
        }
      }
    }
  }
  Ok(())
}

///|
fn PublicationCommitPreparation::advance_references(
  preparation : PublicationCommitPreparation,
  child : PublicationReferencePreparation,
) -> Result[Unit, PublicationCommitIssue] {
  match child.advance(1) {
    Err(issue) => return Err(issue)
    Ok((done, _)) => {
      preparation.peak = Int::max(
        preparation.peak,
        preparation.live + child.peak,
      )
      if done {
        child.cancel()
        preparation.phase = Done
      }
    }
  }
  Ok(())
}

///|
pub fn PublicationCommitPreparation::advance(
  preparation : PublicationCommitPreparation,
  quantum : Int,
) -> Result[(Bool, Int), PublicationCommitIssue] {
  if preparation.closed || preparation.view is Some(_) || quantum < 1 {
    return Err(CommitEncoding)
  }
  if preparation.retained_capture is Some(original) && original.closed {
    preparation.cancel()
    return Err(CommitEncoding)
  }
  let mut used = 0
  while used < quantum && !(preparation.phase is Done) {
    match preparation.step() {
      Err(issue) => {
        preparation.cancel()
        return Err(issue)
      }
      Ok(_) => used += 1
    }
  }
  Ok((preparation.phase is Done, used))
}

///|
pub fn PublicationCommitPreparation::finish(
  preparation : PublicationCommitPreparation,
) -> Result[Unit, PublicationCommitIssue] {
  if preparation.closed ||
    preparation.view is Some(_) ||
    !(preparation.phase is Done) ||
    (preparation.retained_capture is Some(original) && original.closed) {
    return Err(CommitEncoding)
  }
  preparation.cancel()
  Ok(())
}

///|
pub fn PublicationCommitPreparation::cancel(
  preparation : PublicationCommitPreparation,
) -> Unit {
  if preparation.closed {
    return
  }
  match preparation.phase {
    ResultEvidence(child) => child.cancel()
    Bindings(child) => child.cancel()
    Computation(child) => child.cancel()
    References(child) => child.cancel()
    _ => ()
  }
  // A completed view still owns the borrowed originals until its physical
  // output use has stopped and the caller explicitly releases that view.
  if preparation.view is Some(view) {
    match view.observed {
      Some(child) => child.cancel()
      None => ()
    }
    preparation.closed = true
    return
  }
  preparation.inputs = None
  preparation.retained_capture = None
  preparation.retained_effectful = None
  preparation.phase = Done
  preparation.live = 0
  preparation.closed = true
}

///|
/// Read-only fixture synchronization, not commit or cancellation authority.
pub fn computation_evidence_check_fixture_phase(
  preparation : ComputationEvidenceCheck,
) -> String {
  if preparation.closed {
    return "closed"
  }
  match preparation.phase {
    PreludeCheck(child) =>
      match child.phase {
        Root(_) => "root-check"
        Check(_, _, _) => "receipt-check"
        _ => "metadata-check"
      }
    ContextHash(_, _) => "context-check"
    InventoryCheck(_) => "capture-inventory"
    ResultLookup(_, _, _, _, _) => "result-lookup"
    SuffixCheck(_) => "suffix-check"
    Fields(_, _, _, _, _) | Rows(_, _) => "rows-check"
    Done => "done"
    _ => "metadata-check"
  }
}

///|
/// Read-only fixture synchronization, not commit or cancellation authority.
pub fn publication_commit_preparation_fixture_phase(
  preparation : PublicationCommitPreparation,
) -> String {
  if preparation.closed {
    return "closed"
  }
  match preparation.phase {
    OriginalStored => "stored-original"
    BeginResultEvidence | ResultEvidence(_) => "result-evidence"
    BeginBindings | Bindings(_) => "bindings"
    Computation(child) => computation_evidence_check_fixture_phase(child)
    References(child) =>
      match child.phase {
        Inventory(_) => "request-inventory"
        Namespace(_) => "namespace-check"
        _ => "references"
      }
    BeginReferences => "references"
    Done => "done"
  }
}

///|
fn new_publication_commit_preparation(
  inputs : PublicationCommitInputs,
  max_workspace : Int,
) -> PublicationCommitPreparation {
  {
    inputs: Some(inputs),
    retained_capture: None,
    retained_effectful: None,
    max_workspace,
    phase: BeginResultEvidence,
    live: 12,
    peak: 12,
    closed: false,
    view: None,
  }
}
