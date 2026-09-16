///|
/// Installed Host boundary for an independently retained, already completed
/// occurrence. This is not the completion path for a new Compute/Acquisition.
/// The verifier must bind its proof to exact surviving custody, the newly
/// checked owner, the original input/task/attempt facts, a receiving permit,
/// successful full-body verification and the admitted live physical holding.
/// Neither descriptor equality nor content admission satisfies that contract.
/// Verification is synchronous and side-effect-free. It may consult this
/// receiving grant's revocation, never the original upstream's current life.
struct TrustedRetainedReadmission[P] {
  preparation : CompletionPreparation
  expected : RetainedCompletionDescriptor
  verify : (P) -> RetainedOutputMaterial?
  mut open : Bool
}

///|
pub fn[P] prepare_trusted_retained_readmission(
  preparation : CompletionPreparation,
  expected : RetainedCompletionDescriptor,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> RetainedOutputMaterial?,
) -> Result[TrustedRetainedReadmission[P], TrustedOutputIssue] {
  // Reuse target/schema/retention validation, not Acquisition provenance.
  // Original process-local input handles cannot be replayed in this runtime.
  match
    validate_trusted_output_contract(
      preparation,
      Step(expected.output_step),
      max_entries,
      max_name_bytes,
      None,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let owner = completion_preparation_owner(preparation)
  let prepared = @lower.bound_preparation(owner)
  let width = @schema.field_count(
    @lower.preparation_schema_at(prepared, Step(expected.output_step)).unwrap(),
  )
  if expected.registry_cid != preparation.contracts.registry_cid ||
    expected.values_contract_cid != preparation.contracts.values_contract_cid ||
    expected.input_count != @lower.preparation_input_count(prepared) ||
    expected.columns != width ||
    expected.input_count > max_entries ||
    expected.rows < 0 ||
    expected.bytes < 0 ||
    expected.nodes < 0 ||
    expected.depth < 0 ||
    expected.values.nodes < 0 ||
    expected.values.text_bytes < 0 ||
    expected.values.work < 0 {
    return Err(ForeignOutput)
  }
  Ok({ preparation, expected, verify, open: true, })
}

///|
/// One admitted local instance of a retained completion fact. Failure consumes
/// this admission attempt; it cannot restore a failed Program's dispatch.
pub fn[P] readmit_trusted_retained_output(
  port : TrustedRetainedReadmission[P],
  proof : P,
) -> Result[CompletedOutput, TrustedOutputIssue] {
  if !port.open {
    return Err(Unverified)
  }
  port.open = false
  guard (port.verify)(proof) is Some(material) && (material.available)() else {
    return Err(Unverified)
  }
  let receipt = material.receipt
  let owner = completion_preparation_owner(port.preparation)
  let expected = port.expected
  let target = @pipeline.Target::Step(expected.output_step)
  guard physical_equal(receipt.owner, owner) &&
    receipt.target == target &&
    @lower.preparation_schema_at(@lower.bound_preparation(owner), target)
    is Some(schema) &&
    physical_equal(receipt.schema, schema) else {
    return Err(ForeignOutput)
  }
  if receipt.cid != expected.rows_cid ||
    receipt.rows != expected.rows ||
    receipt.bytes != expected.bytes ||
    receipt.nodes != expected.nodes ||
    receipt.depth != expected.depth ||
    receipt.usage != expected.values {
    return Err(ForeignOutput)
  }
  let completion : CompletedSequence = {
    result_identity: Ref(()),
    readmitted: true,
    contracts: port.preparation.contracts,
    sequence: port.preparation.sequence,
    store: RetainedStore(expected.input_count, target, material),
    _producer_inputs: [],
    // Original provenance is verified by custody, not reconstructed by
    // manufacturing local ProducerReads or synthetic binding identities.
    input_bindings: [],
    // Preserve the receiving grant's logical revocation across representation
    // conversion. Physical-copy loss remains material.available, independently.
    live: Some(fn() {
      match (port.verify)(proof) {
        Some(current) => physical_equal(current, material)
        None => false
      }
    }),
  }
  Ok({ completion, target, table: None, representation: Some(material), })
}
