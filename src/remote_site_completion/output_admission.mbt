///|
/// Checked-task facts fixed before a remote execution starts. The exact
/// material generation and physical manifest do not exist yet and therefore
/// are verified separately when the retained representation is adopted.
pub(all) struct RemoteManagedOutputExpectation {
  managed_profile_cid : String
  result_schema_cid : String
  logical_view_cid : String
  representation_codec_cid : String
}

///|
/// One admitted remote proof set. Construction does not grant proof authority:
/// the installed verifier still checks every exact binding before common value
/// admission can finish.
pub(all) struct RemoteManagedOutputProof {
  evidence : @remote.RemoteExecutionEvidence
  subject : @remote.RemoteManagedOutputSubject
  measurement : @remote.RemoteManagedOutputMeasurement
}

///|
/// Install the common aggregate-value verifier before remote execution. The
/// returned port issues only a value receipt. It does not retain the remote
/// material, establish a logical CID or complete a task.
pub fn prepare_remote_managed_output_verifier(
  stream : @execution.ManagedOutputValues,
  request : @remote.DispatchRequest,
  expectation : RemoteManagedOutputExpectation,
) -> Result[
  @execution.ManagedVerifiedOutputPort[RemoteManagedOutputProof],
  @execution.ManagedVerifiedOutputIssue,
] {
  @execution.prepare_managed_verified_output_port(stream, proof => {
    remote_managed_output_facts(request, expectation, proof)
  })
}

///|
pub fn finish_remote_managed_output_verifier(
  port : @execution.ManagedVerifiedOutputPort[RemoteManagedOutputProof],
  proof : RemoteManagedOutputProof,
) -> Result[
  @execution.ManagedOutputValueReceipt,
  @execution.ManagedVerifiedOutputIssue,
] {
  @execution.finish_managed_verified_output(port, proof)
}

///|
pub fn cancel_remote_managed_output_verifier(
  port : @execution.ManagedVerifiedOutputPort[RemoteManagedOutputProof],
) -> Bool {
  @execution.cancel_managed_verified_output_port(port)
}

///|
fn remote_managed_output_facts(
  request : @remote.DispatchRequest,
  expectation : RemoteManagedOutputExpectation,
  proof : RemoteManagedOutputProof,
) -> @execution.ManagedViewOutputFacts? {
  if !@remote.remote_execution_evidence_matches_dispatch(
      proof.evidence,
      request,
    ) ||
    !@remote.remote_managed_output_subject_matches_evidence(
      proof.subject,
      proof.evidence,
      request,
    ) ||
    !@remote.remote_managed_output_subject_matches_measurement(
      proof.subject,
      proof.measurement,
    ) {
    return None
  }
  let subject = @remote.remote_managed_output_subject_projection(proof.subject)
  if subject.length() != 12 ||
    subject[3] != expectation.managed_profile_cid ||
    subject[4] != expectation.result_schema_cid ||
    subject[5] != expectation.logical_view_cid ||
    subject[6] != expectation.representation_codec_cid {
    return None
  }
  let measured = @remote.remote_managed_output_measurement_projection(
    proof.measurement,
  )
  if measured.length() != 7 || measured[0].length() != 4 {
    return None
  }
  let rows = measured[0][0]
  let width = measured[1].length()
  if measured[2].length() != width ||
    measured[3].length() != width ||
    measured[4].length() != width ||
    measured[5].length() != width ||
    measured[6].length() != width {
    return None
  }
  let columns : Array[@execution.ManagedColumnMeasurement] = []
  for index in 0..<width {
    columns.push({
      rows: measured[1][index],
      bytes: measured[2][index],
      nodes: measured[3][index],
      max_value_bytes: measured[4][index],
      null_rows: measured[5][index],
      admitted_depth: measured[6][index],
    })
  }
  Some({
    rows,
    columns,
    admission_usage: {
      nodes: measured[0][1],
      text_bytes: measured[0][2],
      work: measured[0][3],
    },
  })
}
