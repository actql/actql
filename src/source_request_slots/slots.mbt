///|
pub enum Value {
  Literal(@decode.Cursor)
  Parameter(@parameter.Declaration)
  Binding(@binding.Declaration)
}

///|
pub struct Slot {
  stage_index : Int
  input_name : String
  field_name : String
  source : @decode.Cursor
  value : Value
}

///|
struct Slots {
  source : @stages.Source
  bindings : @binding.Declarations
  entries : Array[Slot]
  work : Int
}

///|
pub(all) struct Limits {
  max_work : Int
  max_slots : Int
}

///|
pub enum Issue {
  InvalidLimits
  ForeignBindings
  WorkLimit
  SlotLimit
  Decode(@decode.Issue)
  InvalidSource(@decode.Cursor)
  UnknownParameter(String, @decode.Cursor)
  UnknownBinding(String, @decode.Cursor)
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
fn parameter_named(
  source : @stages.Source,
  name : String,
) -> @parameter.Declaration? {
  let declarations = @stages.declarations(source)
  let mut low = 0
  let mut high = @parameter.declaration_count(declarations)
  while low < high {
    let mid = low + (high - low) / 2
    let declaration = @parameter.declaration_at(declarations, mid).unwrap()
    let order = @canonical.compare_utf16(declaration.name, name)
    if order == 0 {
      return Some(declaration)
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
/// Read static request field roles in the exact staged source. Nested business
/// data is not a template. Catalog/type/authority admission remains separate.
pub fn collect(
  source : @stages.Source,
  bindings : @binding.Declarations,
  limits : Limits,
) -> Result[Slots, Issue] {
  if limits.max_work < 0 || limits.max_slots < 0 {
    return Err(InvalidLimits)
  }
  if !physical_equal(@stages.program(source), @binding.program(bindings)) {
    return Err(ForeignBindings)
  }
  let b : Budget = { remaining: limits.max_work, }
  try {
    spend(b, @binding.work(bindings))
    spend(b, @stages.stage_count(source))
    let entries = []
    for stage_index in 0..<@stages.stage_count(source) {
      let body = @stage.stage_body(
        @stages.stage_at(source, stage_index).unwrap(),
      )
      let inputs = read(
        @decode.required(read(@decode.open_object(body)), "inputs"),
      )
      let n = @decode.object_length(inputs).unwrap()
      spend(b, n)
      for i in 0..<n {
        let (input_name, input) = @decode.field_at(inputs, i).unwrap()
        spend(b, input_name.length())
        if @decode.object_length(input) is Some(n) {
          spend(b, n)
          let view = read(@decode.open_object(input))
          if @decode.lookup(view, "connector") is None &&
            @decode.lookup(view, "resource") is None {
            continue
          }
          if @decode.lookup(view, "carrier") is Some(_) {
            raise Stop(InvalidSource(input))
          }
          for key in ["connector", "resource"] {
            let raw = read(@decode.required(view, key))
            let text = read(@decode.text(raw))
            spend(b, text.length())
            if text.is_empty() {
              raise Stop(InvalidSource(raw))
            }
          }
          if @decode.lookup(view, "request") is Some(request) {
            let n = @decode.object_length(request).unwrap_or(0)
            if n > limits.max_slots - entries.length() {
              raise Stop(SlotLimit)
            }
            spend(b, n)
            ignore(read(@decode.open_object(request)))
            for j in 0..<n {
              let (field_name, raw) = @decode.field_at(request, j).unwrap()
              spend(b, field_name.length())
              // Charge retained data without interpreting nested keys. Source
              // parsing has already validated all JSON scalars and normalization.
              let pending = [raw]
              while pending.pop() is Some(cursor) {
                spend(b, 1)
                if @decode.object_length(cursor) is Some(n) {
                  spend(b, n)
                  for k in 0..<n {
                    let (key, child) = @decode.field_at(cursor, k).unwrap()
                    spend(b, key.length())
                    pending.push(child)
                  }
                } else if @decode.array_length(cursor) is Some(n) {
                  spend(b, n)
                  for k in 0..<n {
                    pending.push(@decode.element_at(cursor, k).unwrap())
                  }
                } else if @decode.view(cursor) is @decode.TextValue(text) {
                  spend(b, text.length())
                }
              }
              let value = if @decode.object_length(raw) == Some(1) {
                let (tag, child) = @decode.field_at(raw, 0).unwrap()
                match tag {
                  "$param" => {
                    let name = read(@decode.text(child))
                    match parameter_named(source, name) {
                      Some(d) => Parameter(d)
                      None => raise Stop(UnknownParameter(name, raw))
                    }
                  }
                  "$binding" => {
                    let name = read(@decode.text(child))
                    match @binding.find(bindings, name) {
                      Some(d) => Binding(d)
                      None => raise Stop(UnknownBinding(name, raw))
                    }
                  }
                  _ => Literal(raw)
                }
              } else {
                Literal(raw)
              }
              entries.push({
                stage_index,
                input_name,
                field_name,
                source: raw,
                value,
              })
            }
          }
        }
      }
    }
    Ok({ source, bindings, entries, work: limits.max_work - b.remaining, })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn source(slots : Slots) -> @stages.Source {
  slots.source
}

///|
pub fn bindings(slots : Slots) -> @binding.Declarations {
  slots.bindings
}

///|
pub fn count(slots : Slots) -> Int {
  slots.entries.length()
}

///|
pub fn at(slots : Slots, index : Int) -> Slot? {
  slots.entries.get(index)
}

///|
pub fn work(slots : Slots) -> Int {
  slots.work
}
