///|
/// Bounded value encoding for existing Local read evidence. These values and
/// their canonical bytes are metadata, never an Account decision or a grant.
pub(all) enum ClientLocalReadEvidenceValue {
  Text(String)
  Quantity(Int)
  Texts(Array[String])
  AllowedReads(String)
}

///|
pub(all) enum ClientLocalReadPreimageIssue {
  CapacityExceeded
  Encoding
} derive(Eq, Debug)

///|
/// Preserve the original Native 16384/256/8 envelope and canonical UTF-16 key
/// order. Native retains its selected crypto/digest and failure mapping; the
/// portable caller supplies its own distinct, typed purpose/sink originals.
pub fn encode_client_local_read_preimage(
  fields : Array[(String, ClientLocalReadEvidenceValue)],
) -> Result[String, ClientLocalReadPreimageIssue] {
  try {
    let writer = @encode.writer(16384, 256, 8)
    @encode.begin_ordered_object(writer)
    for (name, value) in fields {
      @encode.ordered_key(writer, name)
      match value {
        Text(value) => @encode.string_value(writer, value)
        Quantity(value) =>
          @encode.decimal_number_value(writer, value.to_string())
        Texts(values) => {
          @encode.begin_array(writer)
          for value in values {
            @encode.string_value(writer, value)
          }
          @encode.end_array(writer)
        }
        AllowedReads(result_name) => {
          @encode.begin_array(writer)
          for resource in ["run", "result/" + result_name] {
            @encode.begin_object(writer)
            @encode.key(writer, "operation")
            @encode.string_value(writer, "read")
            @encode.key(writer, "outcome")
            @encode.string_value(writer, "allow")
            @encode.key(writer, "resource")
            @encode.string_value(writer, resource)
            @encode.end_object(writer)
          }
          @encode.end_array(writer)
        }
      }
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}
