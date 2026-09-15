///|
pub(all) enum ValuesWireBoundIssue {
  Measurement(ValuesMeasurementIssue)
  SubjectMismatch
  LawMismatch
  InvalidProof
  ValueMismatch
} derive(Debug)

///|
/// An applied wire-payload proof with its exact Program/binding owner retained.
/// It is neither a selected limit nor successful publication enforcement.
pub struct ValuesWireBound {
  cells : ProgramOperationCells
  requirement_index : Int
  site : OperationRequirementSite
  proof : @wire.ProgramProofClaim
  bytes : Int
  nodes : Int
  depth : Int
}

///|
pub fn values_wire_bound_contract(_v : ValuesWireBound) -> String {
  "sha256:b36a2c0087fa668e54b50e15ffae0985bda11bf4eab06b46c1b8a91f8750e750"
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
  let requirements = cells.requirements
  guard requirements.entries.get(requirement_index) is Some(site) else {
    return Err(Measurement(InvalidRequirement))
  }
  guard site.requirement
    is @pipeline.ValuesRequirement(@values.ResolvePublicationResources) else {
    return Err(Measurement(InvalidRequirement))
  }
  let witness = @wire.program_proof_witness(proof)
  guard @wire.source(witness) is @wire.Program(subject, _) else {
    return Err(InvalidProof)
  }
  if @step_bounds.subject_ref(site.pipeline, site.step) != Some(subject) {
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
  Ok({ cells, requirement_index, site, proof, bytes, nodes, depth, })
}
