///|
/// Emit only the admitted source reference and checked row type using the
/// existing schema-only snapshot shape. Materialization, completeness and
/// integration evidence are excluded. This does not establish source ownership
/// or complete a Unit contract selection; those checks belong to the caller.
pub fn emit_type_projection(
  value : Snapshot,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_static_projection(value, writer, false)
}

///|
/// Static score semantics and row type, excluding every observation claim.
pub fn emit_score_projection(
  value : Snapshot,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_static_projection(value, writer, true)
}

///|
fn emit_static_projection(
  value : Snapshot,
  writer : @encode.Writer,
  scores : Bool,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "output_carrier")
  @encode.string_value(writer, "relation")
  @encode.key(writer, "schema")
  @contract.emit_checked(value.contract, writer)
  if scores {
    emit_scores(value, writer)
  }
  @encode.key(writer, "source_ref")
  @encode.string_value(writer, @reference.stringify(value.reference))
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-input-schema/0.1")
  @encode.end_object(writer)
}
