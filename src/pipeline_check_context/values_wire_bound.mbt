///|
pub(all) enum ValuesWireBoundIssue {
  Measurement(ValuesMeasurementIssue)
  SubjectMismatch
  LawMismatch
  InvalidProof
  ValueMismatch
} derive(Debug)

///|
/// An applied wire-payload proof with its exact Values occurrence retained.
/// It is neither a selected limit nor successful publication enforcement.
pub struct ValuesWireBound {
  owner : ValuesResourceOwner
  proof : @wire.ProgramProofClaim
  bytes : Int
  nodes : Int
  depth : Int
}

///|
pub fn values_wire_bound_pipeline(
  value : ValuesWireBound,
) -> @pipeline.CheckedPipeline {
  values_resource_pipeline(value.owner)
}

///|
pub fn values_wire_bound_step(value : ValuesWireBound) -> Int {
  values_resource_step(value.owner)
}

///|
pub fn values_wire_bound_cells(
  value : ValuesWireBound,
) -> ProgramOperationCells? {
  match value.owner.source {
    BoundCells(cells, _, _) => Some(cells)
    Authored(_, _, _) => None
  }
}

///|
pub fn values_wire_bound_site(
  value : ValuesWireBound,
) -> OperationRequirementSite? {
  match value.owner.source {
    BoundCells(_, _, site) => Some(site)
    Authored(_, _, _) => None
  }
}

///|
pub fn values_wire_bound_contract(_v : ValuesWireBound) -> String {
  "sha256:4c9bfcee52cbb204e8a00ca21e2e39b833cb298d517d498cc6002025cbf9156f"
}

///|
/// Apply the pinned byte law, not the row-count law or a backend assertion.
/// Re-measure bound typed values; integrity admission alone is insufficient.
pub fn check_values_wire_bound(
  cells : ProgramOperationCells,
  requirement_index : Int,
  proof : @wire.ProgramProofClaim,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ValuesWireBound, ValuesWireBoundIssue] {
  let owner = match bound_values_resource_owner(cells, requirement_index) {
    Ok(value) => value
    Err(issue) => return Err(Measurement(issue))
  }
  let witness = @wire.program_proof_witness(proof)
  guard @wire.source(witness) is @wire.Program(subject, _) else {
    return Err(InvalidProof)
  }
  if @step_bounds.subject_ref(
      values_resource_pipeline(owner),
      values_resource_step(owner),
    ) !=
    Some(subject) {
    return Err(SubjectMismatch)
  }
  if @law.name(@wire.law(witness)) != "actql.bound.values-wire" ||
    @wire.unit(witness) != @derivation.Bytes {
    return Err(LawMismatch)
  }
  if @wire.program_proof_form(proof) != @wire.DerivedInputs ||
    @wire.program_proof_input_count(proof) != 0 ||
    @wire.role(witness) != @derivation.ProvenUpperBound {
    return Err(InvalidProof)
  }
  guard @wire.derivation(witness) is @wire.SourceValue else {
    return Err(InvalidProof)
  }
  let (bytes, nodes, depth) = match
    measure_operation_values_rows(
      cells, requirement_index, max_bytes, max_nodes, max_depth,
    ) {
    Ok(usage) => usage
    Err(issue) => return Err(Measurement(issue))
  }
  if @wire.value(witness) != bytes.to_int64() {
    return Err(ValueMismatch)
  }
  Ok({ owner, proof, bytes, nodes, depth, })
}
