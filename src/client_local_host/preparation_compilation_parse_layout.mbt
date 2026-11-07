///|
/// One parse_plan_identity_value call, before construction. `value` survives
/// that call; `temporary` is private parser/admission storage. Neither is a
/// final Run holding by itself. The caller owns original emitted wire text.
priv struct CompilationParseLayout {
  value : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
  // Included in temporary until the caller proves this SAME output slot
  // is already reserved or used only at a nonoverlapping constructor phase.
  output_tree : @execution.PreparationRepresentationUnits
}
