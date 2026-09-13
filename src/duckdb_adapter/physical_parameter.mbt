///|
/// Exact scalar transport from an already admitted value. This handle carries
/// no source permission, acquisition evidence or successful Compute claim.
struct PhysicalParameter {
  id : String
  decimal : (Int, Int)?
  value : ParameterValue
}

///|
priv enum ParameterValue {
  Admitted(@admitted.Value)
  ScalarNumber(Double)
  ScalarBoolean(Bool)
  ScalarText(String)
  Null
}

///|
fn parameter_type(
  contract : @contract.Contract,
) -> Result[(String, (Int, Int)?), ValueIssue] {
  match contract.shape {
    @contract.Boolean => Ok(("BOOLEAN", None))
    @contract.Text(_) => Ok(("VARCHAR", None))
    @contract.Number => Ok(("DOUBLE", None))
    @contract.Date => Ok(("DATE", None))
    @contract.Timestamp => Ok(("TIMESTAMP_TZ", None))
    @contract.Decimal(precision~, scale~) =>
      Ok(("DECIMAL", Some((precision, scale))))
    _ => Err(UnsupportedType)
  }
}

///|
pub fn prepare_physical_parameter(
  checked : @admitted.CheckedValue,
) -> Result[PhysicalParameter, ValueIssue] {
  let (id, decimal) = match parameter_type(checked.contract) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ id, decimal, value: Admitted(checked.value), })
}

///|
/// Read one exact receiving cell from a bound immutable producer. This does not
/// repeat admission or grant receiving execution/guard credits. The caller must
/// account for import and transport independently of the producer's completion.
pub fn prepare_producer_parameter(
  input : @execution.ProducerRead,
  row : Int,
  column : Int,
) -> Result[PhysicalParameter, ValueIssue] {
  guard @schema.field_at(@execution.producer_read_schema(input), column)
    is Some(field) else {
    return Err(OutOfRange)
  }
  let (id, decimal) = match parameter_type(field.contract) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @execution.producer_read_cell(input, row, column) is Some(cell) else {
    return Err(OutOfRange)
  }
  let value = match cell {
    @execution.Null => Null
    @execution.Number(value) => ScalarNumber(value)
    @execution.Boolean(value) => ScalarBoolean(value)
    @execution.Text(value) => ScalarText(value)
    @execution.Captured(value) => Admitted(value)
  }
  Ok({ id, decimal, value, })
}

///|
fn fixed_digits(text : String, start : Int, end : Int) -> Int {
  let mut value = 0
  for i in start..<end {
    value = value * 10 + text[i].to_int() - 48
  }
  value
}

///|
// Only called for the immutable Gregorian text admitted by value_admission.
fn admitted_date_days(text : String) -> Int {
  let year = fixed_digits(text, 0, 4)
  let month = fixed_digits(text, 5, 7)
  let day = fixed_digits(text, 8, 10)
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let lengths = [
    31,
    if leap {
      29
    } else {
      28
    },
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ]
  let mut days = year_start(year) + day - 1
  for i in 0..<(month - 1) {
    days += lengths[i]
  }
  days
}

///|
fn admitted_timestamp_micros(text : String) -> Int64 {
  let days = admitted_date_days(text).to_int64()
  let within = fixed_digits(text, 11, 13) * 3600000 +
    fixed_digits(text, 14, 16) * 60000 +
    fixed_digits(text, 17, 19) * 1000 +
    fixed_digits(text, 20, 23)
  (days * 86400000L + within.to_int64()) * 1000L
}

///|
fn double_bits_text(number : Double) -> String {
  let bits = number.reinterpret_as_uint64()
  let digits = "0123456789abcdef"
  let builder = StringBuilder()
  for i in 0..<16 {
    let digit = ((bits >> ((15 - i) * 4)) & 15UL).to_int()
    builder.write_char(digits[digit].to_int().unsafe_to_char())
  }
  builder.to_string()
}

///|
/// Emit one prepared parameter in the private Node adapter format. The caller's
/// bounded writer counts transport construction; it is not a logical-work credit.
pub fn emit_physical_parameter(
  parameter : PhysicalParameter,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(output)
  @encode.key(output, "type")
  @encode.begin_object(output)
  @encode.key(output, "id")
  @encode.string_value(output, parameter.id)
  if parameter.decimal is Some((precision, scale)) {
    @encode.key(output, "precision")
    @encode.number_value(output, precision.to_double())
    @encode.key(output, "scale")
    @encode.number_value(output, scale.to_double())
  }
  @encode.end_object(output)
  @encode.key(output, "value")
  match parameter.value {
    Null => @encode.null_value(output)
    ScalarNumber(value) => @encode.string_value(output, double_bits_text(value))
    ScalarBoolean(value) => @encode.bool_value(output, value)
    ScalarText(value) => @encode.string_value(output, value)
    Admitted(value) =>
      match value {
        @admitted.Null => @encode.null_value(output)
        @admitted.Boolean(value) => @encode.bool_value(output, value)
        @admitted.Text(value) => @encode.string_value(output, value)
        @admitted.Number(value) =>
          @encode.string_value(output, double_bits_text(value))
        @admitted.Decimal(value) =>
          @encode.string_value(output, value.coefficient)
        @admitted.Date(value) =>
          @encode.string_value(output, admitted_date_days(value).to_string())
        @admitted.Timestamp(value) =>
          @encode.string_value(
            output,
            admitted_timestamp_micros(value).to_string(),
          )
        _ => raise @encode.InvalidStructure
      }
  }
  @encode.end_object(output)
}
