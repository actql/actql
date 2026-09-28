///|
pub struct ClientResultPlanIdentity {
  wire : String
  cid : String
  result_name : String
  unit_definition_cid : String
  unit_result_name : String
  unit_result_ordinal : Int
  row_contract_cid : String
}

///|
priv struct ClientResultProjectionField {
  name : String
  value_contract_cid : String
}

///|
pub(all) enum ClientResultPlanIssue {
  InvalidLimits
  MissingResult
  MissingPublication
  MismatchedPublication
  MissingProjection
  RowContract(ClientResultRowContractIssue)
  Encoding
}

///|
pub(all) enum ClientResultPlanAdmissionIssue {
  Issue(ClientResultPlanIssue)
  MismatchedPlan
}

///|
pub fn client_result_plan_wire(value : ClientResultPlanIdentity) -> String {
  value.wire
}

///|
pub fn client_result_plan_cid(value : ClientResultPlanIdentity) -> String {
  value.cid
}

///|
pub fn client_result_plan_name(value : ClientResultPlanIdentity) -> String {
  value.result_name
}

///|
pub fn client_result_plan_row_contract_cid(
  value : ClientResultPlanIdentity,
) -> String {
  value.row_contract_cid
}

///|
fn emit_client_result_plan(
  writer : @encode.Writer,
  result_name : String,
  unit_definition_cid : String,
  unit_result_name : String,
  unit_result_ordinal : Int,
  projection : Array[ClientResultProjectionField],
  order : @results.PublicationOrder,
  row_contract_cid : String,
  cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "order")
  @encode.begin_object(writer)
  @encode.key(writer, "strategy")
  let strategy = match @results.publication_strategy(order) {
    @results.Authored => "authored"
    @results.Inherited => "inherited"
    @results.CandidateKey => "candidate_key"
    @results.ProjectedFields => "projected_fields"
  }
  @encode.string_value(writer, strategy)
  @encode.key(writer, "terms")
  @encode.begin_array(writer)
  for index in 0..<@results.publication_term_count(order) {
    let term = @results.publication_term_at(order, index).unwrap()
    @encode.begin_object(writer)
    @encode.key(writer, "authored")
    @encode.bool_value(writer, @results.publication_term_authored(term))
    @encode.key(writer, "direction")
    @encode.string_value(
      writer,
      match @results.publication_term_direction(term) {
        @order.Asc => "asc"
        @order.Desc => "desc"
      },
    )
    @encode.key(writer, "field")
    @encode.string_value(
      writer,
      @schema.reference_name(@results.publication_term_field(term)),
    )
    @encode.key(writer, "nulls")
    @encode.string_value(
      writer,
      match @results.publication_term_nulls(term) {
        @order.First => "first"
        @order.Last => "last"
      },
    )
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.end_object(writer)
  @encode.key(writer, "projection")
  @encode.begin_array(writer)
  for field in projection {
    @encode.begin_object(writer)
    @encode.key(writer, "input")
    @encode.string_value(writer, field.name)
    @encode.key(writer, "output")
    @encode.string_value(writer, field.name)
    @encode.key(writer, "value_contract_cid")
    @encode.string_value(writer, field.value_contract_cid)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "result_name")
  @encode.string_value(writer, result_name)
  if cid is Some(cid) {
    @encode.key(writer, "result_plan_logical_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "typed_output_port")
  @encode.begin_object(writer)
  @encode.key(writer, "carrier")
  @encode.string_value(writer, "relation")
  @encode.key(writer, "name")
  @encode.string_value(writer, unit_result_name)
  @encode.key(writer, "row_contract_cid")
  @encode.string_value(writer, row_contract_cid)
  @encode.end_object(writer)
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.key(writer, "unit_result_name")
  @encode.string_value(writer, unit_result_name)
  @encode.key(writer, "unit_result_ordinal")
  @encode.number_value(writer, unit_result_ordinal.to_double())
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-result-plan/0.1")
  @encode.end_object(writer)
}

///|
/// Issue the public Result Plan identity from the exact checked export
/// occurrence. A graph root and physical placement remain Plan-level bindings.
pub fn issue_prepared_client_result_plan(
  value : PreparedClientProgram,
  result : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientResultPlanIdentity, ClientResultPlanIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let graph = value.graph
  guard @strategy.graph_result_task(graph, result) is Some(task) &&
    @strategy.graph_task_unit_index(graph, task) is Some(unit) &&
    @strategy.graph_result_name(graph, result) is Some(result_name) &&
    @strategy.graph_result_occurrence(graph, result) is Some(occurrence) else {
    return Err(MissingResult)
  }
  let port = @execution.managed_result_occurrence_port(occurrence)
  let order = @results.port_order(port)
  let unit_result_ordinal = @results.publication_result_index(order)
  let unit_result_name = @results.name(@results.port_result(port))
  let program = @strategy.graph_program(graph)
  guard @checked.unit_publication_at(program, unit, unit_result_ordinal)
    is Some(publication) &&
    @checked.unit_definition_cid(program, unit) is Some(unit_definition_cid) else {
    return Err(MissingPublication)
  }
  if @checked.publication_result_name(publication) != unit_result_name {
    return Err(MismatchedPublication)
  }
  let row = match
    issue_prepared_client_result_row_contract(
      value, unit, unit_result_ordinal, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(row) => row
    Err(issue) => return Err(RowContract(issue))
  }
  if client_result_row_contract_unit_cid(row) != unit_definition_cid ||
    client_result_row_contract_name(row) != unit_result_name {
    return Err(MismatchedPublication)
  }
  let projection_names = @results.fields(@results.port_result(port))
  if projection_names.length() != @results.port_projection_count(port) {
    return Err(MissingProjection)
  }
  let projection : Array[ClientResultProjectionField] = []
  let schema = @results.port_schema(port)
  for name in projection_names {
    let mut found = None
    for index in 0..<@results.port_projection_count(port) {
      if @results.port_projection_input_at(port, index) is Some(input) &&
        @schema.reference_name(input) == name {
        if found is Some(_) {
          return Err(MissingProjection)
        }
        found = Some(input)
      }
    }
    guard found is Some(input) &&
      @schema.lookup(schema, input) is Some(contract) else {
      return Err(MissingProjection)
    }
    let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
      _ => return Err(Encoding)
    }
    @contract.emit_checked(contract, hash) catch {
      _ => return Err(Encoding)
    }
    let value_contract_cid = "sha256:" +
      (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
    projection.push({ name, value_contract_cid, })
  }
  let row_contract_cid = client_result_row_contract_cid(row)
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_result_plan(
    hash,
    result_name,
    unit_definition_cid,
    unit_result_name,
    unit_result_ordinal,
    projection,
    order,
    row_contract_cid,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_result_plan(
    writer,
    result_name,
    unit_definition_cid,
    unit_result_name,
    unit_result_ordinal,
    projection,
    order,
    row_contract_cid,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({
    wire,
    cid,
    result_name,
    unit_definition_cid,
    unit_result_name,
    unit_result_ordinal,
    row_contract_cid,
  })
}

///|
/// Recheck a saved Result Plan against the checked export occurrence.
/// Lookup never reopens a physical Compute or delivery attempt.
pub fn admit_prepared_client_result_plan(
  value : PreparedClientProgram,
  result : Int,
  saved_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientResultPlanIdentity, ClientResultPlanAdmissionIssue] {
  let issued = match
    issue_prepared_client_result_plan(
      value, result, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(Issue(issue))
  }
  if saved_wire != issued.wire {
    return Err(MismatchedPlan)
  }
  Ok(issued)
}
