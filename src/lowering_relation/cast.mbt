///|
/// The target is projected from the checker-owned result contract. Nullable
/// belongs to that result contract, never to the canonical CAST target body.
fn emit_cast_target(
  contract : @contract.Contract,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(output)
  let kind = match contract.shape {
    Number => "number"
    Text(_) => "string"
    Boolean => "boolean"
    Timestamp => "timestamp"
    Decimal(precision~, scale~) => {
      @encode.key(output, "precision")
      @encode.number_value(output, precision.to_double())
      @encode.key(output, "scale")
      @encode.number_value(output, scale.to_double())
      "decimal"
    }
    _ => raise @encode.InvalidStructure
  }
  @encode.key(output, "type")
  @encode.string_value(output, kind)
  @encode.end_object(output)
}
