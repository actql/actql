///|
/// Host-installed storage verifier, scoped to one exact value-admission stream.
/// This is not execution completion, read authority, or a backend adoption API.
/// The installed verifier is trusted to prove that its payload is the sealed
/// immutable representation of this receipt's values, order and occurrences.
/// Neither arbitrary Program JSON nor a connector-selected verifier may install
/// this port. Its proof type belongs to the adopted Host implementation.
struct ManagedOutputRetentionPort[P, T] {
  identity : Ref[Unit]
  verify : (P) -> (ManagedOutputValueReceipt, T, Int64, () -> Bool)?
  mut open : Bool
  mut verifying : Bool
  mut revoked : Bool
}

///|
/// One immutable generation with its independently managed lifetime. Provenance
/// retains the receipt, not the admission buffer, upstream data or verifier.
struct ManagedRetainedOutput[T] {
  receipt : ManagedOutputValueReceipt
  payload : T
  // Accounted physical holding upper bound owned by this generation. This is
  // charged retained capacity, not an observed file length, serialized value
  // size or process RSS measurement.
  storage_bytes : Int64
  available : () -> Bool
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
    identity: stream.identity,
    verify,
    open: true,
    verifying: false,
    revoked: false,
  })
}

///|
pub fn[P, T] cancel_managed_output_retention_port(
  port : ManagedOutputRetentionPort[P, T],
) -> Bool {
  if port.revoked || (!port.open && !port.verifying) {
    return false
  }
  port.open = false
  port.revoked = true
  true
}

///|
/// Consume the issuance opportunity before invoking trusted code. Failure is
/// terminal for this port; it cannot issue another generation on retry. Store
/// cleanup remains its owner's responsibility, including failed verification.
pub fn[P, T] retain_managed_output(
  port : ManagedOutputRetentionPort[P, T],
  proof : P,
) -> Result[ManagedRetainedOutput[T], ManagedOutputRetentionIssue] {
  if !port.open {
    return Err(Closed)
  }
  port.open = false
  port.verifying = true
  let verified = (port.verify)(proof)
  port.verifying = false
  if port.revoked {
    return Err(Closed)
  }
  guard verified is Some((receipt, payload, storage_bytes, available)) else {
    return Err(Unverified)
  }
  if !physical_equal(receipt.identity, port.identity) {
    return Err(ForeignReceipt)
  }
  if storage_bytes < 0L {
    return Err(InvalidStorageBytes)
  }
  port.verifying = true
  let live = available()
  port.verifying = false
  if port.revoked {
    return Err(Closed)
  }
  if !live {
    return Err(Unavailable)
  }
  Ok({ receipt, payload, storage_bytes, available, })
}

///|
pub fn[T] managed_retained_output_matches(
  material : ManagedRetainedOutput[T],
  receipt : ManagedOutputValueReceipt,
) -> Bool {
  physical_equal(material.receipt, receipt) && (material.available)()
}

///|
/// Installed Host lookup only. A returned payload is not a consumer pin or use
/// authorization: the Store must acquire those atomically before dispatch.
pub fn[T] managed_retained_output_payload(
  material : ManagedRetainedOutput[T],
) -> T? {
  if (material.available)() {
    Some(material.payload)
  } else {
    None
  }
}

///|
pub fn[T] managed_retained_output_storage_bytes(
  material : ManagedRetainedOutput[T],
) -> Int64? {
  if (material.available)() {
    Some(material.storage_bytes)
  } else {
    None
  }
}
