///|
/// DuckDB adapter types, not additions to the common Carrier or value contract.
pub(all) enum PhysicalType {
  Boolean
  Varchar
  Integer(bits~ : Int, signed~ : Bool)
  Float32
  Float64
  Decimal(precision~ : Int, scale~ : Int)
  Date
  TimestampTZ
  NaiveTimestamp
} derive(Eq, Debug)

///|
struct ValueMapping {
  physical : PhysicalType
  contract : @contract.Contract
}

///|
pub(all) enum ValueIssue {
  InvalidLimits
  UnsupportedType
  TypeMismatch
  InvalidPhysicalValue
  LossyInteger
  LossyTimestamp
  ImplicitTimezone
  OutOfRange
  Decode(@decode.Issue)
  Admission(@admitted.Issue)
} derive(Eq, Debug)

///|
/// Match types before reading data, including empty and all-NULL results.
/// Transport support is not evidence of native predicate support.
pub fn prepare_value_mapping(
  physical : PhysicalType,
  contract : @contract.Contract,
) -> Result[ValueMapping, ValueIssue] {
  match physical {
    NaiveTimestamp => return Err(ImplicitTimezone)
    Integer(bits~, ..) =>
      if ![8, 16, 32, 64, 128].contains(bits) {
        return Err(UnsupportedType)
      }
    Decimal(precision~, scale~) =>
      if precision < 1 || precision > 38 || scale < 0 || scale > precision {
        return Err(UnsupportedType)
      }
    _ => ()
  }
  let matches = match (physical, contract.shape) {
    (Boolean, @contract.Boolean)
    | (Varchar, @contract.Text(_))
    | (Integer(..), @contract.Number)
    | (Float32, @contract.Number)
    | (Float64, @contract.Number)
    | (Date, @contract.Date)
    | (TimestampTZ, @contract.Timestamp) => true
    (Decimal(precision~, scale~), @contract.Decimal(precision=p, scale=s)) =>
      precision == p && scale == s
    _ => false
  }
  if !matches {
    return Err(TypeMismatch)
  }
  Ok({ physical, contract, })
}
