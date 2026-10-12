///|
/// A Source acquisition ceiling at its normative Unit input reference. Retain
/// the Catalog/profile owner and original input rather than manufacturing an
/// ordinary operation proof or attesting to completed physical acquisition.
struct ReidentifiedSourceInput {
  original : @step_bounds.SourceInputRows
  unit_definition_cid : String
  input_reference : String
  rows : @wire.LimitClaim
}

///|
fn reidentify_source_input(
  unit : BuiltUnit,
  input : @step_bounds.SourceInputRows,
  budget : IdentityBudget,
) -> ReidentifiedSourceInput raise UnitBuildFailure {
  if !physical_equal(
      unit.pipeline,
      @step_bounds.source_input_rows_pipeline(input),
    ) {
    raise ForeignOwner
  }
  let index = @step_bounds.source_input_rows_index(input)
  guard @pipeline.input_at(unit.pipeline, index) is Some((name, _)) else {
    raise ForeignOwner
  }
  let original = @step_bounds.source_input_rows_limit(input)
  if @wire.limit_subject(@environment.file_listing_rows_claim(original)) !=
    @step_bounds.source_input_rows_subject(unit.pipeline, index).unwrap() {
    raise ForeignOwner
  }
  let remaining = IdentityBudget::{ ..budget, }
  identity_charge(remaining, 1)
  for _ in 0..<3 {
    identity_charge(remaining, name.length())
  }
  identity_charge(remaining, unit.definition_cid.length())
  let reference = "unit:" +
    unit.definition_cid +
    "#/inputs/" +
    name.replace(old="~", new="~0").replace(old="/", new="~1")
  // Reidentify the already checked candidates, not a second resolution of the
  // Catalog and policy. The existing artifact builder meters each encoding
  // pass and debits retained bytes/nodes against this same IdentityBudget.
  // Streaming acquisition enforcement must not become engine enforcement.
  let claim = @environment.file_listing_rows_claim(original)
  let rows = reidentify_sequence_limit(
    claim,
    reference + "/rows",
    "rows",
    remaining,
    enforcement=@wire.limit_enforcement(claim),
  )
  if @derivation.minimum_value(@wire.limit_minimum(rows)) !=
    @environment.file_listing_rows_maximum(original) ||
    !physical_equal(@wire.limit_claims(rows), @wire.limit_claims(claim)) {
    raise ForeignOwner
  }
  budget.work = remaining.work
  budget.bytes = remaining.bytes
  budget.nodes = remaining.nodes
  {
    original: input,
    unit_definition_cid: unit.definition_cid,
    input_reference: reference,
    rows,
  }
}

///|
pub fn reidentified_source_input_original(
  value : ReidentifiedSourceInput,
) -> @step_bounds.SourceInputRows {
  value.original
}

///|
pub fn reidentified_source_input_unit(
  value : ReidentifiedSourceInput,
) -> String {
  value.unit_definition_cid
}

///|
pub fn reidentified_source_input_reference(
  value : ReidentifiedSourceInput,
) -> String {
  value.input_reference
}

///|
pub fn reidentified_source_input_rows(
  value : ReidentifiedSourceInput,
) -> @wire.LimitClaim {
  value.rows
}
