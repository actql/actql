///|
/// Only this connector's successful measurement can create this proof. Once
/// sealed, it owns its result independently of upstream availability.
priv struct NumericCompletion {
  rows : @execution.AdmittedOutputRows
  mut live : Bool
}

///|
struct CompletedNumericOutput {
  proof : NumericCompletion
  output : @execution.CompletedOutput
}

///|
/// Trusted connector completion, not DAG publication: the common driver still
/// requires its reservation and atomic holding attachment before task success.
/// No caller-supplied verifier or replacement rows are accepted here.
pub fn complete_numeric_output(
  generated : @execution.GeneratedSequence,
  measured : MeasuredNumericOutput,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[CompletedNumericOutput, PlanIssue] {
  if measured.completed || !@execution.producer_read_available(measured.input) {
    return Err(Unsupported)
  }
  let port = match
    @execution.prepare_trusted_output_port(
      generated,
      Step(1),
      max_entries,
      max_name_bytes,
      fn(proof : NumericCompletion) {
        if proof.live {
          Some(proof.rows)
        } else {
          None
        }
      },
      inputs=[measured.input],
    ) {
    Ok(port) => port
    Err(issue) => return Err(Completion(issue))
  }
  let proof = { rows: measured.rows, live: true, }
  match @execution.complete_trusted_output(port, proof) {
    Ok(output) => {
      measured.completed = true
      Ok({ proof, output, })
    }
    Err(issue) => {
      proof.live = false
      Err(Completion(issue))
    }
  }
}

///|
pub fn numeric_completed_output(
  completed : CompletedNumericOutput,
) -> @execution.CompletedOutput {
  completed.output
}

///|
pub fn close_numeric_output(completed : CompletedNumericOutput) -> Unit {
  completed.proof.live = false
}
