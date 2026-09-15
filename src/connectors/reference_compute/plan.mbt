///|
/// Independent conformance connector's bounded numeric specialization. This is
/// a physical plan, not execution evidence or a replacement checked program.
struct NumericPlan {
  owner : @lower.BoundPrepared
  predicate_field : String
  threshold : Double
  fields : Array[@relation.ProjectionField]
}

///|
pub(all) enum PlanIssue {
  Unsupported
  Preparation(@lower.KernelIssue)
  Limit
}

///|
pub fn prepare_numeric_plan(
  owner : @lower.BoundPrepared,
  max_entries : Int,
  max_name_bytes : Int,
  expressions : @lower.ExpressionLimits,
) -> Result[NumericPlan, PlanIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(Limit)
  }
  let preparation = @lower.bound_preparation(owner)
  let pipeline = @lower.pipeline(preparation)
  if @pipeline.input_count(pipeline) != 1 || @pipeline.step_count(pipeline) != 2 {
    return Err(Unsupported)
  }
  let filter = match
    @lower.prepare_kernel(
      owner,
      0,
      max_bindings=max_entries,
      max_name_bytes~,
      expressions,
    ) {
    Ok(kernel) => kernel
    Err(issue) => return Err(Preparation(issue))
  }
  let project = match
    @lower.prepare_kernel(
      owner,
      1,
      max_bindings=max_entries,
      max_name_bytes~,
      expressions,
    ) {
    Ok(kernel) => kernel
    Err(issue) => return Err(Preparation(issue))
  }
  if @lower.kernel_view_entries(filter) > max_entries ||
    @lower.kernel_view_entries(project) >
    max_entries - @lower.kernel_view_entries(filter) {
    return Err(Limit)
  }
  guard @lower.kernel_body(filter) is @lower.Filter(predicate) &&
    @lower.kernel_body(project) is @lower.Select(fields) &&
    @lower.node_at(preparation, 0) is Some(node) &&
    @lower.kernel_input(project) == @lower.node_id(node) &&
    Some(@lower.kernel_input(filter)) == @lower.input_id(preparation, 0) else {
    return Err(Unsupported)
  }
  guard @lower.expression_body(predicate) is @lower.Binary(Greater, left, right) &&
    @lower.expression_body(left)
    is @lower.Field(_, @relation.InputField(@schema.Unqualified(name))) &&
    @lower.expression_contract(left).shape is @contract.Number &&
    @lower.expression_body(right) is @lower.Literal(value) &&
    value.value is @admitted.Number(threshold) else {
    return Err(Unsupported)
  }
  guard @pipeline.schema_at(pipeline, Input(0)) is Some(schema) else {
    return Err(Unsupported)
  }
  for field in fields {
    guard field.input is @schema.Unqualified(input) &&
      field.output is @schema.Unqualified(_) &&
      @schema.lookup_reference(schema, input) is Some(source) &&
      source.contract.shape is @contract.Number else {
      return Err(Unsupported)
    }
  }
  Ok({ owner, predicate_field: name, threshold, fields: fields.copy(), })
}

///|
pub fn numeric_plan_owner(plan : NumericPlan) -> @lower.BoundPrepared {
  plan.owner
}
