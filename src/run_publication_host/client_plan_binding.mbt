///|
pub(all) enum ClientPublicationBindingIssue {
  MissingPublication
  MismatchedCheckedLimit
  Encoding
} derive(Eq, Debug)

///|
fn[C] emit_client_publication_binding(
  writer : @encode.Writer,
  unit_definition_cid : String,
  result_name : String,
  measure : String,
  subject : String,
  effective_max : Int64,
  resolved_limit_cid : String,
  binding_cid : C?,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if binding_cid is Some(cid) {
    @encode.key(writer, "binding_cid")
    emit_cid(cid, writer)
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
  emit_client_publication_binding_material(
    value, unit, index, scope, max_wire_bytes, max_nodes, max_depth,
  ).map(material => material.0)
}

///|
// The original bounded emitter also retains its checked field projection.
// This is not admission of caller text. Saved bodies still use the parser.
fn emit_client_publication_binding_material(
  value : PreparedClientProgram,
  unit : Int,
  index : Int,
  scope : ClientPublicationLimitScope,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (String, ClientPublicationBindingFields?),
  ClientPublicationBindingIssue,
] {
  let (
    unit_definition_cid,
    result_name,
    measure,
    subject,
    effective_max,
    resolved_limit_cid,
  ) = match client_publication_binding_arguments(value, unit, index, scope) {
    Ok(fields) => fields
    Err(issue) => return Err(issue)
  }
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
    (value, writer) => @encode.string_value(writer, value),
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
    (value, writer) => @encode.string_value(writer, value),
  ) catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  // Preserve the saved reader's exact safe-integer domain. A wider Int64 can
  // be rendered as a Number, but cannot supply admitted binding fields.
  let fields : ClientPublicationBindingFields? = @scalar.read_safe_integer(
    effective_max.to_double(),
  ).map(decoded_max => {
    binding_cid,
    effective_max: decoded_max,
    resolved_limit_cid,
    subject_ref: subject,
    kind: "result_publication",
    measure,
    result_name,
    unit_definition_cid,
    unit: measure,
    version: "actql-execution-limit-binding/0.1",
  })
  Ok((body, fields))
}

///|
// Same typed input and exact subject checks for the real writer and its
// construction measurement. This creates neither a binding CID nor authority.
fn client_publication_binding_arguments(
  value : PreparedClientProgram,
  unit : Int,
  index : Int,
  scope : ClientPublicationLimitScope,
) -> Result[
  (String, String, String, String, Int64, String),
  ClientPublicationBindingIssue,
] {
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
  Ok(
    (
      unit_definition_cid, result_name, measure, subject, effective_max, resolved_limit_cid,
    ),
  )
}
