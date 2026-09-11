///|
pub(all) enum Constraint {
  Resource(String)
  Artifact(String?)
} derive(Eq, Debug)

///|
pub struct Declaration {
  name : String
  constraint : Constraint
  priv source : @decode.Cursor
}

///|
struct Declarations {
  program : @stage.Program
  entries : Array[Declaration]
  work : Int
}

///|
pub(all) struct Limits {
  max_bindings : Int
  max_work : Int
}

///|
pub enum Issue {
  InvalidLimits
  WorkLimit
  BindingLimit
  Decode(@decode.Issue)
  InvalidName(@decode.Cursor)
  InvalidMetadata(@decode.Cursor)
  UnknownType(@decode.Cursor)
  EmptyConstraint(@decode.Cursor)
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Budget {
  mut remaining : Int
}

///|
fn spend(b : Budget, n : Int) -> Unit raise Stop {
  if n > b.remaining {
    raise Stop(WorkLimit)
  }
  b.remaining -= n
}

///|
fn[T] read(value : Result[T, @decode.Issue]) -> T raise Stop {
  match value {
    Ok(v) => v
    Err(e) => raise Stop(Decode(e))
  }
}

///|
fn valid_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  for i in 0..<name.length() {
    let c = name.code_unit_at(i).to_int()
    if !(c == 95 ||
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (i > 0 && c >= 48 && c <= 57)) {
      return false
    }
  }
  true
}

///|
/// Admit declarations from their actual Program owner, not an independent map.
/// No concrete Ref value, issuer evidence or request compatibility is admitted.
pub fn prepare(
  program : @stage.Program,
  limits : Limits,
) -> Result[Declarations, Issue] {
  if limits.max_bindings < 0 || limits.max_work < 0 {
    return Err(InvalidLimits)
  }
  let b : Budget = { remaining: limits.max_work, }
  try {
    spend(b, 1)
    let root = read(@decode.open_object(@stage.program_body(program)))
    let entries : Array[Declaration] = []
    if @decode.lookup(root, "bindings") is Some(bindings) {
      ignore(read(@decode.open_object(bindings)))
      let n = @decode.object_length(bindings).unwrap()
      if n > limits.max_bindings {
        raise Stop(BindingLimit)
      }
      spend(b, n)
      // Bound all retained declaration/annotation data without recursion. JSON
      // scalar validity is already guaranteed by the opaque Program parser.
      let pending = [bindings]
      while pending.pop() is Some(cursor) {
        spend(b, 1)
        if @decode.array_length(cursor) is Some(n) {
          spend(b, n)
          for i in 0..<n {
            pending.push(@decode.element_at(cursor, i).unwrap())
          }
        } else if @decode.object_length(cursor) is Some(n) {
          spend(b, n)
          for i in 0..<n {
            let (key, child) = @decode.field_at(cursor, i).unwrap()
            spend(b, key.length())
            pending.push(child)
          }
        } else if @decode.view(cursor) is @decode.TextValue(value) {
          spend(b, value.length())
        }
      }
      for i in 0..<n {
        let (name, source) = @decode.field_at(bindings, i).unwrap()
        if !valid_name(name) {
          raise Stop(InvalidName(source))
        }
        let view = read(@decode.open_object(source))
        let type_source = read(@decode.required(view, "type"))
        let kind = read(@decode.text(type_source))
        let allowed = match kind {
          "resource_ref" => ["type", "resource_kind", "meta"]
          "artifact_ref" => ["type", "media_type", "meta"]
          _ => raise Stop(UnknownType(type_source))
        }
        ignore(read(@decode.closed_object(source, allowed)))
        if @decode.lookup(view, "meta") is Some(meta) {
          let n = match @decode.object_length(meta) {
            Some(n) if n > 0 => n
            _ => raise Stop(InvalidMetadata(meta))
          }
          for j in 0..<n {
            let (key, child) = @decode.field_at(meta, j).unwrap()
            if key.has_prefix("actql_") {
              raise Stop(InvalidMetadata(child))
            }
          }
        }
        let constraint = if kind == "resource_ref" {
          let raw = read(@decode.required(view, "resource_kind"))
          let value = read(@decode.text(raw))
          if value.is_empty() {
            raise Stop(EmptyConstraint(raw))
          }
          Resource(value)
        } else {
          let media = match @decode.lookup(view, "media_type") {
            None => None
            Some(raw) => {
              let value = read(@decode.text(raw))
              if value.is_empty() {
                raise Stop(EmptyConstraint(raw))
              }
              Some(value)
            }
          }
          Artifact(media)
        }
        entries.push({ name, constraint, source, })
      }
    }
    entries.sort_by((a, b) => @canonical.compare_utf16(a.name, b.name))
    Ok({ program, entries, work: limits.max_work - b.remaining, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn program(value : Declarations) -> @stage.Program {
  value.program
}

///|
pub fn count(value : Declarations) -> Int {
  value.entries.length()
}

///|
pub fn at(value : Declarations, index : Int) -> Declaration? {
  value.entries.get(index)
}

///|
pub fn source(value : Declaration) -> @decode.Cursor {
  value.source
}

///|
pub fn work(value : Declarations) -> Int {
  value.work
}

///|
pub fn find(value : Declarations, name : String) -> Declaration? {
  let mut low = 0
  let mut high = value.entries.length()
  while low < high {
    let mid = low + (high - low) / 2
    let order = @canonical.compare_utf16(value.entries[mid].name, name)
    if order == 0 {
      return Some(value.entries[mid])
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
pub fn emit_declaration(
  value : Declaration,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  match value.constraint {
    Resource(kind) => {
      @encode.key(writer, "resource_kind")
      @encode.string_value(writer, kind)
      @encode.key(writer, "type")
      @encode.string_value(writer, "resource_ref")
    }
    Artifact(media) => {
      if media is Some(media) {
        @encode.key(writer, "media_type")
        @encode.string_value(writer, media)
      }
      @encode.key(writer, "type")
      @encode.string_value(writer, "artifact_ref")
    }
  }
  @encode.end_object(writer)
}
