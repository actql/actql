///|
pub(all) enum ClientPublicationBindingIssue {
  MissingPublication
  MismatchedCheckedLimit
  Encoding
} derive(Eq, Debug)

///|
fn emit_client_publication_binding(
  writer : @encode.Writer,
  unit_definition_cid : String,
  result_name : String,
  measure : String,
  subject : String,
  effective_max : Int64,
  resolved_limit_cid : String,
  binding_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if binding_cid is Some(cid) {
    @encode.key(writer, "binding_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "effective_max")
  @encode.number_value(writer, effective_max.to_double())
  @encode.key(writer, "resolved_limit_cid")
  @encode.string_value(writer, resolved_limit_cid)
  @encode.key(writer, "subject_ref")
  @encode.string_value(writer, subject)
  @encode.key(writer, "target")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "result_publication")
  @encode.key(writer, "measure")
  @encode.string_value(writer, measure)
  @encode.key(writer, "result_name")
  @encode.string_value(writer, result_name)
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.end_object(writer)
  @encode.key(writer, "unit")
  @encode.string_value(writer, measure)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-execution-limit-binding/0.1")
  @encode.end_object(writer)
}

///|
/// Issue one private Plan limit binding from the checked Unit Result port and
/// its owner-issued resolved limit. A matching number alone is insufficient.
pub fn emit_prepared_client_publication_binding(
  value : PreparedClientProgram,
  unit : Int,
  index : Int,
  scope : ClientPublicationLimitScope,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientPublicationBindingIssue] {
  let program = @strategy.graph_program(value.graph)
  guard @checked.unit_publication_at(program, unit, index) is Some(publication) &&
    @checked.unit_definition_cid(program, unit) is Some(unit_definition_cid) else {
    return Err(MissingPublication)
  }
  let result_name = @checked.publication_result_name(publication)
  let (claim, measure, expected_unit) = match scope {
    Rows => (@checked.publication_rows(publication), "rows", @arithmetic.Rows)
    Bytes =>
      (@checked.publication_bytes(publication), "bytes", @arithmetic.Bytes)
  }
  let token = result_name.replace(old="~", new="~0").replace(old="/", new="~1")
  let subject = "unit:" +
    unit_definition_cid +
    "#/results/" +
    token +
    "/" +
    measure
  if @capacity.limit_subject(claim) != subject ||
    @capacity.limit_enforcement(claim) != @capacity.EngineAtomic ||
    @arithmetic.minimum_unit(@capacity.limit_minimum(claim)) != expected_unit {
    return Err(MismatchedCheckedLimit)
  }
  let effective_max = @arithmetic.minimum_value(@capacity.limit_minimum(claim))
  let resolved_limit_cid = @capacity.limit_cid(claim)
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_publication_binding(
    hash,
    unit_definition_cid,
    result_name,
    measure,
    subject,
    effective_max,
    resolved_limit_cid,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let binding_cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_publication_binding(
    writer,
    unit_definition_cid,
    result_name,
    measure,
    subject,
    effective_max,
    resolved_limit_cid,
    Some(binding_cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(body)
}
