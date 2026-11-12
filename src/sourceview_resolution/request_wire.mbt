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
/// Canonical publication preimage of the SAME typed bound Request. Transport
/// spelling and original field/binding indices remain unchanged. The caller
/// funds one temporary field-reference array when there is more than one field.
pub fn parameterized_request_canonical_document(
  request : ParameterizedRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodedDocument, RequestWireIssue] {
  canonical_request_fields_document(
    request.fields,
    max_bytes,
    max_nodes,
    max_depth,
  )
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
  canonical_request_fields_document(
    request.fields,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn canonical_request_fields_document(
  original : Array[ParameterizedRequestField],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodedDocument, RequestWireIssue] {
  bound_request_fields_document(
    canonical_request_fields(original),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn canonical_request_fields(
  original : Array[ParameterizedRequestField],
) -> Array[ParameterizedRequestField] {
  if original.length() < 2 {
    return original
  }
  let fields = original.copy()
  fields.sort_by((a, b) => {
    @unicode.compare_utf16(a.field.slot.field_name, b.field.slot.field_name)
  })
  fields
}

///|
/// Measure the SAME typed canonical Request emitter before constructing its
/// publication document. No wire, parse tree, hash, authority or bound is
/// issued from these facts. Fixed measurement/field controls use the existing
/// checked-input allowance; the caller funds the variable document separately.
pub fn parameterized_request_canonical_geometry(
  request : ParameterizedRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@encode.EncodingConstructionGeometry, RequestWireIssue] {
  let writer = @encode.construction_measuring_writer(
    max_bytes, max_nodes, max_depth,
  ) catch {
    issue => return Err(Encoding(issue))
  }
  match
    emit_bound_request_fields(canonical_request_fields(request.fields), writer) {
    Err(issue) => {
      @encode.cancel_writer(writer)
      return Err(issue)
    }
    Ok(_) => ()
  }
  let geometry = @encode.finish_construction_measurement(writer) catch {
    issue => {
      @encode.cancel_writer(writer)
      return Err(Encoding(issue))
    }
  }
  Ok(geometry)
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
  match emit_bound_request_fields(fields, writer) {
    Err(issue) => {
      @encode.cancel_writer(writer)
      return Err(issue)
    }
    Ok(_) => ()
  }
  let document = @encode.finish_document(writer) catch {
    issue => {
      @encode.cancel_writer(writer)
      return Err(Encoding(issue))
    }
  }
  Ok(document)
}

///|
fn emit_bound_request_fields(
  fields : Array[ParameterizedRequestField],
  writer : @encode.Writer,
) -> Result[Unit, RequestWireIssue] {
  try {
    @encode.begin_object(writer)
    for field in fields {
      @encode.key(writer, field.field.slot.field_name)
      match field.value {
        CheckedLiteral(value) => @value.emit_checked_wire_value(value, writer)
        BoundParameter(parameter) =>
          @value.emit_checked_wire_value(parameter.value, writer)
        UnboundHostBinding(_) => return Err(UnboundHostBinding)
      }
    }
    @encode.end_object(writer)
    Ok(())
  } catch {
    issue => Err(Encoding(issue))
  }
}
