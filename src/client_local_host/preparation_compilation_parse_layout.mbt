///|
/// One parse_plan_identity_value call, before construction. `value` survives
/// that call; `temporary` is private parser/admission storage. Neither is a
/// final Run holding by itself. The caller owns original emitted wire text.
priv struct CompilationParseLayout {
  value : @execution.PreparationRepresentationUnits
  temporary : @execution.PreparationRepresentationUnits
}
