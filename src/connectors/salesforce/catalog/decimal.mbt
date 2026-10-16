///|
/// The largest described precision this revision declares as
/// `decimal(P,S)`. It is a chosen support range, not a proof that the value
/// Salesforce holds is recovered: a value written through the API or Apex
/// can carry more fractional digits than the field defines, and its
/// precision may already have been lost before the reply. What the
/// connector guarantees is only this: a read admits the value the reply's
/// number text denotes, without rounding, and a write sends JSON whose
/// number denotes the approved decimal. Neither step computes the value
/// through binary64.
const MAX_EXACT_DOUBLE_PRECISION : Int = 15

///|
/// The ActQL `decimal(P,S)` a Salesforce Number (`double`) field is declared
/// as, from its described precision and scale, or none.
fn double_decimal(field : FieldMetadata) -> (Int, Int)? {
  guard field.native_type == "double" &&
    field.precision is Some(precision) &&
    field.scale is Some(scale) &&
    precision >= 1 &&
    precision <= MAX_EXACT_DOUBLE_PRECISION &&
    scale >= 0 &&
    scale <= precision else {
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
