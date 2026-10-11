///|
pub(all) enum ClientAuthoringContextIssue {
  Encoding
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
priv struct ClientAnnotation {
  kind : String
  path : String
  name : String?
  meta : @decode.Cursor
}

///|
fn client_annotation_path(
  parent : String,
  key : String,
  max_bytes : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.writer(max_bytes, 1, 0)
  @encode.string_value(writer, key)
  parent + "[" + @encode.finish(writer) + "]"
}

///|
fn client_annotation(
  items : Array[ClientAnnotation],
  node : @decode.Cursor,
  kind : String,
  path : String,
  name : String?,
) -> Unit {
  guard @decode.open_object(node) is Ok(object) &&
    @decode.lookup(object, "meta") is Some(meta) else {
    return
  }
  items.push({ kind, path, name, meta, })
}

///|
fn client_declaration_annotations(
  items : Array[ClientAnnotation],
  node : @decode.Cursor,
  parent : String,
  field : String,
  kind : String,
  max_bytes : Int,
) -> Unit raise @encode.EncodeFailure {
  guard @decode.open_object(node) is Ok(object) &&
    @decode.lookup(object, field) is Some(declarations) &&
    @decode.object_length(declarations) is Some(count) else {
    return
  }
  let path = client_annotation_path(parent, field, max_bytes)
  for i in 0..<count {
    let (name, declaration) = @decode.field_at(declarations, i).unwrap()
    client_annotation(
      items,
      declaration,
      kind,
      client_annotation_path(path, name, max_bytes),
      Some(name),
    )
  }
}

///|
/// Extract only grammar-owned annotations from the original prepared source.
/// Business values named meta remain opaque. This sidecar grants no execution
/// or publication authority and does not substitute the normalization journal.
pub fn issue_prepared_client_authoring_context(
  owner : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientAuthoringContextIssue] {
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let body = try {
    let items : Array[ClientAnnotation] = []
    let root = @syntax.program_body(owner.source)
    client_annotation(items, root, "program", "$", Some(owner.source.id))
    for
      (field, kind) in [
        ("params", "parameter"),
        ("bindings", "binding"),
        ("results", "result"),
      ] {
      client_declaration_annotations(
        items, root, "$", field, kind, max_wire_bytes,
      )
    }
    for i, stage in @syntax.stages(owner.source) {
      let node = @syntax.stage_body(stage)
      let path = "$[\"stages\"][" + i.to_string() + "]"
      client_annotation(items, node, "stage", path, Some(stage.id))
      for
        (field, kind) in [
          ("inputs", "input"),
          ("results", "result"),
          ("effects", "effect"),
        ] {
        client_declaration_annotations(
          items, node, path, field, kind, max_wire_bytes,
        )
      }
      let object = @decode.open_object(node).unwrap()
      if @decode.lookup(object, "steps") is Some(steps) &&
        @decode.array_length(steps) is Some(count) {
        for j in 0..<count {
          let step = @decode.element_at(steps, j).unwrap()
          let name = match @decode.open_object(step) {
            Ok(object) =>
              match @decode.lookup(object, "as") {
                Some(value) =>
                  match @decode.text(value) {
                    Ok(name) => Some(name)
                    Err(_) => None
                  }
                None => None
              }
            Err(_) => None
          }
          client_annotation(
            items,
            step,
            "step",
            path + "[\"steps\"][" + j.to_string() + "]",
            name,
          )
        }
      }
    }
    items.sort_by((left, right) => {
      @canonical_value.compare_utf16(left.path, right.path)
    })
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-authoring-context/0.1")
    @encode.key(writer, "program_definition_cid")
    @encode.string_value(
      writer,
      prepared_client_identity(owner).program_definition_cid,
    )
    @encode.key(writer, "annotations")
    @encode.begin_array(writer)
    for item in items {
      @encode.begin_object(writer)
      @encode.key(writer, "target")
      @encode.begin_object(writer)
      @encode.key(writer, "kind")
      @encode.string_value(writer, item.kind)
      @encode.key(writer, "source_path")
      @encode.string_value(writer, item.path)
      if item.name is Some(name) {
        @encode.key(writer, "name")
        @encode.string_value(writer, name)
      }
      @encode.end_object(writer)
      @encode.key(writer, "meta")
      @syntax.emit_admitted_source_value(item.meta, writer)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  @publication.seal_run_evidence_value(
    "authoring_context", body, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}
