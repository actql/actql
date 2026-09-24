///|
pub(all) enum SalesforceBroadIssue {
  ForeignSource
  InvalidInputSchema
  UnexpectedPrefilter
  Query(@catalog.QueryReadIssue)
  Capture(@execution.CaptureIssue)
  Closed
  Incomplete
} derive(Eq, Debug)

///|
/// One exact checked source and a broad provider projection. Selection,
/// current authority, physical capacity, evidence, and capture remain pending.
struct SalesforceBroadPreparation {
  requirement : @planning.QueryRequirement
  plan : @catalog.ReadProjection
  owner : @lower.BoundPrepared
  input_index : Int
  columns : Array[Int]
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
pub fn prepare_salesforce_broad_query(
  requirement : @planning.QueryRequirement,
  plan : @catalog.ReadProjection,
  connector_instance : String,
) -> Result[SalesforceBroadPreparation, SalesforceBroadIssue] {
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
  let (columns, bound) = match projection_columns(plan, schema) {
    Some(value) => value
    None => return Err(InvalidInputSchema)
  }
  let filtered = exact_int_prefilter(
    owner,
    @sourcequery.query_acquisition_filter_index(query),
    bound,
  ).unwrap_or(bound)
  Ok({ requirement, plan: filtered, owner, input_index, columns, })
}

///|
pub fn salesforce_broad_requirement(
  preparation : SalesforceBroadPreparation,
) -> @planning.QueryRequirement {
  preparation.requirement
}

///|
pub fn salesforce_broad_plan(
  preparation : SalesforceBroadPreparation,
) -> @catalog.ReadProjection {
  preparation.plan
}

///|
pub(all) enum SalesforceBroadWork {
  CatalogRefresh
  SourceQuery
  ReceiptTransfer
  ReceiptConversion
  LocalResidual
  ObservationCapture
  Retention
  Cleanup
} derive(Eq, Debug)

///|
pub fn salesforce_broad_work_at(index : Int) -> SalesforceBroadWork? {
  match index {
    0 => Some(CatalogRefresh)
    1 => Some(SourceQuery)
    2 => Some(ReceiptTransfer)
    3 => Some(ReceiptConversion)
    4 => Some(LocalResidual)
    5 => Some(ObservationCapture)
    6 => Some(Retention)
    7 => Some(Cleanup)
    _ => None
  }
}

///|
/// The common planner owns comparison; this contribution does not grant I/O.
pub fn salesforce_broad_candidate(
  registration : @connector.CapabilityRegistration,
  preparation : SalesforceBroadPreparation,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @planning.PreparedAcquisition[SalesforceBroadPreparation],
  @planning.QueryPlanningIssue,
] {
  let duration = match @cost.assess_serial(8, estimates, max_entries) {
    Ok(value) => value
    Err(issue) => return Err(Cost(issue))
  }
  @planning.bind_acquisition_candidate(
    registration,
    preparation.requirement,
    preparation,
    duration,
    quantities,
  )
}

///|
/// Each page is admitted into the exact checked input schema before the next
/// locator is requested. The owner exposes no partial CapturedRows on failure.
struct SalesforceBroadQuery {
  preparation : SalesforceBroadPreparation
  read : @catalog.QueryRead
  input : @execution.AdmittedInput
  mut open : Bool
}

///|
pub fn begin_salesforce_broad_query(
  preparation : SalesforceBroadPreparation,
  api_version : String,
  page_limits : @catalog.QueryPageLimits,
  max_pages : Int,
  max_total_rows : Int64,
  max_capture_rows : Int,
  retention : @execution.ValueLimits,
) -> Result[SalesforceBroadQuery, SalesforceBroadIssue] {
  let read = match
    @catalog.begin_query_read(
      preparation.plan,
      api_version,
      page_limits,
      max_pages,
      max_total_rows,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Query(issue))
  }
  let input = match
    @execution.prepare_admitted_input(
      preparation.owner,
      preparation.input_index,
      max_capture_rows,
      retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  Ok({ preparation, read, input, open: true, })
}

///|
pub fn salesforce_broad_next_path(
  query : SalesforceBroadQuery,
) -> Result[String?, SalesforceBroadIssue] {
  if !query.open {
    return Ok(None)
  }
  match @catalog.query_read_next_path(query.read) {
    Ok(path) => Ok(path)
    Err(issue) => {
      cancel_salesforce_broad_query(query) |> ignore
      Err(Query(issue))
    }
  }
}

///|
pub fn cancel_salesforce_broad_query(query : SalesforceBroadQuery) -> Bool {
  if !query.open {
    return false
  }
  query.open = false
  @catalog.interrupt_query_read(query.read) |> ignore
  @execution.cancel_admitted_input(query.input) |> ignore
  true
}

///|
pub fn accept_salesforce_broad_page(
  query : SalesforceBroadQuery,
  path : String,
  bytes : Bytes,
) -> Result[@catalog.QueryPage, SalesforceBroadIssue] {
  if !query.open {
    return Err(Closed)
  }
  let page = match @catalog.query_read_accept_page(query.read, path, bytes) {
    Ok(value) => value
    Err(issue) => {
      cancel_salesforce_broad_query(query) |> ignore
      return Err(Query(issue))
    }
  }
  if !@catalog.query_page_matches_projection(page, query.preparation.plan) {
    cancel_salesforce_broad_query(query) |> ignore
    return Err(InvalidInputSchema)
  }
  for row_index in 0..<@catalog.query_page_row_count(page) {
    let row = []
    for column in query.preparation.columns {
      guard @catalog.query_page_cell(page, row_index, column) is Some(cell) else {
        cancel_salesforce_broad_query(query) |> ignore
        return Err(InvalidInputSchema)
      }
      row.push(cell)
    }
    match @execution.append_admitted_input(query.input, row) {
      Ok(_) => ()
      Err(issue) => {
        cancel_salesforce_broad_query(query) |> ignore
        return Err(Capture(issue))
      }
    }
  }
  match @catalog.acknowledge_query_page(query.read, page) {
    Ok(_) => Ok(page)
    Err(issue) => {
      cancel_salesforce_broad_query(query) |> ignore
      Err(Query(issue))
    }
  }
}

///|
pub fn salesforce_broad_complete(query : SalesforceBroadQuery) -> Bool {
  query.open && @catalog.query_read_complete(query.read)
}

///|
pub fn salesforce_broad_row_count(query : SalesforceBroadQuery) -> Int64 {
  @catalog.query_read_row_count(query.read)
}

///|
pub fn finish_salesforce_broad_query(
  query : SalesforceBroadQuery,
) -> Result[@execution.CapturedRows, SalesforceBroadIssue] {
  if !query.open {
    return Err(Closed)
  }
  if !@catalog.query_read_complete(query.read) {
    return Err(Incomplete)
  }
  query.open = false
  @execution.finish_admitted_input(query.input).map_err(issue => Capture(issue))
}

///|
/// Run the existing checked filter/select over the complete broad input.
/// This is local residual computation, not an Acquisition completion claim.
pub fn execute_salesforce_broad_residual(
  preparation : SalesforceBroadPreparation,
  input : @execution.CapturedRows,
  limits : @execution.SequenceExecutionLimits,
  measurement : @query.QueryGuardMeasureLimits,
) -> Result[
  (@execution.CompletedSequence, (Int, Int, Int)),
  @query.QueryGuardIssue,
] {
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(preparation.requirement),
  )
  let receipt = match @query.bind_query_receipt(sequence, input) {
    Ok(value) => value
    Err(issue) => return Err(Execution(issue))
  }
  let guards = @planning.query_requirement_guards(preparation.requirement)
  @query.execute_query_receipt_guarded(
    sequence,
    receipt,
    limits,
    max_output_rows=guards.max_rows,
    max_value_bytes=guards.max_value_bytes,
    measurement,
  )
}
