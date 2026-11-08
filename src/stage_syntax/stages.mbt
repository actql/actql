///|
pub(all) enum Predecessor {
  Initial
  Accepted(String)
  Completed(String)
} derive(Eq, Debug)

///|
pub(all) enum ImportPort {
  Result(producer~ : String, result~ : String)
  Receipt(producer~ : String, effect~ : String)
} derive(Eq, Debug)

///|
pub struct Stage {
  id : String
  predecessor : Predecessor
  priv imports : Array[(String, ImportPort)]
  priv results : Array[String]
  priv table_inputs : Array[String]
  priv effects : Array[String]
  priv result_index : Map[String, Bool]
  priv table_input_index : Map[String, Bool]
  priv effect_index : Map[String, Bool]
  priv body : @wire.Cursor
  priv original_inputs : @wire.ObjectView
  priv original_input_names : Array[String]
  priv original_steps : @wire.Cursor
}

///|
/// Structural syntax only, NOT a CheckedProgram or executable authorization.
/// Local bodies and shared declarations still require the common semantic checker.
pub struct Program {
  id : String
  priv stages : Array[Stage]
  priv exports : Array[(String, String, String)]
  priv body : @wire.Cursor
  priv source_usage : @source.ParseUsage
  priv preparation : ProgramPreparationData
}

///|
/// A generated, check-only pipeline prefix. The last Stage has no publication
/// roots; earlier Stages keep their actual Result definitions and import edges.
/// This type has no conversion to a complete Program or execution permission.
pub struct Prefix {
  id : String
  priv stages : Array[Stage]
  priv body : @wire.Cursor
  priv source_usage : @source.ParseUsage
}

///|
priv struct Envelope {
  id : String
  stages : Array[Stage]
  exports : Array[(String, String, String)]
  body : @wire.Cursor
  source_usage : @source.ParseUsage
  preparation : ProgramPreparationData
}

///|
/// The declared opaque names are public Program structure. Concrete reference
/// values remain invocation material and are never read through this accessor.
pub fn program_binding_names(program : Program) -> Array[String] {
  let root = @wire.open_object(program.body).unwrap()
  match @wire.lookup(root, "bindings") {
    None => []
    Some(bindings) => @wire.object_field_names(bindings).unwrap()
  }
}

///|
/// Parameter declarations are public Program structure. Bound values remain
/// separate invocation material and are not exposed by this accessor.
pub fn program_parameter_names(program : Program) -> Array[String] {
  let root = @wire.open_object(program.body).unwrap()
  match @wire.lookup(root, "params") {
    None => []
    Some(parameters) => @wire.object_field_names(parameters).unwrap()
  }
}

///|
fn required(view : @wire.ObjectView, name : String) -> @wire.Cursor raise Abort {
  match @wire.required(view, name) {
    Ok(value) => value
    Err(issue) => raise Abort(Decode(issue))
  }
}

///|
fn object(
  node : @wire.Cursor,
  fields : Array[String],
) -> @wire.ObjectView raise Abort {
  match @wire.closed_object(node, fields) {
    Ok(value) => value
    Err(issue) => raise Abort(Decode(issue))
  }
}

///|
fn name(node : @wire.Cursor) -> String raise Abort {
  match @wire.text(node) {
    Ok(value) => {
      if value.is_empty() {
        invalid(node, EmptyName)
      }
      // This slot is a grammar-owned identifier, never row or parameter data.
      match @canonical.normalize_nfc_lf(value) {
        Ok(name) => name
        Err(_) => invalid(node, EmptyName)
      }
    }
    Err(issue) => raise Abort(Decode(issue))
  }
}

///|
fn names(node : @wire.Cursor, nonempty : Bool) -> Array[String] raise Abort {
  let fields = match @wire.object_field_names(node) {
    Ok(value) => value
    Err(issue) => raise Abort(Decode(issue))
  }
  // Parsing rejects normalized duplicates; admission owns the immutable tree.
  if nonempty && fields.is_empty() {
    invalid(node, EmptyDeclarations)
  }
  for key in fields {
    if key.is_empty() {
      invalid(node, EmptyName)
    }
  }
  fields
}

