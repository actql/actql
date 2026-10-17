///|
/// The provider native kinds whose numeric values use a described Decimal.
fn described_decimal_type(native_type : String) -> Bool {
  native_type == "double" ||
  native_type == "currency" ||
  native_type == "percent"
}

///|
/// The ActQL `decimal(P,S)` from the original described precision and scale.
/// The existing Decimal Owner supplies the supported domain. Read and write
/// preserve number text without binary64, currency conversion or percent
/// scaling; neither recovers precision lost before the provider reply.
fn described_decimal(field : FieldMetadata) -> (Int, Int)? {
  guard described_decimal_type(field.native_type) &&
    field.precision is Some(precision) &&
    field.scale is Some(scale) &&
    @contract.decimal_contract(precision, scale, nullable=field.nullable)
    is Some(_) else {
    return None
  }
  Some((precision, scale))
}

///|
/// Why a number is not a value of `decimal(P,S)`.
priv enum DecimalIssue {
  /// Not a JSON number or canonical decimal text.
  DecimalFormat
  /// More integer digits than P − S.
  DecimalRange
  /// A nonzero digit beyond scale S.
  DecimalScale
}

///|
/// The same provider number-text conversion through the Common Decimal Owner.
/// The exact source lexeme was already bounded by the query body's limits.
fn json_number_decimal(
  lexeme : String,
  precision : Int,
  scale : Int,
) -> Result[String, DecimalIssue] {
  match
    @admitted.normalize_decimal_text(
      lexeme,
      precision,
      scale,
      lexeme.length().max(1),
    ) {
    Ok(value) => Ok(value)
    Err(
      @admitted.InvalidFormat
      | @admitted.InvalidLimits
      | @admitted.InputLimit
    ) => Err(DecimalFormat)
    Err(@admitted.OutOfRange) => Err(DecimalRange)
    Err(@admitted.BeyondScale) => Err(DecimalScale)
  }
}

///|
/// Why an approved decimal value is refused before it is sent: it must be
/// the ActQL canonical spelling of a `decimal(P,S)` value.
fn decimal_write_issue(
  text : String,
  precision : Int,
  scale : Int,
  field : String,
) -> WriteBodyIssue? {
  match json_number_decimal(text, precision, scale) {
    Ok(canonical) if canonical == text => None
    Ok(_) | Err(DecimalFormat) => Some(InvalidValue(field))
    Err(DecimalRange) => Some(ValueOutOfRange(field))
    Err(DecimalScale) => Some(ValueBeyondScale(field))
  }
}

///|
/// The exact JSON text of the value at `cursor`, from the bytes it was
/// parsed from.
fn source_lexeme(source : Bytes, cursor : @decode.Cursor) -> String? {
  let span = @decode.cursor_span(cursor)
  if span.start_byte < 0 ||
    span.end_byte > source.length() ||
    span.start_byte >= span.end_byte {
    return None
  }
  let text = StringBuilder()
  for index in span.start_byte..<span.end_byte {
    let byte = source[index]
    if byte >= 128 {
      return None
    }
    text.write_char(byte.to_int().unsafe_to_char())
  }
  Some(text.to_string())
}
