///|
/// Run-bound identity of one exact checked Program Result occurrence.
/// Construction normalizes nothing on behalf of a caller: the checked Result
/// name must already be in canonical text form.
struct ResultDefinition {
  program_definition_cid : String
  result_name : String
  result_definition_cid : String
  max_wire_bytes : Int
}

///|
pub(all) enum ResultDefinitionIssue {
  InvalidProgramDefinitionCid
  EmptyResultName
  NonCanonicalResultName
  ResultNameLimit
  Encoding
} derive(Eq, Debug)

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn emit_result_definition_body(
  program_definition_cid : String,
  result_name : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "program_definition_cid")
  @encode.string_value(writer, program_definition_cid)
  @encode.key(writer, "result_name")
  @encode.string_value(writer, result_name)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-result-definition/0.1")
  @encode.end_object(writer)
}

///|
fn emit_result_definition(
  definition : ResultDefinition,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "program_definition_cid")
  @encode.string_value(writer, definition.program_definition_cid)
  @encode.key(writer, "result_definition_cid")
  @encode.string_value(writer, definition.result_definition_cid)
  @encode.key(writer, "result_name")
  @encode.string_value(writer, definition.result_name)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-result-definition/0.1")
  @encode.end_object(writer)
}

///|
/// Seal the exact 0.1 Result Definition. The bound is derived from the already
/// checked metadata and covers worst-case JSON escaping without allocating a
/// second unbounded representation.
pub fn prepare_result_definition(
  program_definition_cid : String,
  result_name : String,
) -> Result[ResultDefinition, ResultDefinitionIssue] {
  if !valid_cid(program_definition_cid) {
    return Err(InvalidProgramDefinitionCid)
  }
  if result_name.is_empty() {
    return Err(EmptyResultName)
  }
  let canonical_name = match @canonical.normalize_nfc_lf(result_name) {
    Ok(value) => value
    Err(_) => return Err(NonCanonicalResultName)
  }
  if canonical_name != result_name {
    return Err(NonCanonicalResultName)
  }
  // A JSON string uses at most six bytes per UTF-16 unit. The fixed allowance
  // covers keys, punctuation, version, both 71-byte CIDs, and delimiters.
  if result_name.length() > (2147483647 - 512) / 6 {
    return Err(ResultNameLimit)
  }
  let max_wire_bytes = result_name.length() * 6 + 512
  let writer = @encode.hashing_writer(max_wire_bytes, 4, 1) catch {
    _ => return Err(Encoding)
  }
  emit_result_definition_body(program_definition_cid, result_name, writer) catch {
    _ => return Err(Encoding)
  }
  let digest = @encode.finish_hash(writer) catch { _ => return Err(Encoding) }
  Ok({
    program_definition_cid,
    result_name,
    result_definition_cid: "sha256:" + digest,
    max_wire_bytes,
  })
}

///|
pub fn result_definition_program_cid(definition : ResultDefinition) -> String {
  definition.program_definition_cid
}

///|
pub fn result_definition_name(definition : ResultDefinition) -> String {
  definition.result_name
}

///|
pub fn result_definition_cid(definition : ResultDefinition) -> String {
  definition.result_definition_cid
}

///|
/// Canonical complete body for a representation adapter. Identity and schema
/// decisions have already been made; this is not a second contract encoder.
pub fn result_definition_json(
  definition : ResultDefinition,
) -> Result[String, ResultDefinitionIssue] {
  let writer = @encode.writer(definition.max_wire_bytes, 5, 1) catch {
    _ => return Err(Encoding)
  }
  emit_result_definition(definition, writer) catch {
    _ => return Err(Encoding)
  }
  Ok(@encode.finish(writer)) catch {
    _ => Err(Encoding)
  }
}
