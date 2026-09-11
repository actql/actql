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
  priv effects : Array[String]
  priv result_index : Map[String, Bool]
  priv effect_index : Map[String, Bool]
  priv body : @wire.Cursor
}

///|
/// Structural syntax only, NOT a CheckedProgram or executable authorization.
/// Local bodies and shared declarations still require the common semantic checker.
pub struct Program {
  id : String
  priv stages : Array[Stage]
  priv exports : Array[(String, String, String)]
  priv body : @wire.Cursor
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
    Ok(value) => if value.is_empty() { invalid(node, EmptyName) } else { value }
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
fn decode(root : @wire.Cursor, max_stages : Int) -> Program raise Abort {
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
  let stages : Array[Stage] = []
  let seen : Map[String, Stage] = Map([])
  for node in nodes {
    let stage = object(node, [
      "id", "meta", "after", "inputs", "from", "steps", "results", "effects",
    ])
    let stage_id = name(required(stage, "id"))
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
      if @wire.view(input) is TextValue(_) {
        continue
      }
      let input_fields = names(input, false)
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
    ignore(
      match @wire.elements(required(stage, "steps")) {
        Ok(value) => value
        Err(issue) => raise Abort(Decode(issue))
      },
    )
    let results = names(required(stage, "results"), true)
    let effects = match @wire.lookup(stage, "effects") {
      Some(value) => names(value, false)
      None => []
    }
    let value = {
      id: stage_id,
      predecessor,
      imports,
      results,
      effects,
      result_index: name_index(results),
      effect_index: name_index(effects),
      body: node,
    }
    stages.push(value)
    seen[stage_id] = value
  }
  let exports_node = required(view, "results")
  let export_names = names(exports_node, true)
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
  { id, stages, exports, body: root, }
}

///|
pub fn stages(program : Program) -> Array[Stage] {
  program.stages.copy()
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
