///|
/// The original occurrence-bound resolution, retained by lowering only after
/// producer and typed-node identity checks. This view is not Host admission.
struct ExpressionTextBound(@context.TextBoundResolution)

///|
pub fn text_bound_output(value : ExpressionTextBound) -> @text_bounds.Output {
  @context.text_bound_output(value.0)
}

///|
pub fn text_bound_policy(value : ExpressionTextBound) -> @environment.TextTime {
  @context.text_bound_policy(value.0)
}

///|
/// Preserve the original typed filter identity without exposing a checker site.
pub fn text_bound_filter(
  value : ExpressionTextBound,
) -> @typing.TypedExpression? {
  let requirement = @context.validation_site_requirement(
    @context.text_bound_site(value.0),
  )
  requirement.filter.map(filter => filter.expression)
}
