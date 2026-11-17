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
  schema : @schema.Schema
  verify : (P) -> RetainedOutputMaterial?
  mut open : Bool
}

///|
/// Explicit compatibility policy. Row cardinality is never a metadata limit.
pub(all) struct RetainedReadmissionMetadataPolicy {
  producer_inputs : Int?
  schema_columns : Int?
  name_bytes : Int?
}

///|
priv enum RetainedReadmissionFactsOrigin {
  Live(CompletedOutput)
  Receiving(CompletionPreparation, RetainedCompletionDescriptor)
}

///|
/// Immutable geometry of one exact completion or receiving preparation. These
/// facts grant no custody, currentness, allocation or successful completion.
struct RetainedReadmissionFacts {
  origin : RetainedReadmissionFactsOrigin
  schema : @schema.Schema
  rows : Int
  producer_inputs : Int
  schema_columns : Int
  binding_entries : Int
}

///|
// New fixed issuance/return controls only: target/schema/node Options,
// origin+fact+Results, named policy+three optional Ints, target/schema/node
// Options, identifier result and one live scalar decoder Some/tuple.
// The call-expanded packet co-counts sequential alternatives (15H/13R/13W),
// including the materialization holder's optional facts link and the added
// TrustedRetainedReadmission checked-schema field. The issued facts object
// itself is not retained by the receiving port.
// Schema names borrow
// their checked UTF8 measurement; there is no variable name array or copy.
let retained_readmission_facts_control : Int64 = preparation_representation_cost({
    record_headers: 15L,
    reference_slots: 13L,
    scalar_words: 13L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  },
).unwrap()

///|
/// Constructor demand DATA. The existing read/assembly admits this amount
/// before issuing facts; this scalar neither issues nor authenticates a Read.
pub fn retained_readmission_facts_control_bytes() -> Int64 {
  retained_readmission_facts_control
}

///|
fn retained_readmission_identifier_bytes(value : String) -> Int? {
  let mut bytes = 0
  let mut offset = 0
  while offset < value.length() {
    guard text_function_scalar(value, offset) is Some((_, next, width, _)) &&
      width <= 2147483647 - bytes else {
      return None
    }
    bytes += width
    offset = next
  }
  Some(bytes)
}

///|
fn check_retained_readmission_metadata(
  schema : @schema.Schema,
  identifier : String,
  inputs : Int,
  columns : Int,
  policy : RetainedReadmissionMetadataPolicy,
) -> Result[Unit, TrustedOutputIssue] {
  if (policy.producer_inputs is Some(input_limit) && input_limit < 0) ||
    (policy.schema_columns is Some(column_limit) && column_limit < 0) ||
    (policy.name_bytes is Some(name_limit) && name_limit < 0) {
    return Err(InvalidLimits)
  }
  if (policy.producer_inputs is Some(input_limit) && inputs > input_limit) ||
    (policy.schema_columns is Some(column_limit) && columns > column_limit) {
    return Err(Limit)
  }
  guard retained_readmission_identifier_bytes(identifier) is Some(id_bytes) else {
    return Err(Limit)
  }
  // Schema admission already checked these immutable scalar names. Reuse
  // its exact retained UTF8 count instead of rebuilding/discarding names.
  let names = @schema.field_reference_name_bytes(schema)
  if policy.name_bytes is Some(remaining) &&
    (
      id_bytes > remaining ||
      id_bytes > remaining - id_bytes ||
      names > remaining - id_bytes - id_bytes
    ) {
    return Err(Limit)
  }
  Ok(())
}

///|
/// Borrow the existing successful output; never generate another completion.
pub fn retained_input_facts(
  output : CompletedOutput,
) -> Result[RetainedReadmissionFacts, TrustedOutputIssue] {
  guard output.target is Step(step) else { return Err(InvalidTarget) }
  let prepared = @lower.bound_preparation(
    @lower.sequence_owner(output.completion.sequence),
  )
  guard @lower.node_at(prepared, step) is Some(node) else {
    return Err(InvalidTarget)
  }
  let schema = completed_output_relation_schema(output)
  let inputs = @lower.preparation_input_count(prepared)
  let columns = @schema.field_count(schema)
  match
    check_retained_readmission_metadata(
      schema,
      @lower.node_id(node),
      inputs,
      columns,
      { producer_inputs: None, schema_columns: None, name_bytes: None, },
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    origin: Live(output),
    schema,
    rows: completed_row_count(output),
    producer_inputs: inputs,
    schema_columns: columns,
    // Retained producer binding entries need not equal checked Program input
    // ports: a prefix can have an internal producer without an external input.
    binding_entries: output.completion.input_bindings.length(),
  })
}