///|
fn open(node : @wire.Cursor) -> @wire.ObjectView raise Abort {
  match @wire.open_object(node) {
    Ok(value) => value
    Err(issue) => raise Abort(Decode(issue))
  }
}

///|
fn name_index(names : Array[String]) -> Map[String, Bool] {
  let index = Map([])
  for name in names {
    index[name] = true
  }
  index
}

///|
fn metadata(view : @wire.ObjectView) -> Unit raise Abort {
  match @wire.lookup(view, "meta") {
    None => ()
    Some(node) => {
      let fields = match @wire.object_field_names(node) {
        Ok(fields) => fields
        Err(issue) => raise Abort(Decode(issue))
      }
      if fields.is_empty() {
        invalid(node, EmptyDeclarations)
      }
      let annotations = open(node)
      for key in fields {
        if key.has_prefix("actql_") {
          // The key exists even when its value is null; reject the reserved name.
          invalid(
            @wire.lookup(annotations, key).unwrap(),
            ReservedMetadataKey(key),
          )
        }
      }
    }
  }
}

///|
/// Inspect normalized, owned source. This is not a semantic checker.
fn decode(
  root : @wire.Cursor,
  max_stages : Int,
  source_usage : @source.ParseUsage,
) -> Program raise Abort {
  let value = decode_envelope(root, max_stages, source_usage, prefix=false)
  {
    id: value.id,
    stages: value.stages,
    exports: value.exports,
    body: value.body,
    source_usage: value.source_usage,
    preparation: value.preparation,
  }
}

///|
fn decode_prefix(
  root : @wire.Cursor,
  max_stages : Int,
  source_usage : @source.ParseUsage,
) -> Prefix raise Abort {
  let value = decode_envelope(root, max_stages, source_usage, prefix=true)
  {
    id: value.id,
    stages: value.stages,
    body: value.body,
    source_usage: value.source_usage,
  }
}

