///|
/// Measure the same original request over held canonical subtrees before
/// allocating its transport String. Callers fund the measurement controls.
pub fn measure_client_effect_file_request(
  binding : String,
  mapping : String,
  target : @canonical.CanonicalValue,
  value : @canonical.CanonicalValue?,
  before : @canonical.CanonicalValue,
  version : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Int, Int, Int), Unit] {
  try {
    let writer = @encode.measuring_writer(max_bytes, max_nodes, max_depth)
    emit_client_effect_file_request(
      writer, binding, mapping, target, value, before, version,
    )
    Ok(@encode.finish_measurement_usage(writer))
  } catch {
    _ => Err(())
  }
}

///|
/// The canonical file request has a value for UPDATE and omits it for DELETE.
/// Warm and saved callers share the writer and back it before entry.
pub fn client_effect_file_request_wire(
  binding : String,
  mapping : String,
  target : @canonical.CanonicalValue,
  value : @canonical.CanonicalValue?,
  before : @canonical.CanonicalValue,
  version : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, Unit] {
  try {
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_client_effect_file_request(
      writer, binding, mapping, target, value, before, version,
    )
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(())
  }
}

///|
/// Compose an UPDATE from the original typed target and checked change
/// documents. The caller keeps the selected Mapping and row version in
/// custody. This function emits DATA only, with no approval or write claim.
pub fn emit_client_effect_file_update(
  writer : @encode.Writer,
  binding : String,
  mapping : String,
  target : String,
  changes : @encode.EncodedDocument,
  before : @encode.EncodedDocument,
  version : String,
) -> Unit raise @encode.EncodeFailure {
  emit_client_effect_file_request_body(
    writer,
    binding,
    mapping,
    target,
    Some(changes),
    before,
    version,
    emit_client_effect_file_target_text,
    emit_client_effect_file_document,
  )
}

///|
fn emit_client_effect_file_target_text(
  value : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.string_value(writer, value)
}

///|
fn emit_client_effect_file_document(
  value : @encode.EncodedDocument,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.emit_document(writer, value)
}

///|
// One protocol body for measurement and emission. Original canonical subtrees
// remain borrowed; measuring cannot issue a request, CID, grant or text body.
fn emit_client_effect_file_request(
  writer : @encode.Writer,
  binding : String,
  mapping : String,
  target : @canonical.CanonicalValue,
  value : @canonical.CanonicalValue?,
  before : @canonical.CanonicalValue,
  version : String,
) -> Unit raise @encode.EncodeFailure {
  emit_client_effect_file_request_body(
    writer, binding, mapping, target, value, before, version, @canonical.emit_value,
    @canonical.emit_value,
  )
}

///|
// Physical framing and field order belong to this single request encoder.
fn[T, B] emit_client_effect_file_request_body(
  writer : @encode.Writer,
  binding : String,
  mapping : String,
  target : T,
  changes : B?,
  before : B,
  version : String,
  emit_target : (T, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  emit_body : (B, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "before")
  emit_body(before, writer)
  @encode.key(writer, "binding")
  @encode.string_value(writer, binding)
  @encode.key(writer, "mapping")
  @encode.string_value(writer, mapping)
  @encode.key(writer, "target")
  emit_target(target, writer)
  if changes is Some(value) {
    @encode.key(writer, "value")
    emit_body(value, writer)
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, version)
  @encode.end_object(writer)
}
