///|
/// The receiving binding is kept by the original Read owner. Only the
/// installed Model's issue-side control can prepare its outcome port once.
struct InferOutcomeBinding {
  rows : PreparedInferRows
}

///|
struct InferOutcomeIssuer {
  binding : InferOutcomeBinding
  mut issued : Bool
}

///|
pub fn prepare_infer_outcome_handoff(
  rows : PreparedInferRows,
) -> (InferOutcomeBinding, InferOutcomeIssuer) {
  let binding : InferOutcomeBinding = { rows, }
  (binding, { binding, issued: false, })
}

///|
/// This port can only be produced by the INFER-specific owner. A conventional
/// trusted Relation port or a completed output at the same Step cannot enter.
struct InferOutcomePort {
  original : TrustedOutputPort[InferOutcomeBinding?]
  output_origin : OutputWorkspaceOriginal?
}

///|
fn prepare_infer_outcome_port_original(
  completion : CompletionPreparation,
  rows : PreparedInferRows,
  materialization : AdmittedOutputPreparation,
  live : () -> Bool,
  binding : InferOutcomeBinding?,
) -> Result[InferOutcomePort, TrustedOutputIssue] {
  if !infer_completion_matches_rows(completion, rows) {
    return Err(ForeignOutput)
  }
  let target = @pipeline.Step(completion_preparation_terminal_step(completion))
  prepare_trusted_output_port(completion, target, 256, 65536, proof => {
    let same_binding = match (binding, proof) {
      (Some(original), Some(selected)) => physical_equal(original, selected)
      (None, None) => true
      _ => false
    }
    if same_binding && live() {
      admitted_output_preparation_rows(materialization)
    } else {
      None
    }
  }).map(original => {
    output_origin: if binding is Some(_) {
      materialization.state.workspace.growth.bind(growth => growth.output_origin)
    } else {
      None
    },
    original,
  })
}

///|
pub fn prepare_infer_outcome_port(
  completion : CompletionPreparation,
  rows : PreparedInferRows,
  materialization : AdmittedOutputPreparation,
  live : () -> Bool,
) -> Result[InferOutcomePort, TrustedOutputIssue] {
  prepare_infer_outcome_port_original(
    completion,
    rows,
    materialization,
    live,
    None,
  )
}

///|
/// The original Model chooses its accepted materialization at preparation.
/// Even the same issuer cannot replace it with a second same-Port output.
pub fn prepare_bound_infer_outcome_port(
  issuer : InferOutcomeIssuer,
  completion : CompletionPreparation,
  rows : PreparedInferRows,
  materialization : AdmittedOutputPreparation,
  live : () -> Bool,
) -> Result[InferOutcomePort, TrustedOutputIssue] {
  if issuer.issued || !physical_equal(issuer.binding.rows, rows) {
    return Err(ForeignOutput)
  }
  prepare_infer_outcome_port_original(
    completion,
    rows,
    materialization,
    live,
    Some(issuer.binding),
  ).map(port => {
    issuer.issued = true
    port
  })
}

///|
pub fn complete_infer_outcome_port(
  value : InferOutcomePort,
) -> Result[CompletedOutput, TrustedOutputIssue] {
  complete_trusted_output(value.original, None)
}

///|
/// Complete only under the receiving binding from this original handoff.
pub fn complete_bound_infer_outcome_port(
  value : InferOutcomePort,
  binding : InferOutcomeBinding,
) -> Result[CompletedOutput, TrustedOutputIssue] {
  complete_trusted_output(value.original, Some(binding))
}

///|
/// Observe the exact metered attachment used by the original bound port.
pub fn infer_outcome_workspace_original(
  value : InferOutcomePort,
) -> OutputWorkspaceOriginal? {
  value.output_origin
}