///|
fn decode_envelope(
  root : @wire.Cursor,
  max_stages : Int,
  source_usage : @source.ParseUsage,
  prefix~ : Bool,
) -> Envelope raise Abort {
  let view = object(root, [
    "version", "id", "meta", "params", "bindings", "stages", "results",
  ])
  if name(required(view, "version")) != "actql/0.1" {
    invalid(required(view, "version"), WrongVersion)
  }
  let id = name(required(view, "id"))
  metadata(view)
  for key in ["params", "bindings"] {
    match @wire.lookup(view, key) {
      Some(node) => ignore(names(node, true))
      None => ()
    }
  }
  let nodes = match @wire.elements(required(view, "stages")) {
    Ok(value) => value
    Err(issue) => raise Abort(Decode(issue))
  }
  if nodes.is_empty() {
    invalid(required(view, "stages"), EmptyStages)
  }
  if nodes.length() > max_stages {
    invalid(required(view, "stages"), StageLimit)
  }
  let preparation : ProgramPreparationState = {
    operations: 0,
    effect_members: 0,
    results: 0,
    external_inputs: 0,
    initial_fields: 0,
    possible_growth: 0,
    projected_fields: 0,
    max_label_utf16: id.length(),
    may_contain_expression_syntax: false,
  }
  let stages : Array[Stage] = []
  let seen : Map[String, Stage] = Map([])
  for node in nodes {
    let stage = object(node, stage_closed_field_names)
    let stage_id = name(required(stage, "id"))
    preparation.max_label_utf16 = Int::max(
      preparation.max_label_utf16,
      stage_id.length(),
    )
    metadata(stage)
    if seen.contains(stage_id) {
      invalid(required(stage, "id"), DuplicateStage(stage_id))
    }
    let predecessor = if stages.is_empty() {
      if @wire.lookup(stage, "after") is Some(_) {
        invalid(required(stage, "after"), InitialAfter)
      }
      Initial
    } else {
      let previous = stages[stages.length() - 1].id
      match @wire.lookup(stage, "after") {
        None => Completed(previous)
        Some(value) =>
          match name(value) {
            "accepted" => Accepted(previous)
            "completed" => Completed(previous)
            _ => invalid(value, InvalidAfter)
          }
      }
    }
    let inputs = required(stage, "inputs")
    let input_names = names(inputs, false)
    let inputs_view = open(inputs)
    let imports : Array[(String, ImportPort)] = []
    for input_name in input_names {
      let input = required(inputs_view, input_name)
      // Local Input shorthand is a string; Carrier resolution belongs downstream.
      if @wire.is_text(input) {
        continue
      }
      let input_fields = names(input, false)
      if !prefix {
        preparation_schema(input, preparation)
      }
      for kind in ["result", "receipt"] {
        if input_fields.contains(kind) {
          let input_view = object(input, [kind, "meta"])
          metadata(input_view)
          let target_key = if kind == "result" { "result" } else { "effect" }
          let target = object(required(input_view, kind), ["stage", target_key])
          let producer = name(required(target, "stage"))
          let port = name(required(target, target_key))
          let earlier = match seen.get(producer) {
            Some(value) => value
            None =>
              invalid(required(target, "stage"), UnknownProducer(producer))
          }
          if kind == "result" {
            if !earlier.result_index.contains(port) {
              invalid(required(target, target_key), UnknownResult(port))
            }
            imports.push((input_name, Result(producer~, result=port)))
          } else {
            if !earlier.effect_index.contains(port) {
              invalid(required(target, target_key), UnknownEffect(port))
            }
            imports.push((input_name, Receipt(producer~, effect=port)))
          }
        }
      }
    }
    match @wire.lookup(stage, "from") {
      Some(value) =>
        if !input_names.contains(name(value)) {
          invalid(value, UnknownInput(name(value)))
        }
      None => ()
    }
    let original_steps = required(stage, "steps")
    let original_step_views = match @wire.elements(original_steps) {
      Ok(value) => value
      Err(issue) => raise Abort(Decode(issue))
    }
    preparation.operations += original_step_views.length()
    preparation.external_inputs += input_names.length() - imports.length()
    if !prefix {
      for step in original_step_views {
        preparation_step(step, preparation)
      }
    }
    let results_node = required(stage, "results")
    let results = names(results_node, false)
    preparation.results += results.length()
    let table_inputs = match @wire.lookup(stage, "table_inputs") {
      Some(value) => names(value, true)
      None => []
    }
    let effects = match @wire.lookup(stage, "effects") {
      Some(value) => names(value, false)
      None => []
    }
    preparation.effect_members += effects.length()
    // Effects are roots even without public Results. This is structural syntax,
    // not authorization: every Effect still needs the common semantic checker.
    let open_prefix = prefix && stages.length() == nodes.length() - 1
    if open_prefix {
      if !results.is_empty() || !effects.is_empty() || !table_inputs.is_empty() {
        invalid(results_node, PrefixPublication)
      }
    } else if results.is_empty() && effects.is_empty() {
      invalid(results_node, EmptyDeclarations)
    }
    let value = {
      id: stage_id,
      predecessor,
      imports,
      results,
      table_inputs,
      effects,
      result_index: name_index(results),
      table_input_index: name_index(table_inputs),
      effect_index: name_index(effects),
      body: node,
      original_inputs: inputs_view,
      original_input_names: input_names,
      original_steps,
    }
    stages.push(value)
    seen[stage_id] = value
  }
  let exports_node = required(view, "results")
  let export_names = names(exports_node, false)
  if prefix {
    if !export_names.is_empty() {
      invalid(exports_node, PrefixPublication)
    }
  } else if export_names.is_empty() &&
    !stages.any(stage => !stage.effects.is_empty()) {
    invalid(exports_node, EmptyDeclarations)
  }
  let exports_view = open(exports_node)
  let exports = export_names.map(key => {
    let export_ = object(required(exports_view, key), ["from"])
    let from = object(required(export_, "from"), ["stage", "result"])
    let producer = name(required(from, "stage"))
    let result = name(required(from, "result"))
    match seen.get(producer) {
      Some(stage) =>
        if !stage.result_index.contains(result) {
          invalid(required(from, "result"), UnknownResult(result))
        }
      None => invalid(required(from, "stage"), UnknownProducer(producer))
    }
    (key, producer, result)
  })
  {
    id,
    stages,
    exports,
    body: root,
    source_usage,
    preparation: {
      operations: preparation.operations,
      effect_members: preparation.effect_members,
      results: preparation.results + exports.length(),
      external_inputs: preparation.external_inputs,
      initial_fields: preparation.initial_fields,
      possible_growth: preparation.possible_growth,
      projected_fields: preparation.projected_fields,
      max_label_utf16: preparation.max_label_utf16,
      may_contain_expression_syntax: preparation.may_contain_expression_syntax,
    },
  }
}

