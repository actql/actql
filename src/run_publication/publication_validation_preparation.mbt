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
priv struct PublicationCommitInputs {
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
  BeginResultEvidence
  ResultEvidence(ResultEvidencePreparation)
  Bindings
  Computation(ComputationEvidenceCheck)
  References
  Done
}

///|
/// Complete commit validation, not durability or permission to install an
/// index. Store custody remains with the existing publication commit owner.
struct PublicationCommitPreparation {
  mut inputs : PublicationCommitInputs?
  max_workspace : Int
  mut phase : PublicationCommitPhase
  mut live : Int
  mut peak : Int
  mut closed : Bool
}

///|
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
  {
    inputs: Some({
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
    }),
    max_workspace,
    phase: BeginResultEvidence,
    live: 12,
    peak: 12,
    closed: false,
  }
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
    Bindings =>
      match
        validate_durable_result_bindings(
          chain.run_definition,
          chain.invocation,
          chain.definitions,
          chain.artifacts,
          inputs.orderings,
          inputs.retentions,
          inputs.bindings,
          inputs.index_entry,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) =>
          preparation.phase = Computation(
            start_computation_evidence_check(
              chain,
              preparation.max_workspace - preparation.live,
            ),
          )
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
              Ok(_) => preparation.phase = References
            }
          }
        }
      }
    References =>
      match
        validate_publication_commit_references(
          chain.run_definition,
          chain.invocation,
          chain.definitions,
          chain.manifest,
          chain.receipt,
          chain.captured_run,
          inputs.request,
          inputs.attempt,
          inputs.index_entry,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => preparation.phase = Done
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
        preparation.phase = Bindings
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
  if preparation.closed || quantum < 1 {
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
  if preparation.closed || !(preparation.phase is Done) {
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
    Computation(child) => child.cancel()
    _ => ()
  }
  preparation.inputs = None
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
    ContextHash(_, _) => "context-check"
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
    BeginResultEvidence | ResultEvidence(_) => "result-evidence"
    Bindings => "bindings"
    Computation(child) => computation_evidence_check_fixture_phase(child)
    References => "references"
    Done => "done"
  }
}
