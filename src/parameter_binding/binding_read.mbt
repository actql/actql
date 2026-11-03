///|
/// Constructor boundaries of the SAME original binding read. These are DATA
/// observations, not caller-supplied transitions, resource grants or validation.
pub(all) enum BindingReadPhase {
  BindingHeader
  BindingSelection
  BindingPreflight
  BindingValue
  BindingComplete
} derive(Eq, Debug)

///|
priv enum BindingReadState {
  AwaitingBindingHeader
  ReadingBinding(BindingReadBody)
  BindingCompleted(Result[BindingResult, Issue])
}

///|
priv struct BindingReadBody {
  object : @decode.ObjectView?
  budget : Budget
  entries : Array[BoundParameter]
  missing : Array[Declaration]
  mut index : Int
  mut declaration : Declaration?
  mut selected : @decode.Cursor?
  mut provided : Bool
  mut phase : BindingReadPhase
  mut construction : BindingReadConstruction?
}

///|
/// The actual declaration original, supplied Cursor and semantic limits.
/// A fixed caller must fund each constructor before advancing; neither this
/// holder nor its accessors reserve capacity, check currentness or perform IO.
struct BindingReadInput {
  declarations : Declarations
  supplied : @decode.Cursor?
  limits : @value.Limits
  mut origin : Origin
  mut state : BindingReadState
  mut value_nodes : Int
  mut value_text : Int
}

///|
pub fn prepare_binding_read(
  declarations : Declarations,
  supplied : @decode.Cursor?,
  limits : @value.Limits,
) -> Result[BindingReadInput, Issue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  Ok({
    declarations,
    supplied,
    limits,
    origin: Supplied,
    state: AwaitingBindingHeader,
    value_nodes: 0,
    value_text: 0,
  })
}

///|
pub fn binding_read_phase(original : BindingReadInput) -> BindingReadPhase {
  match original.state {
    AwaitingBindingHeader => BindingHeader
    ReadingBinding(body) => body.phase
    BindingCompleted(_) => BindingComplete
  }
}

///|
/// SAME selected original/Some, never a lookup, copy or admission. Header and
/// completed states expose no partial values or constructed binding result.
pub fn binding_read_pending_source(
  original : BindingReadInput,
) -> @decode.Cursor? {
  match original.state {
    ReadingBinding(body) => body.selected
    _ => None
  }
}

///|
pub fn binding_read_pending_declaration(
  original : BindingReadInput,
) -> Declaration? {
  match original.state {
    ReadingBinding(body) => body.declaration
    _ => None
  }
}

///|
/// The original selected failure domain. It is set before name/source budget
/// admission just as in ordinary binding, not inferred from a cursor's path.
pub fn binding_read_origin(original : BindingReadInput) -> Origin {
  original.origin
}

///|
/// Advance one original constructor boundary AFTER its complete reservation.
/// There is one semantic implementation for ordinary and staged consumers.
/// Completion caches the exact Result; repeat finishing does no binding work.
pub fn advance_binding_read(original : BindingReadInput) -> Unit {
  try {
    match original.state {
      AwaitingBindingHeader => binding_read_header(original)
      ReadingBinding(body) =>
        match body.phase {
          BindingSelection => binding_read_selection(original, body)
          BindingPreflight => binding_read_preflight(body)
          BindingValue => binding_read_value(original, body)
          _ => abort("private binding body lost its constructor phase")
        }
      BindingCompleted(_) => ()
    }
  } catch {
    Abort(issue) =>
      original.state = BindingCompleted(
        Err(BindingInput(original.origin, issue)),
      )
  }
}

///|
fn binding_read_header(original : BindingReadInput) -> Unit raise Abort {
  // The closed supplied-map boundary precedes Budget and per-entry reads.
  let names = original.declarations.entries.map(e => e.name)
  let object = match original.supplied {
    None => None
    Some(cursor) => Some(decoded(@decode.closed_object(cursor, names)))
  }
  let body : BindingReadBody = {
    object,
    budget: {
      nodes: original.limits.max_nodes,
      text: original.limits.max_text_bytes,
      depth: original.limits.max_depth,
    },
    entries: [],
    missing: [],
    index: 0,
    declaration: None,
    selected: None,
    provided: false,
    phase: BindingSelection,
    construction: None,
  }
  original.state = ReadingBinding(body)
  if original.declarations.entries.is_empty() {
    complete_binding_read(original, body)
  }
}

