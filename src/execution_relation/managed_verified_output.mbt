///|
/// A Host-installed verifier may establish a complete output from bounded
/// aggregate facts without returning every value to common execution code.
/// Its proof type must bind the exact execution, material generation and
/// registered implementation. This port does not confer proof authority.
struct ManagedVerifiedOutputPort[P] {
  stream : ManagedOutputValues
  verify : (P) -> ManagedViewOutputFacts?
  mut open : Bool
  mut verifying : Bool
  mut revoked : Bool
}

///|
pub(all) enum ManagedVerifiedOutputIssue {
  Closed
  Unverified
  InconsistentFacts
  OutputRepresentationRequired
  Values(ManagedOutputValueIssue)
}

///|
/// Install before execution starts. The verifier is Host configuration, never
/// a callback selected by a Program, connector response or remote peer.
pub fn[P] prepare_managed_verified_output_port(
  stream : ManagedOutputValues,
  verify : (P) -> ManagedViewOutputFacts?,
) -> Result[ManagedVerifiedOutputPort[P], ManagedVerifiedOutputIssue] {
  if !stream.open || stream.reading || stream.rows != 0 {
    return Err(Closed)
  }
  if stream.row_measurements is Some(_) {
    return Err(OutputRepresentationRequired)
  }
  stream.reading = true
  Ok({ stream, verify, open: true, verifying: false, revoked: false, })
}

///|
pub fn[P] cancel_managed_verified_output_port(
  port : ManagedVerifiedOutputPort[P],
) -> Bool {
  if port.revoked || (!port.open && !port.verifying) {
    return false
  }
  port.open = false
  port.revoked = true
  cancel_managed_output_values(port.stream) |> ignore
  true
}

///|
/// Consume the one-shot verifier and issue a receipt only after all aggregate
/// admission and measurement constraints have been checked by common code.
pub fn[P] finish_managed_verified_output(
  port : ManagedVerifiedOutputPort[P],
  proof : P,
) -> Result[ManagedOutputValueReceipt, ManagedVerifiedOutputIssue] {
  if !port.open || !port.stream.open {
    return Err(Closed)
  }
  port.open = false
  port.verifying = true
  let facts = (port.verify)(proof)
  port.verifying = false
  if port.revoked || !port.stream.open {
    return Err(Closed)
  }
  guard facts is Some(facts) else {
    cancel_managed_output_values(port.stream) |> ignore
    return Err(Unverified)
  }
  let checked = apply_managed_output_facts(
    port.stream,
    facts,
    (_ : Int, _ : ManagedColumnMeasurement) => true,
    None,
  )
  match checked {
    Err(issue) => {
      cancel_managed_output_values(port.stream) |> ignore
      Err(
        match issue {
          ManagedViewOutputIssue::Closed => Closed
          ManagedViewOutputIssue::Unverified => Unverified
          ManagedViewOutputIssue::InconsistentFacts => InconsistentFacts
          ManagedViewOutputIssue::OutputRepresentationRequired =>
            OutputRepresentationRequired
          ManagedViewOutputIssue::ForeignBinding => Unverified
          ManagedViewOutputIssue::Values(value) => Values(value)
        },
      )
    }
    Ok(_) => {
      port.stream.reading = false
      match finish_managed_output_values(port.stream) {
        Ok(receipt) => Ok(receipt)
        Err(issue) => Err(Values(issue))
      }
    }
  }
}
