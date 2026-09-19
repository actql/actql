///|
/// Host-installed storage verifier, scoped to one exact value-admission stream.
/// This is not execution completion, read authority, or a backend adoption API.
/// The installed verifier is trusted to prove that its payload is the sealed
/// immutable representation of this receipt's values, order and occurrences.
/// Neither arbitrary Program JSON nor a connector-selected verifier may install
/// this port. Its proof type belongs to the adopted Host implementation.
struct ManagedOutputRetentionPort[P, T] {
  core : @managed_carrier.RetentionPort[P, ManagedOutputValueReceipt, T]
}

///|
/// One immutable generation with its independently managed lifetime. Provenance
/// retains the receipt, not the admission buffer, upstream data or verifier.
struct ManagedRetainedOutput[T] {
  receipt : ManagedOutputValueReceipt
  core : @managed_carrier.Retained[ManagedOutputValueReceipt, T]
}

///|
pub(all) enum ManagedOutputRetentionIssue {
  Closed
  Unverified
  ForeignReceipt
  InvalidStorageBytes
  Unavailable
} derive(Eq, Debug)

///|
pub fn[P, T] prepare_managed_output_retention_port(
  stream : ManagedOutputValues,
  verify : (P) -> (ManagedOutputValueReceipt, T, Int64, () -> Bool)?,
) -> Result[ManagedOutputRetentionPort[P, T], ManagedOutputRetentionIssue] {
  // Install before receiving values. Do not authorize a completed receipt by
  // comparing only its owner/target or a content/physical digest afterwards.
  if !stream.open || stream.reading || stream.rows != 0 {
    return Err(Closed)
  }
  Ok({
    core: @managed_carrier.prepare_retention_port(stream.carrier_binding, (
      proof : P,
    ) => {
      match verify(proof) {
        Some((receipt, payload, bytes, available)) =>
          Some((receipt.carrier_receipt, receipt, payload, bytes, available))
        None => None
      }
    }),
  })
}

///|
pub fn[P, T] cancel_managed_output_retention_port(
  port : ManagedOutputRetentionPort[P, T],
) -> Bool {
  @managed_carrier.cancel_retention_port(port.core)
}

///|
/// Consume the issuance opportunity before invoking trusted code. Failure is
/// terminal for this port; it cannot issue another generation on retry. Store
/// cleanup remains its owner's responsibility, including failed verification.
pub fn[P, T] retain_managed_output(
  port : ManagedOutputRetentionPort[P, T],
  proof : P,
) -> Result[ManagedRetainedOutput[T], ManagedOutputRetentionIssue] {
  let core = match @managed_carrier.retain(port.core, proof) {
    Ok(value) => value
    Err(@managed_carrier.Closed) => return Err(Closed)
    Err(@managed_carrier.Unverified) => return Err(Unverified)
    Err(@managed_carrier.ForeignReceipt) => return Err(ForeignReceipt)
    Err(@managed_carrier.InvalidStorageBytes) => return Err(InvalidStorageBytes)
    Err(@managed_carrier.Unavailable) => return Err(Unavailable)
    Err(_) => return Err(Unverified)
  }
  let receipt = @managed_carrier.retained_evidence(core)
  Ok({ receipt, core, })
}

///|
pub fn[T] managed_retained_output_matches(
  material : ManagedRetainedOutput[T],
  receipt : ManagedOutputValueReceipt,
) -> Bool {
  physical_equal(material.receipt, receipt) &&
  @managed_carrier.retained_available(material.core)
}

///|
/// Installed Host lookup only. A returned payload is not a consumer pin or use
/// authorization: the Store must acquire those atomically before dispatch.
pub fn[T] managed_retained_output_payload(
  material : ManagedRetainedOutput[T],
) -> T? {
  @managed_carrier.retained_payload(material.core)
}

///|
pub fn[T] managed_retained_output_storage_bytes(
  material : ManagedRetainedOutput[T],
) -> Int64? {
  @managed_carrier.retained_storage_bytes(material.core)
}
