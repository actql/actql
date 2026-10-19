///|
/// An undischarged binding-stage condition from the original Take obligation.
/// This is not a declaration restriction or a value/plan/authority certificate.
pub struct TemplateParameterCondition {
  program : @syntax.Program
  declaration : @parameters.Declaration
  stage : Int
  step : Int
  owner : @pipeline.OperationObligations
  index : Int
  minimum : Int64
  priv ordinal : Int
}

///|
pub fn template_checked_condition_count(value : TemplateCheckedProgram) -> Int {
  value.conditions.length()
}

///|
pub fn template_checked_condition_at(
  value : TemplateCheckedProgram,
  index : Int,
) -> TemplateParameterCondition? {
  value.conditions.get(index)
}

///|
/// Membership is nominal and bound to this complete template, not a matching
/// Parameter name, copied descriptor, declaration or canonical Program body.
pub fn template_condition_matches(
  value : TemplateCheckedProgram,
  condition : TemplateParameterCondition,
) -> Bool {
  physical_equal(value.declarations.program, condition.program) &&
  value.conditions.get(condition.ordinal) is Some(original) &&
  physical_equal(original, condition)
}

///|
pub fn template_condition_source(
  value : TemplateParameterCondition,
) -> @decode.Cursor {
  @pipeline.operation_obligation_source_at(value.owner, value.index).unwrap()
}