///|
fn binding_read_selection(
  original : BindingReadInput,
  body : BindingReadBody,
) -> Unit {
  let declaration = original.declarations.entries[body.index]
  let (provided, selected) = match body.construction {
    None => select_binding_source(body.object, declaration)
    Some(original) => {
      let current = original.entries[body.index].unwrap()
      (current.provided, current.selected)
    }
  }
  match selected {
    None => {
      body.missing.push(declaration)
      finish_binding_entry(original, body)
    }
    Some(_) => {
      body.declaration = Some(declaration)
      body.selected = selected
      body.provided = provided
      original.origin = if body.provided { Supplied } else { Default }
      body.phase = BindingPreflight
    }
  }
}

///|
// One original selection rule for ordinary and construction-observed readers.
// Explicit NULL remains supplied; only absence selects the original default.
fn select_binding_source(
  object : @decode.ObjectView?,
  declaration : Declaration,
) -> (Bool, @decode.Cursor?) {
  let provided = match object {
    None => None
    Some(o) => @decode.lookup(o, declaration.name)
  }
  let selected = match provided {
    Some(c) => Some(c)
    None => declaration.default_cursor
  }
  (provided is Some(_), selected)
}

///|
fn binding_read_preflight(body : BindingReadBody) -> Unit raise Abort {
  let declaration = body.declaration.unwrap()
  let cursor = body.selected.unwrap()
  charge_text(declaration.name, cursor, body.budget)
  preflight(cursor, body.budget)
  body.phase = BindingValue
}

///|
fn binding_read_value(
  original : BindingReadInput,
  body : BindingReadBody,
) -> Unit raise Abort {
  let declaration = body.declaration.unwrap()
  let cursor = body.selected.unwrap()
  let (value, origin) = if body.provided {
    let (value, nodes, text) = check_value_usage(
      cursor,
      declaration.syntax.parameter_type,
      original.limits,
    )
    // Value admission has a fresh per-value budget; selected-value preflight
    // separately charges the cumulative binding budget, including names.
    original.value_nodes = Int::max(original.value_nodes, nodes)
    original.value_text = Int::max(original.value_text, text)
    (value, Supplied)
  } else {
    (declaration.default_value.unwrap(), Default)
  }
  body.entries.push({
    name: declaration.name,
    value,
    origin,
    parameter_type: declaration.parameter_type,
  })
  finish_binding_entry(original, body)
}

///|
fn finish_binding_entry(
  original : BindingReadInput,
  body : BindingReadBody,
) -> Unit {
  body.index += 1
  body.declaration = None
  body.selected = None
  body.provided = false
  if body.index == original.declarations.entries.length() {
    complete_binding_read(original, body)
  } else {
    body.phase = BindingSelection
  }
}

///|
fn complete_binding_read(
  original : BindingReadInput,
  body : BindingReadBody,
) -> Unit {
  let usage = (
    original.limits.max_nodes - body.budget.nodes,
    original.limits.max_text_bytes - body.budget.text,
  )
  let result = if body.missing.is_empty() {
    Ok(
      Ready({
        declarations: original.declarations,
        entries: body.entries,
        usage,
      }),
    )
  } else {
    Ok(
      NeedsBindings({
        declarations: original.declarations,
        entries: body.missing,
        usage,
      }),
    )
  }
  original.state = BindingCompleted(result)
}

///|
/// A complete repeat forwards the SAME original Result unchanged. This does
/// not imply constructor funding, binding usage allowance or execution rights.
pub fn finish_binding_read(
  original : BindingReadInput,
) -> Result[BindingResult, Issue] {
  for state = original.state {
    match state {
      BindingCompleted(result) => break result
      _ => {
        advance_binding_read(original)
        continue original.state
      }
    }
  }
}
