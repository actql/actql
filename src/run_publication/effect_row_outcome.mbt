///|
pub(all) enum EffectRowOutcomeIssue {
  InvalidRow
  ForeignRow
  Outcome(PublicationContractIssue)
} derive(Debug)

///|
/// Check a typed provider projection against one admitted Preview row. This
/// establishes neither response custody nor a terminal outcome receipt.
pub fn check_effect_preview_row_outcome(
  preview : EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  projected_row_cid : String,
  outcome_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, EffectRowOutcomeIssue] {
  guard effect_preview_row_identity(preview, member_index, row_index)
    is Some(expected) else {
    return Err(InvalidRow)
  }
  if projected_row_cid != expected {
    return Err(ForeignRow)
  }
  parse_effect_outcome_shape(outcome_wire, max_wire_bytes, max_nodes, max_depth)
  .map(_ => ())
  .map_err(issue => Outcome(issue))
}
