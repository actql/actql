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
  parameterized_request_document(request, max_bytes, max_nodes, max_depth).map(
    @encode.document_text,
  )
}

///|
/// The same typed Request writer, retaining its exact measured document for
/// downstream dependency custody. No JSON reparse, field admission or new
/// Request is performed after the original checked binding.
pub fn parameterized_request_document(
  request : ParameterizedRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodedDocument, RequestWireIssue] {
  bound_request_fields_document(request.fields, max_bytes, max_nodes, max_depth)
}

///|
/// The keyed template's actual static fields, excluding its correlation roles.
/// The same checked field writer is used by ordinary requests; no key tuple,
/// request value, Host binding or capability is fabricated for this projection.
pub fn parameterized_keyed_static_request_wire(
  request : ParameterizedKeyedRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RequestWireIssue] {
  parameterized_keyed_static_request_document(
    request, max_bytes, max_nodes, max_depth,
  ).map(@encode.document_text)
}

///|
/// The same original static Request writer, retaining measured document facts
/// so a transport can embed it without a second field/Ref traversal.
pub fn parameterized_keyed_static_request_document(
  request : ParameterizedKeyedRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodedDocument, RequestWireIssue] {
  let fields = request.fields.copy()
  fields.sort_by((a, b) => {
    @unicode.compare_utf16(a.field.slot.field_name, b.field.slot.field_name)
  })
  bound_request_fields_document(fields, max_bytes, max_nodes, max_depth)
}

///|
fn bound_request_fields_document(
  fields : Array[ParameterizedRequestField],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodedDocument, RequestWireIssue] {
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    issue => return Err(Encoding(issue))
  }
  try {
    @encode.begin_object(writer)
    for field in fields {
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
    Ok(@encode.finish_document(writer))
  } catch {
    issue => {
      @encode.cancel_writer(writer)
      Err(Encoding(issue))
    }
  }
}
