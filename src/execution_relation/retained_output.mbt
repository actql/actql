///|
/// Immutable admitted content and the current authority for one physical copy.
/// No table/file/session representation is visible to the common engine.
struct RetainedOutputMaterial {
  receipt : AdmittedOutputStreamReceipt
  storage_bytes : Int64
  available : () -> Bool
  mut value_measurement : RetainedValueMeasurement?
}

///|
/// Typed implementation payload, never cast by common execution. Only the exact
/// material installed at completion can recover this handle for a consumer.
struct RetainedOutputHandle[T] {
  material : RetainedOutputMaterial
  payload : T
}

///|
/// Opaque physical-copy lookup for installed Host wiring. A lookup is neither
/// receiving admission nor authority inferred from an equal content identity.
pub fn producer_read_retained_material(
  input : ProducerRead,
) -> RetainedOutputMaterial? {
  if producer_read_available(input) {
    input.bound.output.representation
  } else {
    None
  }
}

///|
/// Trusted Store/Host construction, not a completion constructor. The installed
/// implementation must bind the receipt's exact provisional batches to verified
/// immutable storage and attach its own retention/revocation condition here.
pub fn[T] retain_admitted_output_stream(
  receipt : AdmittedOutputStreamReceipt,
  payload : T,
  available : () -> Bool,
) -> RetainedOutputHandle[T] {
  {
    material: {
      receipt,
      storage_bytes: receipt.bytes.to_int64(),
      available,
      value_measurement: receipt.value_measurement,
    },
    payload,
  }
}

///|
/// Installed Store/Host construction for a verified noncanonical representation.
/// The Store must verify the conversion from the receipt's exact admitted values
/// (including order) and seal immutable storage before constructing this handle.
/// storage_bytes is the physical holding quantity, not the canonical row size.
/// It grants neither completion nor a reservation; the receiving execution must
/// still check it against its previously admitted physical storage allocation.
/// A physical digest must never replace the content receipt's logical CID.
pub fn[T] retain_admitted_output_representation(
  receipt : AdmittedOutputStreamReceipt,
  payload : T,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[RetainedOutputHandle[T], TrustedOutputIssue] {
  if storage_bytes < 0L {
    return Err(InvalidLimits)
  }
  if !available() {
    return Err(NotRetained)
  }
  Ok({
    material: {
      receipt,
      storage_bytes,
      available,
      value_measurement: receipt.value_measurement,
    },
    payload,
  })
}

///|
/// Quantity of this exact live physical copy. Content identity/encoding budgets
/// continue to use its logical receipt; equal CIDs cannot select another copy.
pub fn retained_output_storage_bytes(
  material : RetainedOutputMaterial,
) -> Int64? {
  if (material.available)() {
    Some(material.storage_bytes)
  } else {
    None
  }
}

///|
pub fn[T] retained_output_material(
  handle : RetainedOutputHandle[T],
) -> RetainedOutputMaterial {
  handle.material
}

///|
pub fn retained_output_matches_receipt(
  material : RetainedOutputMaterial,
  receipt : AdmittedOutputStreamReceipt,
) -> Bool {
  physical_equal(material.receipt, receipt) && (material.available)()
}

///|
pub fn[T] retained_producer_payload(
  handle : RetainedOutputHandle[T],
  input : ProducerRead,
) -> T? {
  if !producer_read_available(input) {
    return None
  }
  guard input.bound.output.representation is Some(material) &&
    physical_equal(material, handle.material) &&
    (material.available)() else {
    return None
  }
  Some(handle.payload)
}

///|
/// Exact owned consumer projection into the source representation. Positional
/// metadata only: no cell materialization or permission to substitute a copy.
pub fn[T] retained_producer_columns(
  handle : RetainedOutputHandle[T],
  input : ProducerRead,
  max_entries : Int,
) -> Array[Int]? {
  if max_entries < 0 ||
    input.columns.length() > max_entries ||
    retained_producer_payload(handle, input) is None {
    return None
  }
  Some(input.columns.copy())
}

///|
struct TrustedRetainedOutputPort[P] {
  generated : CompletionPreparation
  target : @pipeline.Target
  inputs : Array[ProducerRead]
  verify : (P) -> RetainedOutputMaterial?
}

///|
/// Installed, proof-typed execution/retention verifier. Value admission alone
/// is insufficient. The implementation must verify exact attempt, obligations,
/// transport, settlement and immutable storage binding before returning material.
/// The public consumer/Program cannot supply or replace this verifier.
pub fn[P] prepare_trusted_retained_output_port(
  generated : CompletionPreparation,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> RetainedOutputMaterial?,
  inputs? : Array[ProducerRead],
) -> Result[TrustedRetainedOutputPort[P], TrustedOutputIssue] {
  // Reuse the same bounded target/retention/port checks as row-backed output.
  // This validator is never used to construct a row-backed completion.
  match
    validate_trusted_output_contract(
      generated, target, max_entries, max_name_bytes, inputs,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    generated,
    target,
    inputs: inputs.map(values => values.copy()).unwrap_or([]),
    verify,
  })
}

///|
/// Seal execution evidence once. Afterwards only this result's representation
/// lifetime is consulted, never the upstream inputs' present availability.
pub fn[P] complete_trusted_retained_output(
  port : TrustedRetainedOutputPort[P],
  proof : P,
) -> Result[CompletedOutput, TrustedOutputIssue] {
  for input in port.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  guard (port.verify)(proof) is Some(material) && (material.available)() else {
    return Err(Unverified)
  }
  let receipt = material.receipt
  let owner = completion_preparation_owner(port.generated)
  let prepared = @lower.bound_preparation(owner)
  if !physical_equal(receipt.owner, owner) || receipt.target != port.target {
    return Err(ForeignOutput)
  }
  guard @lower.preparation_schema_at(prepared, port.target) is Some(schema) &&
    physical_equal(schema, receipt.schema) else {
    return Err(ForeignOutput)
  }
  // A verifier must not revoke an input while reporting completion.
  for input in port.inputs {
    if !producer_read_available(input) {
      return Err(ForeignInputs)
    }
  }
  let completion : CompletedSequence = {
    result_identity: Ref(()),
    readmitted: false,
    contracts: port.generated.contracts,
    sequence: port.generated.sequence,
    store: RetainedStore(
      @lower.preparation_input_count(prepared),
      port.target,
      material,
    ),
    _producer_inputs: [],
    input_bindings: port.inputs.map(input => input.bound.identity),
    live: None,
  }
  Ok({
    completion,
    target: port.target,
    table: None,
    representation: Some(material),
  })
}
