///|
pub(all) enum SalesforceReadPreparationIssue {
  ForeignSource
  InvalidInputSchema
  UnexpectedPrefilter
  Undeclared(@catalog.DeclarationUseIssue)
} derive(Eq, Debug)

///|
/// One exact checked source and a broad provider projection. Selection,
/// current authority, physical capacity, evidence, and capture remain pending.
struct SalesforceReadPreparation {
  requirement : @planning.QueryRequirement
  plan : @catalog.ReadProjection
}

///|
/// An optional exact prefilter is derived only from the bound checked filter.
/// An unsupported expression retains the broad query and the full residual.
fn exact_int_prefilter(
  owner : @lower.BoundPrepared,
  filter_index : Int,
  plan : @catalog.ReadProjection,
) -> @catalog.ReadProjection? {
  guard @lower.lower_expression(owner, filter_index, 0, {
      max_nodes: 3,
      max_work: 16,
      max_depth: 3,
      max_literal_nodes: 1,
      max_literal_text_bytes: 16,
    })
    is Ok(expression) &&
    @lower.expression_body(expression) is @lower.Binary(operator, left, right) &&
    @lower.expression_body(left)
    is @lower.Field(_, @relation.InputField(@schema.Unqualified(name))) &&
    @lower.expression_contract(left).shape is @contract.Number &&
    @lower.expression_body(right) is @lower.Literal(value) &&
    value.value is @admitted.Number(number) else {
    return None
  }
  let threshold = number.to_int()
  if threshold.to_double() != number {
    return None
  }
  let comparison = match operator {
    @lower.Equal => @catalog.ExactIntComparison::Equal
    @lower.Less => @catalog.ExactIntComparison::Less
    @lower.LessEqual => @catalog.ExactIntComparison::LessEqual
    @lower.Greater => @catalog.ExactIntComparison::Greater
    @lower.GreaterEqual => @catalog.ExactIntComparison::GreaterEqual
    _ => return None
  }
  @catalog.with_exact_int_comparison(plan, name, comparison, threshold)
}

///|
/// The checked source must be a SourceView of this Site's declaration for
/// the planned Resource and fields; otherwise nothing is prepared.
pub fn prepare_salesforce_row_projection(
  requirement : @planning.QueryRequirement,
  plan : @catalog.ReadProjection,
  connector_instance : String,
  site_declaration : @catalog.StaticDeclaration,
) -> Result[SalesforceReadPreparation, SalesforceReadPreparationIssue] {
  if @catalog.read_projection_has_prefilter(plan) {
    return Err(UnexpectedPrefilter)
  }
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let query = @query.query_sequence_requirement(sequence)
  let requests = @sourcequery.query_acquisition_owner(query)
  guard @sourcequery.pipeline_request_at(
      requests,
      @sourcequery.query_acquisition_source_index(query),
    )
    is Some(@sourcequery.Direct(mode, _)) else {
    return Err(ForeignSource)
  }
  let declaration = @sourcequery.declaration(@sourcequery.mode_input(mode))
  if declaration.connector != connector_instance ||
    declaration.resource != @catalog.read_projection_resource(plan) {
    return Err(ForeignSource)
  }
  let owner = @query.query_sequence_owner(sequence)
  guard @sourcequery.query_acquisition_input(query)
    is @pipeline.Input(input_index) &&
    @lower.preparation_input_schema(
      @lower.bound_preparation(owner),
      input_index,
    )
    is Some(schema) else {
    return Err(InvalidInputSchema)
  }
  let (_, bound) = match projection_columns(plan, schema) {
    Some(value) => value
    None => return Err(InvalidInputSchema)
  }
  if connector_instance != site_declaration.connector_id {
    return Err(ForeignSource)
  }
  match
    @catalog.check_declared_read(
      site_declaration,
      bound,
      @planning.query_requirement_source(requirement).1,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Undeclared(issue))
  }
  let filtered = exact_int_prefilter(
    owner,
    @sourcequery.query_acquisition_filter_index(query),
    bound,
  ).unwrap_or(bound)
  Ok({ requirement, plan: filtered, })
}

///|
pub fn salesforce_read_requirement(
  preparation : SalesforceReadPreparation,
) -> @planning.QueryRequirement {
  preparation.requirement
}

///|
pub fn salesforce_read_plan(
  preparation : SalesforceReadPreparation,
) -> @catalog.ReadProjection {
  preparation.plan
}
