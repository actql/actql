///|
pub(all) struct Limits {
  max_slots : Int
  max_references : Int
  max_pointer_units : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  SlotLimit
  ReferenceLimit
  PointerLimit
  ForeignExpression(Int)
  EmptyLocation
  UnknownParameter(String, String)
  DuplicateLocation(String)
} derive(Eq, Debug)

///|
pub struct Reference {
  name : String
  path : String
  declaration : @parameter.Declaration
}

///|
struct Index {
  source : @decode.Cursor
  declarations : @parameter.Declarations
  slots : Array[@expression.ParameterOccurrences]
  entries : Array[Reference]
  used : Array[Int]
  pointer_units : Int
}

///|
priv struct PointerBudget {
  mut remaining : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn write_piece(
  out : StringBuilder,
  piece : String,
  budget : PointerBudget,
) -> Unit raise Stop {
  if piece.length() > budget.remaining {
    raise Stop(PointerLimit)
  }
  budget.remaining -= piece.length()
  out.write_string(piece)
}

///|
fn write_segments(
  out : StringBuilder,
  path : Array[@decode.PathSegment],
  start : Int,
  budget : PointerBudget,
) -> Unit raise Stop {
  for i in start..<path.length() {
    write_piece(out, "/", budget)
    match path[i] {
      @source.Index(index) => write_piece(out, index.to_string(), budget)
      @source.Key(key) =>
        for ch in key.iter() {
          write_piece(
            out,
            match ch {
              '~' => "~0"
              '/' => "~1"
              _ => ch.to_string()
            },
            budget,
          )
        }
    }
  }
}

///|
fn find_declaration(
  declarations : @parameter.Declarations,
  name : String,
) -> Int? {
  let mut low = 0
  let mut high = @parameter.declaration_count(declarations)
  while low < high {
    let mid = low + (high - low) / 2
    let d = @parameter.declaration_at(declarations, mid).unwrap()
    let order = @canonical.compare_utf16(d.name, name)
    if order == 0 {
      return Some(mid)
    }
    if order < 0 {
      low = mid + 1
    } else {
      high = mid
    }
  }
  None
}

///|
/// Index supplied admitted expression slots; this does not discover all Program
/// slots or certify that the supplied list is complete.
pub fn build(
  source : @decode.Cursor,
  declarations : @parameter.Declarations,
  slots : Array[@expression.ParameterOccurrences],
  limits : Limits,
) -> Result[Index, Issue] {
  if limits.max_slots < 0 ||
    limits.max_references < 0 ||
    limits.max_pointer_units < 0 {
    return Err(InvalidLimits)
  }
  if slots.length() > limits.max_slots {
    return Err(SlotLimit)
  }
  try {
    let root_path = @decode.cursor_path(source)
    let budget = { remaining: limits.max_pointer_units, }
    let entries : Array[Reference] = []
    let used : Map[Int, Unit] = Map([])
    for slot in 0..<slots.length() {
      let occurrences = slots[slot]
      let expression = @expression.parameter_occurrence_expression(occurrences)
      let origin = match
        @expression.origin(expression, @expression.tree(expression)) {
        Some(origin) => origin
        None => raise Stop(ForeignExpression(slot))
      }
      if @decode.tree_index(source, origin.source) is None {
        raise Stop(ForeignExpression(slot))
      }
      let prefix = @decode.cursor_path(origin.source)
      if prefix.length() < root_path.length() {
        raise Stop(ForeignExpression(slot))
      }
      for i in 0..<root_path.length() {
        if prefix[i] != root_path[i] {
          raise Stop(ForeignExpression(slot))
        }
      }
      let count = @expression.parameter_occurrence_count(occurrences)
      if count > limits.max_references - entries.length() {
        raise Stop(ReferenceLimit)
      }
      for i in 0..<count {
        let r = @expression.parameter_occurrence_at(occurrences, i).unwrap()
        let out = StringBuilder()
        write_segments(out, prefix, root_path.length(), budget)
        write_segments(out, @decode.cursor_path(r.cursor), 0, budget)
        let path = out.to_string()
        if path.is_empty() {
          raise Stop(EmptyLocation)
        }
        let index = match find_declaration(declarations, r.name) {
          Some(index) => index
          None => raise Stop(UnknownParameter(r.name, path))
        }
        entries.push({
          name: r.name,
          path,
          declaration: @parameter.declaration_at(declarations, index).unwrap(),
        })
        used[index] = ()
      }
    }
    entries.sort_by((a, b) => {
      let order = @canonical.compare_utf16(a.path, b.path)
      if order == 0 {
        @canonical.compare_utf16(a.name, b.name)
      } else {
        order
      }
    })
    for i in 1..<entries.length() {
      if entries[i - 1].path == entries[i].path {
        raise Stop(DuplicateLocation(entries[i].path))
      }
    }
    let used = used.keys().collect()
    used.sort()
    Ok({
      source,
      declarations,
      slots: slots.copy(),
      entries,
      used,
      pointer_units: limits.max_pointer_units - budget.remaining,
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn reference_count(index : Index) -> Int {
  index.entries.length()
}

///|
pub fn reference_at(index : Index, position : Int) -> Reference? {
  index.entries.get(position)
}

///|
pub fn source(index : Index) -> @decode.Cursor {
  index.source
}

///|
pub fn declarations(index : Index) -> @parameter.Declarations {
  index.declarations
}

///|
pub fn slot_at(
  index : Index,
  position : Int,
) -> @expression.ParameterOccurrences? {
  index.slots.get(position)
}

///|
pub fn pointer_units(index : Index) -> Int {
  index.pointer_units
}

///|
pub fn emit_references(
  index : Index,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(output)
  for r in index.entries {
    @encode.begin_object(output)
    @encode.key(output, "name")
    @encode.string_value(output, r.name)
    @encode.key(output, "path")
    @encode.string_value(output, r.path)
    @encode.key(output, "type")
    @parameter.emit_declaration(r.declaration, output)
    @encode.end_object(output)
  }
  @encode.end_array(output)
}

///|
pub fn emit_used_declarations(
  index : Index,
  output : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(output)
  for i in index.used {
    let d = @parameter.declaration_at(index.declarations, i).unwrap()
    @encode.key(output, d.name)
    @parameter.emit_declaration(d, output)
  }
  @encode.end_object(output)
}
