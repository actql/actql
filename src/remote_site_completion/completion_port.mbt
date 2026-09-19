///|
/// Host-private material proof paired with the admitted remote evidence. The
/// payload remains opaque to common code. Its installed verifier must bind it
/// to the exact generation, holding evidence and physical manifest supplied by
/// the checked remote subject.
pub(all) struct RemoteManagedCompletionProof[P] {
  output : RemoteManagedOutputProof
  material : P
}

///|
pub(all) enum RemoteManagedCompletionIssue {
  Closed
  ForeignProfile
  UnverifiedMaterial
  Values(@execution.ManagedVerifiedOutputIssue)
  Retention(@execution.ManagedOutputRetentionIssue)
  Completion(@execution.TrustedOutputIssue)
}

///|
/// One pre-execution common completion path. The Host verifier performs only
/// physical-handle binding; remote semantic evidence, aggregate admission,
/// retention and completion are independently enforced by MoonBit.
struct RemoteManagedCompletionPort[P, T] {
  values : @execution.ManagedVerifiedOutputPort[RemoteManagedOutputProof]
  retention : @execution.ManagedOutputRetentionPort[
    (@execution.ManagedOutputValueReceipt, T, Int64, () -> Bool),
    T,
  ]
  completion : @execution.ManagedCompletionPort[
    @execution.ManagedRetainedOutput[T],
    T,
  ]
  verify_material : (P, String, String, String, Int64) -> (T, () -> Bool)?
  receipt : Ref[@execution.ManagedOutputValueReceipt?]
  material : Ref[@execution.ManagedRetainedOutput[T]?]
  mut open : Bool
  mut verifying : Bool
  mut revoked : Bool
}

///|
/// Install every authority before remote execution starts. The execution
/// attempt is the opaque common TaskExecution attempt, not the serializable
/// remote attempt number.
pub fn[P, T] prepare_remote_managed_completion_port(
  stream : @execution.ManagedOutputValues,
  request : @remote.DispatchRequest,
  expectation : RemoteManagedOutputExpectation,
  profile : @execution.ManagedExecutionProfile,
  preparation : @execution.CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify_material : (P, String, String, String, Int64) -> (T, () -> Bool)?,
  inputs? : Array[@execution.ProducerRead],
  managed_inputs? : Array[@execution.ManagedProducerRead[T]],
  obligations? : @execution.ManagedObligations,
  identity_issuer? : @execution.ManagedIdentityIssuer[T],
  attempt? : @execution.ManagedExecutionAttempt,
) -> Result[RemoteManagedCompletionPort[P, T], RemoteManagedCompletionIssue] {
  if @execution.managed_execution_profile_cid(profile) !=
    expectation.managed_profile_cid {
    return Err(ForeignProfile)
  }
  let receipt : Ref[@execution.ManagedOutputValueReceipt?] = Ref(None)
  let material : Ref[@execution.ManagedRetainedOutput[T]?] = Ref(None)
  let retention = match
    @execution.prepare_managed_output_retention_port(stream, proof => {
      let (candidate, payload, retained_bytes, available) = proof
      if receipt.val is Some(expected) &&
        physical_equal(candidate, expected) &&
        available() {
        Some((candidate, payload, retained_bytes, available))
      } else {
        None
      }
    }) {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let values = match
    prepare_remote_managed_output_verifier(stream, request, expectation) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_managed_output_retention_port(retention) |> ignore
      return Err(Values(issue))
    }
  }
  let completion = match
    @execution.prepare_managed_completion_port(
      profile,
      preparation,
      target,
      max_entries,
      max_name_bytes,
      candidate => {
        if material.val is Some(expected) && physical_equal(candidate, expected) {
          Some(expected)
        } else {
          None
        }
      },
      inputs?,
      managed_inputs?,
      obligations?,
      identity_issuer?,
      attempt?,
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_remote_managed_output_verifier(values) |> ignore
      @execution.cancel_managed_output_retention_port(retention) |> ignore
      return Err(Completion(issue))
    }
  }
  Ok({
    values,
    retention,
    completion,
    verify_material,
    receipt,
    material,
    open: true,
    verifying: false,
    revoked: false,
  })
}

///|
pub fn[P, T] cancel_remote_managed_completion_port(
  port : RemoteManagedCompletionPort[P, T],
) -> Bool {
  if port.revoked || (!port.open && !port.verifying) {
    return false
  }
  port.open = false
  port.revoked = true
  cancel_remote_managed_output_verifier(port.values) |> ignore
  @execution.cancel_managed_output_retention_port(port.retention) |> ignore
  @execution.cancel_managed_completion_port(port.completion) |> ignore
  true
}

///|
/// Consume one exact remote proof set and physical handle. A successful return
/// is a common managed completion, but the enclosing task is not committed
/// until physical_strategy accepts its exact attempt and retained allocation.
pub fn[P, T] finish_remote_managed_completion(
  port : RemoteManagedCompletionPort[P, T],
  proof : RemoteManagedCompletionProof[P],
) -> Result[@execution.ManagedCompletedOutput[T], RemoteManagedCompletionIssue] {
  if !port.open {
    return Err(Closed)
  }
  port.open = false
  let receipt = match
    finish_remote_managed_output_verifier(port.values, proof.output) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_managed_output_retention_port(port.retention) |> ignore
      @execution.cancel_managed_completion_port(port.completion) |> ignore
      return Err(Values(issue))
    }
  }
  port.verifying = true
  let (generation, holding, manifest, retained_bytes) = @remote.remote_managed_output_subject_retention(
    proof.output.subject,
  )
  let verified = (port.verify_material)(
    proof.material,
    generation,
    holding,
    manifest,
    retained_bytes,
  )
  port.verifying = false
  if port.revoked {
    return Err(Closed)
  }
  guard verified is Some((payload, available)) else {
    @execution.cancel_managed_output_retention_port(port.retention) |> ignore
    @execution.cancel_managed_completion_port(port.completion) |> ignore
    return Err(UnverifiedMaterial)
  }
  port.receipt.val = Some(receipt)
  let retained = match
    @execution.retain_managed_output(
      port.retention,
      (receipt, payload, retained_bytes, available),
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_managed_completion_port(port.completion) |> ignore
      return Err(Retention(issue))
    }
  }
  port.material.val = Some(retained)
  match @execution.complete_managed_output(port.completion, retained) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Completion(issue))
  }
}