///|
pub fn stages(program : Program) -> Array[Stage] {
  program.stages.copy()
}

///|
/// Read the source Stage count without allocating a copy.
pub fn stage_count(program : Program) -> Int {
  program.stages.length()
}

///|
pub fn stage_table_input_count(stage : Stage) -> Int {
  stage.table_inputs.length()
}

///|
pub fn stage_table_input_at(stage : Stage, index : Int) -> String? {
  stage.table_inputs.get(index)
}

///|
pub fn imports(stage : Stage) -> Array[(String, ImportPort)] {
  stage.imports.copy()
}

///|
pub fn import_count(stage : Stage) -> Int {
  stage.imports.length()
}

///|
pub fn import_at(stage : Stage, index : Int) -> (String, ImportPort)? {
  stage.imports.get(index)
}

///|
pub fn exports(program : Program) -> Array[(String, String, String)] {
  program.exports.copy()
}

///|
pub fn export_count(program : Program) -> Int {
  program.exports.length()
}

///|
pub fn export_at(program : Program, index : Int) -> (String, String, String)? {
  program.exports.get(index)
}

///|
pub fn stage_body(stage : Stage) -> @wire.Cursor {
  stage.body
}

///|
/// Same structurally admitted declaration table, not semantic or resource
/// admission. Names and source cursors stay in their original Stage lifetime.
pub fn stage_input_declaration_count(stage : Stage) -> Int {
  stage.original_input_names.length()
}

///|
pub fn stage_input_declaration_name_at(stage : Stage, index : Int) -> String? {
  stage.original_input_names.get(index)
}

///|
pub fn stage_input_declaration(stage : Stage, name : String) -> @wire.Cursor? {
  @wire.lookup(stage.original_inputs, name)
}

///|
pub fn stage_steps_source(stage : Stage) -> @wire.Cursor {
  stage.original_steps
}

///|
pub fn result_names(stage : Stage) -> Array[String] {
  stage.results.copy()
}

///|
pub fn effect_names(stage : Stage) -> Array[String] {
  stage.effects.copy()
}

///|
pub fn program_body(program : Program) -> @wire.Cursor {
  program.body
}

///|
/// Original owned Cursor, including imported origins. No Result is synthesized.
pub fn prefix_body(prefix : Prefix) -> @wire.Cursor {
  prefix.body
}

///|
pub fn prefix_stages(prefix : Prefix) -> Array[Stage] {
  prefix.stages.copy()
}

///|
// One immutable list is used by actual Stage admission and constructor
// inspection bounds. It is never returned as a mutable caller-owned Array.
let stage_closed_field_names : Array[String] = [
  "id", "meta", "after", "inputs", "from", "steps", "results", "effects", "table_inputs",
]

///|
/// The actual closed Stage contract's field count, not an acceptance override
/// or caller policy. Admitted original Stage bodies cannot exceed this count.
pub fn stage_closed_field_count() -> Int {
  stage_closed_field_names.length()
}
