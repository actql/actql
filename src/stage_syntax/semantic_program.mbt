///|
/// Mark only grammar-owned annotation fields. A business value may itself
/// contain a field named meta, so removing every such key would alter input.
fn mark_annotation(
  root : @wire.Cursor,
  declaration : @wire.Cursor,
  omitted : Map[Int, Bool],
) -> Unit {
  guard @wire.open_object(declaration) is Ok(view) else { return }
  if @wire.lookup(view, "meta") is Some(annotation) {
    omitted[@wire.tree_index(root, annotation).unwrap()] = true
  }
}

///|
fn mark_declaration_annotations(
  root : @wire.Cursor,
  owner : @wire.Cursor,
  name : String,
  omitted : Map[Int, Bool],
) -> Unit {
  guard @wire.open_object(owner) is Ok(view) else { return }
  guard @wire.lookup(view, name) is Some(declarations) else { return }
  guard @wire.object_length(declarations) is Some(count) else { return }
  for i in 0..<count {
    let (_, declaration) = @wire.field_at(declarations, i).unwrap()
    mark_annotation(root, declaration, omitted)
  }
}

///|
fn mark_step_annotations(
  root : @wire.Cursor,
  stage : @wire.Cursor,
  omitted : Map[Int, Bool],
) -> Unit {
  guard @wire.open_object(stage) is Ok(view) else { return }
  guard @wire.lookup(view, "steps") is Some(steps) else { return }
  guard @wire.array_length(steps) is Some(count) else { return }
  for i in 0..<count {
    mark_annotation(root, @wire.element_at(steps, i).unwrap(), omitted)
  }
}

///|
fn emit_without_annotations(
  root : @wire.Cursor,
  cursor : @wire.Cursor,
  omitted : Map[Int, Bool],
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  if @wire.array_length(cursor) is Some(count) {
    @encode.begin_array(out)
    for i in 0..<count {
      emit_without_annotations(
        root,
        @wire.element_at(cursor, i).unwrap(),
        omitted,
        out,
      )
    }
    @encode.end_array(out)
  } else if @wire.object_length(cursor) is Some(count) {
    let fields : Array[(String, @wire.Cursor)] = []
    for i in 0..<count {
      let field = @wire.field_at(cursor, i).unwrap()
      if !omitted.contains(@wire.tree_index(root, field.1).unwrap()) {
        fields.push(field)
      }
    }
    fields.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
    @encode.begin_object(out)
    for (name, value) in fields {
      @encode.key(out, name)
      emit_without_annotations(root, value, omitted, out)
    }
    @encode.end_object(out)
  } else {
    match @wire.view(cursor) {
      @wire.NullValue => @encode.null_value(out)
      @wire.BoolValue(value) => @encode.bool_value(out, value)
      @wire.NumberValue(value) => @encode.number_value(out, value)
      @wire.TextValue(value) => @encode.string_value(out, value)
      _ => raise @encode.InvalidStructure
    }
  }
}

///|
/// Emit the accepted AQL document without its grammar-owned authoring
/// annotations. This is private Plan material, not a checked execution grant.
pub fn emit_metadata_stripped_program(
  program : Program,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let root = program.body
  let omitted : Map[Int, Bool] = Map([])
  mark_annotation(root, root, omitted)
  for name in ["params", "bindings", "results"] {
    mark_declaration_annotations(root, root, name, omitted)
  }
  for stage in program.stages {
    mark_annotation(root, stage.body, omitted)
    for name in ["inputs", "results", "effects"] {
      mark_declaration_annotations(root, stage.body, name, omitted)
    }
    mark_step_annotations(root, stage.body, omitted)
  }
  emit_without_annotations(root, root, omitted, out)
}
