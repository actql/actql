///|
/// Decode the private Node transport descriptor, not a shared wire contract.
/// In particular, naive timestamps stay distinguishable and cannot acquire a
/// timezone by passing through the descriptor decoder.
pub fn decode_physical_type(
  cursor : @decode.Cursor,
) -> Result[PhysicalType, ValueIssue] {
  let object = match @decode.open_object(cursor) {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let id_cursor = match @decode.required(object, "id") {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let id = match @decode.text(id_cursor) {
    Ok(value) => value
    Err(issue) => return Err(Decode(issue))
  }
  let fields = if id == "DECIMAL" {
    ["id", "precision", "scale"]
  } else {
    ["id"]
  }
  match @decode.closed_object(cursor, fields) {
    Ok(_) => ()
    Err(issue) => return Err(Decode(issue))
  }
  let physical = match id {
    "BOOLEAN" => Boolean
    "VARCHAR" => Varchar
    "TINYINT" => Integer(bits=8, signed=true)
    "SMALLINT" => Integer(bits=16, signed=true)
    "INTEGER" => Integer(bits=32, signed=true)
    "BIGINT" => Integer(bits=64, signed=true)
    "HUGEINT" => Integer(bits=128, signed=true)
    "UTINYINT" => Integer(bits=8, signed=false)
    "USMALLINT" => Integer(bits=16, signed=false)
    "UINTEGER" => Integer(bits=32, signed=false)
    "UBIGINT" => Integer(bits=64, signed=false)
    "UHUGEINT" => Integer(bits=128, signed=false)
    "FLOAT" => Float32
    "DOUBLE" => Float64
    "DATE" => Date
    "TIMESTAMP_TZ" => TimestampTZ
    "TIMESTAMP" | "TIMESTAMP_S" | "TIMESTAMP_MS" | "TIMESTAMP_NS" =>
      NaiveTimestamp
    "DECIMAL" => {
      let precision = match @decode.required(object, "precision") {
        Ok(value) =>
          match @decode.int32(value) {
            Ok(value) => value
            Err(issue) => return Err(Decode(issue))
          }
        Err(issue) => return Err(Decode(issue))
      }
      let scale = match @decode.required(object, "scale") {
        Ok(value) =>
          match @decode.int32(value) {
            Ok(value) => value
            Err(issue) => return Err(Decode(issue))
          }
        Err(issue) => return Err(Decode(issue))
      }
      if precision < 1 || precision > 38 || scale < 0 || scale > precision {
        return Err(InvalidPhysicalValue)
      }
      Decimal(precision~, scale~)
    }
    _ => return Err(UnsupportedType)
  }
  Ok(physical)
}
