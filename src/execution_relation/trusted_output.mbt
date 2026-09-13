///|
/// Trusted Host wiring, not a Connector registration or Program capability.
/// The verifier must return only exact retained material from successful live
/// execution evidence. Creating this port is part of the Host's trusted base.
/// Provider-facing entry points must install their verifier internally.
/// Verification is synchronous and side-effect-free, including repeated checks.
struct TrustedOutputPort[P] {
  generated : GeneratedSequence
  target : @pipeline.Target
  id : String
  names : Array[String]
  verify : (P) -> AdmittedOutputRows?
}

///|
pub(all) enum TrustedOutputIssue {
  InvalidLimits
  Limit
  InvalidTarget
  NotRetained
  Unverified
  ForeignOutput
} derive(Eq, Debug)

///|
/// A low-level trusted-runtime API, deliberately not a raw-data completion
/// constructor. Do not expose verifier installation through untrusted exports.
pub fn[P] prepare_trusted_output_port(
  generated : GeneratedSequence,
  target : @pipeline.Target,
  max_entries : Int,
  max_name_bytes : Int,
  verify : (P) -> AdmittedOutputRows?,
) -> Result[TrustedOutputPort[P], TrustedOutputIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  let owner = generated_sequence_owner(generated)
  let prepared = @lower.bound_preparation(owner)
  guard target is Step(index) &&
    index == @lower.sequence_count(generated.sequence) - 1 &&
    @lower.node_at(prepared, index) is Some(node) &&
    @pipeline.schema_at(@lower.pipeline(prepared), target) is Some(schema) else {
    return Err(InvalidTarget)
  }
  // This bridge publishes only the completed final target, never intermediate
  // operations for which a backend's success evidence may provide no material.
  if generated.retained_ids.length() != 1 {
    return Err(NotRetained)
  }
  let id = @lower.node_id(node)
  let mut bytes = max_name_bytes
  for name in [id, generated.retained_ids[0]] {
    match @scalar.admit_utf8_length(name, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
  }
  if generated.retained_ids[0] != id {
    return Err(NotRetained)
  }
  let width = @schema.field_count(schema)
  if width > max_entries {
    return Err(Limit)
  }
  let names = []
  for column in 0..<width {
    let name = @schema.reference_name(
      @schema.field_at(schema, column).unwrap().name,
    )
    match @scalar.admit_utf8_length(name, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
    names.push(name)
  }
  Ok({ generated, target, id, names, verify, })
}

///|
/// Evidence selects the retained data through the installed verifier. Neither
/// caller-supplied rows nor a boolean can substitute for that relationship.
pub fn[P] complete_trusted_output(
  port : TrustedOutputPort[P],
  proof : P,
) -> Result[CompletedOutput, TrustedOutputIssue] {
  guard (port.verify)(proof) is Some(rows) else { return Err(Unverified) }
  let owner = generated_sequence_owner(port.generated)
  if !physical_equal(rows.owner, owner) || rows.target != port.target {
    return Err(ForeignOutput)
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
  guard @pipeline.schema_at(pipeline, port.target) is Some(schema) &&
    physical_equal(schema, rows.schema) else {
    return Err(ForeignOutput)
  }
  let table = CompletedTable::AdmittedTable({
    owner,
    id: port.id,
    names: port.names,
    rows: rows.rows,
  })
  let live = fn() {
    match (port.verify)(proof) {
      Some(current) => physical_equal(current, rows)
      None => false
    }
  }
  let completion : CompletedSequence = {
    contracts: port.generated.contracts,
    sequence: port.generated.sequence,
    store: ImportedStore(@pipeline.input_count(pipeline), port.target, table),
    _producer_inputs: [],
    live: Some(live),
  }
  Ok({ completion, target: port.target, table, })
}

///|
fn completion_is_live(completion : CompletedSequence) -> Bool {
  match completion.live {
    None => true
    Some(check) => check()
  }
}
