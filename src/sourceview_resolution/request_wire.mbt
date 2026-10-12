///|
pub(all) enum RequestWireIssue {
  UnboundHostBinding
  Encoding(@encode.EncodeFailure)
} derive(Debug)

///|
/// Encode the exact typed Request whose parameters have already been bound by
/// this owner. This does not issue references or grant provider I/O authority.
/// The acquisition caller reserves the overlapping wire before calling here.
pub fn parameterized_request_wire(
  request : ParameterizedRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RequestWireIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    issue => return Err(Encoding(issue))
  }
  try {
    @encode.begin_object(writer)
    for field in request.fields {
      @encode.key(writer, field.field.slot.field_name)
      match field.value {
        CheckedLiteral(value) => @value.emit_checked_wire_value(value, writer)
        BoundParameter(parameter) =>
          @value.emit_checked_wire_value(parameter.value, writer)
        UnboundHostBinding(_) => {
          @encode.cancel_writer(writer)
          return Err(UnboundHostBinding)
        }
      }
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    issue => {
      @encode.cancel_writer(writer)
      Err(Encoding(issue))
    }
  }
}