///|
/// Bind freshly recovered metadata to THIS receiving preparation and exact
/// saved descriptor. Equal bytes from another process require a fresh issuer;
/// an old nominal preparation or a caller-created fact cannot be reused.
pub fn prepare_retained_readmission_facts(
  preparation : CompletionPreparation,
  expected : RetainedCompletionDescriptor,
  saved_rows : Int,
  policy : RetainedReadmissionMetadataPolicy,
) -> Result[RetainedReadmissionFacts, TrustedOutputIssue] {
  if expected.registry_cid != preparation.contracts.registry_cid ||
    expected.values_contract_cid != preparation.contracts.values_contract_cid ||
    expected.rows != saved_rows ||
    saved_rows < 0 ||
    expected.bytes < 0 ||
    expected.nodes < 0 ||
    expected.depth < 0 ||
    expected.values.nodes < 0 ||
    expected.values.text_bytes < 0 ||
    expected.values.work < 0 {
    return Err(ForeignOutput)
  }
  if expected.output_step != completion_preparation_terminal_step(preparation) {
    return Err(InvalidTarget)
  }
  if preparation.retained_ids.length() != 1 {
    return Err(NotRetained)
  }
  let target = @pipeline.Step(expected.output_step)
  let prepared = @lower.bound_preparation(
    completion_preparation_owner(preparation),
  )
  guard @lower.node_at(prepared, expected.output_step) is Some(node) &&
    completion_preparation_schema(preparation, target) is Some(schema) else {
    return Err(InvalidTarget)
  }
  let identifier = @lower.node_id(node)
  if identifier != preparation.retained_ids[0] {
    return Err(NotRetained)
  }
  let inputs = @lower.preparation_input_count(prepared)
  let columns = @schema.field_count(schema)
  if expected.input_count != inputs || expected.columns != columns {
    return Err(ForeignOutput)
  }
  match
    check_retained_readmission_metadata(
      schema, identifier, inputs, columns, policy,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({
    origin: Receiving(preparation, expected),
    schema,
    rows: saved_rows,
    producer_inputs: inputs,
    schema_columns: columns,
    // Recovered provenance is verified by custody, not recreated as local
    // producer handles. Readmission below deliberately retains no bindings.
    binding_entries: 0,
  })
}

///|
pub fn retained_readmission_rows(value : RetainedReadmissionFacts) -> Int {
  value.rows
}

///|
pub fn retained_readmission_producer_inputs(
  value : RetainedReadmissionFacts,
) -> Int {
  value.producer_inputs
}

///|
pub fn retained_readmission_schema_columns(
  value : RetainedReadmissionFacts,
) -> Int {
  value.schema_columns
}

///|
pub fn retained_readmission_binding_entries(
  value : RetainedReadmissionFacts,
) -> Int {
  value.binding_entries
}

///|
pub fn[P] prepare_trusted_retained_readmission(
  preparation : CompletionPreparation,
  expected : RetainedCompletionDescriptor,
  facts : RetainedReadmissionFacts,
  verify : (P) -> RetainedOutputMaterial?,
) -> Result[TrustedRetainedReadmission[P], TrustedOutputIssue] {
  guard facts.origin is Receiving(original, descriptor) &&
    physical_equal(original, preparation) &&
    physical_equal(descriptor, expected) else {
    return Err(ForeignOutput)
  }
  // Immutable metadata was validated exactly once by its issuer. Current
  // custody and full content are still checked by the real verifier below.
  Ok({ preparation, expected, schema: facts.schema, verify, open: true, })
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
    physical_equal(receipt.schema, port.schema) else {
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
  let verify = port.verify
  let completion : CompletedSequence = {
    result_identity: Ref(()),
    readmitted: true,
    serialization_output: port.preparation.serialization_output,
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
      match verify(proof) {
        Some(current) => physical_equal(current, material)
        None => false
      }
    }),
  }
  Ok({ completion, target, table: None, representation: Some(material), })
}

///|
fn retained_input_facts_match_output(
  facts : RetainedReadmissionFacts,
  output : CompletedOutput,
) -> Bool {
  guard facts.origin is Live(original) else { return false }
  physical_equal(
    original.completion.result_identity,
    output.completion.result_identity,
  ) &&
  physical_equal(original.completion.sequence, output.completion.sequence) &&
  original.target == output.target
}

///|
/// Same issued live facts; no original Program/schema recount is performed.
pub fn retain_completion_evidence_with_facts(
  output : CompletedOutput,
  facts : RetainedReadmissionFacts,
) -> Result[RetainedCompletionEvidence, RetainedCompletionEvidenceIssue] {
  if !retained_input_facts_match_output(facts, output) {
    return Err(InvalidTarget)
  }
  if !completed_output_available(output) {
    return Err(Unavailable)
  }
  guard output.representation is Some(material) else { return Err(NotRetained) }
  if !physical_equal(material.receipt.schema, facts.schema) ||
    material.receipt.rows != facts.rows ||
    output.completion.input_bindings.length() != facts.binding_entries {
    return Err(MetadataLimit)
  }
  let completion = output.completion
  Ok({
    result_identity: completion.result_identity,
    contracts: completion.contracts,
    sequence: completion.sequence,
    target: output.target,
    input_bindings: completion.input_bindings.copy(),
    receipt: material.receipt,
  })
}

///|
/// Persist canonical values from the same fact family, not the nominal
/// receiving preparation. A cold process verifies them and issues new facts.
pub fn retained_completion_descriptor_with_facts(
  evidence : RetainedCompletionEvidence,
  facts : RetainedReadmissionFacts,
) -> Result[RetainedCompletionDescriptor, RetainedCompletionEvidenceIssue] {
  guard facts.origin is Live(original) &&
    physical_equal(
      evidence.result_identity,
      original.completion.result_identity,
    ) &&
    physical_equal(evidence.sequence, original.completion.sequence) &&
    evidence.target == original.target &&
    physical_equal(evidence.receipt.schema, facts.schema) &&
    evidence.receipt.rows == facts.rows else {
    return Err(InvalidTarget)
  }
  guard evidence.target is Step(output_step) else { return Err(InvalidTarget) }
  let receipt = evidence.receipt
  Ok({
    registry_cid: evidence.contracts.registry_cid,
    values_contract_cid: evidence.contracts.values_contract_cid,
    rows_cid: receipt.cid,
    output_step,
    input_count: facts.producer_inputs,
    columns: facts.schema_columns,
    rows: facts.rows,
    bytes: receipt.bytes,
    nodes: receipt.nodes,
    depth: receipt.depth,
    values: receipt.usage,
  })
}
