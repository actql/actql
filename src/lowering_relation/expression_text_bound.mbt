///|
/// The original occurrence-bound resolution, retained by lowering only after
/// producer and typed-node identity checks. This view is not Host admission.
struct ExpressionTextBound {
  original : @context.TextBoundResolution
  timestamp : @context.TimestampPatternResolution?
}

///|
pub fn text_bound_output(value : ExpressionTextBound) -> @text_bounds.Output {
  @context.text_bound_output(value.original)
}

///|
pub fn text_bound_policy(value : ExpressionTextBound) -> @environment.TextTime {
  @context.text_bound_policy(value.original)
}

///|
/// Preserve the original typed filter identity without exposing a checker site.
pub fn text_bound_filter(
  value : ExpressionTextBound,
) -> @typing.TypedExpression? {
  let requirement = @context.validation_site_requirement(
    @context.text_bound_site(value.original),
  )
  requirement.filter.map(filter => filter.expression)
}

///|
/// The actual checked pattern attached to the same typed occurrence and producer.
/// No wire reparse, Parameter rebind or pattern issuance occurs at execution.
pub fn text_bound_timestamp_pattern(
  value : ExpressionTextBound,
) -> @timestamp.Pattern? {
  value.timestamp.map(pattern => @context.timestamp_pattern_ast(pattern))
}
