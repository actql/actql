///|
pub(all) enum ClientAuthoringContextIssue {
  Encoding
  ForeignOriginal
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
// The original admitted index supplies keys without a fresh ObjectView Map.
fn client_authoring_original_field(
  node : @decode.Cursor,
  key : String,
) -> @decode.Cursor? {
  for index in 0..<@decode.object_length(node).unwrap_or(0) {
    let (name, value) = @decode.field_at(node, index).unwrap()
    if name == key {
      return Some(value)
    }
  }
  None
}

///|
fn client_annotation(
  items : Array[ClientAnnotation],
  node : @decode.Cursor,
  kind : String,
  path : String,
  name : String?,
) -> Unit {
  guard client_authoring_original_field(node, "meta") is Some(meta) else {
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
  guard client_authoring_original_field(node, field) is Some(declarations) &&
    @decode.object_length(declarations) is Some(count) else {
    return
  }
  let path = client_annotation_path(parent, field, max_bytes)
  for i in 0..<count {
    let (name, declaration) = @decode.field_at(declarations, i).unwrap()
    // Unannotated declarations never construct an unused quoted-name path.
    if client_authoring_original_field(declaration, "meta") is None {
      continue
    }
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
/// The original checked source, grammar-selected annotations and one original
/// bounded Writer. This is constructor custody, never a Run or permission.
/// The caller must fund collection/path/sort plus Writer material BEFORE prepare.
struct ClientAuthoringContextPreparation {
  owner : PreparedClientProgram
  mut items : Array[ClientAnnotation]?
  mut writer : @encode.Writer?
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  mut result : Result[
    @publication.RunEvidenceValue,
    ClientAuthoringContextIssue,
  ]?
}

///|
/// Same emitter's body and final identity-bearing document geometry. These
/// quantities are construction DATA, not admitted evidence or capacity.
pub(all) struct ClientAuthoringContextConstruction {
  body : @encode.EncodingConstructionGeometry
  complete : @encode.EncodingConstructionGeometry
} derive(Eq, Debug)

///|
fn collect_client_authoring_annotations(
  owner : PreparedClientProgram,
  max_wire_bytes : Int,
) -> Array[ClientAnnotation] raise @encode.EncodeFailure {
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
    if client_authoring_original_field(node, "steps") is Some(steps) &&
      @decode.array_length(steps) is Some(count) {
      for j in 0..<count {
        let step = @decode.element_at(steps, j).unwrap()
        let name = match client_authoring_original_field(step, "as") {
          Some(value) => @decode.text(value).to_option()
          None => None
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
  items
}

///|
fn emit_client_authoring_context(
  owner : PreparedClientProgram,
  items : Array[ClientAnnotation],
  writer : @encode.Writer,
  identity? : String? = None,
) -> Unit raise @encode.EncodeFailure {
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
  if identity is Some(identity) {
    @encode.key(writer, "authoring_context_cid")
    @encode.string_value(writer, identity)
  }
  @encode.end_object(writer)
}

///|
/// Retain the SAME grammar-selected annotations once, before the original
/// owned writer/sealer is entered. Business fields merely named meta stay DATA.
pub fn prepare_client_authoring_context(
  owner : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientAuthoringContextPreparation, ClientAuthoringContextIssue] {
  try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    let items = collect_client_authoring_annotations(owner, max_wire_bytes)
    Ok({
      owner,
      items: Some(items),
      writer: Some(writer),
      max_wire_bytes,
      max_nodes,
      max_depth,
      result: None,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// No new path inventory, reparse, JSON tree or owned wire is built here.
/// The same emitter borrows the retained metadata through its original cursor.
/// The registered SHA256 spelling sizes one future CID field only; it is not
/// issued or used as an identity. Actual final sealing remains unchanged.
pub fn measure_prepared_client_authoring_context(
  original : ClientAuthoringContextPreparation,
) -> Result[ClientAuthoringContextConstruction, ClientAuthoringContextIssue] {
  guard original.items is Some(items) else { return Err(Encoding) }
  try {
    let body = @encode.construction_measuring_writer(
      original.max_wire_bytes,
      original.max_nodes,
      original.max_depth,
    )
    emit_client_authoring_context(original.owner, items, body)
    let body = @encode.finish_construction_measurement(body)
    let complete = @encode.construction_measuring_writer(
      original.max_wire_bytes,
      original.max_nodes,
      original.max_depth,
    )
    emit_client_authoring_context(
      original.owner,
      items,
      complete,
      identity=Some("sha256:" + "a".repeat(64)),
    )
    let complete = @encode.finish_construction_measurement(complete)
    Ok({ body, complete, })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Finish this SAME retained constructor once. A failed Writer is not retried
/// or replaced: the original error/result stays on the same preparation.
pub fn finish_prepared_client_authoring_context(
  original : ClientAuthoringContextPreparation,
) -> Result[@publication.RunEvidenceValue, ClientAuthoringContextIssue] {
  if original.result is Some(result) {
    return result
  }
  guard original.items is Some(items) && original.writer is Some(writer) else {
    return Err(Encoding)
  }
  let body = try {
    emit_client_authoring_context(original.owner, items, writer)
    @encode.finish(writer)
  } catch {
    _ => {
      let result : Result[
        @publication.RunEvidenceValue,
        ClientAuthoringContextIssue,
      ] = Err(Encoding)
      original.result = Some(result)
      return result
    }
  }
  let result : Result[
    @publication.RunEvidenceValue,
    ClientAuthoringContextIssue,
  ] = @publication.seal_run_evidence_value(
    "authoring_context",
    body,
    original.max_wire_bytes,
    original.max_nodes,
    original.max_depth,
  ).map_err(issue => Evidence(issue))
  original.result = Some(result)
  if result is Ok(_) {
    // Only the completed original evidence crosses Module/Run overlap. Failed
    // constructor material remains on this SAME preparation until cleanup.
    original.items = None
    original.writer = None
  }
  result
}

///|
/// Bounded DATA from the SAME completed constructor. An equal Program CID or
/// copied evidence cannot substitute another original Prepared owner.
pub fn prepared_client_authoring_context_evidence(
  owner : PreparedClientProgram,
  original : ClientAuthoringContextPreparation,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.RunEvidenceValue, ClientAuthoringContextIssue] {
  if !physical_equal(owner, original.owner) {
    return Err(ForeignOriginal)
  }
  guard original.result is Some(result) else { return Err(Encoding) }
  match result {
    Err(_) => result
    Ok(evidence) =>
      if @publication.run_evidence_value_fits(
          evidence, max_wire_bytes, max_nodes, max_depth,
        ) {
        result
      } else {
        Err(Evidence(@publication.RunEvidenceInvalidWire))
      }
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
  // Existing direct consumers keep their original constructor inventory. Only
  // the separately quoted Request path retains the new preparation carrier.
  let body = try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    let items = collect_client_authoring_annotations(owner, max_wire_bytes)
    emit_client_authoring_context(owner, items, writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(Encoding)
  }
  @publication.seal_run_evidence_value(
    "authoring_context", body, max_wire_bytes, max_nodes, max_depth,
  ).map_err(issue => Evidence(issue))
}
