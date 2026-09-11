///|
pub(all) struct Limits {
  max_work : Int
  max_slots : Int
  max_references : Int
  max_pointer_units : Int
  max_request_text_bytes : Int
}

///|
pub enum Issue {
  InvalidLimits
  StageCountMismatch
  ForeignStage(Int)
  WorkLimit
  SlotLimit
  ReferenceLimit
  PointerLimit
  Syntax(@expression.Issue)
  Parameters(@parameters.Issue)
}

///|
pub struct BindingReference {
  name : String
  path : String
  declaration : @bindings.Declaration
}

///|
struct Index {
  parameters : @parameters.Index
  bindings : Array[BindingReference]
  used_bindings : Array[@bindings.Declaration]
}

///|
priv struct BindingSlot {
  source : @requests.Slot
  declaration : @bindings.Declaration
}

///|
struct Inventory {
  requests : @requests.Slots
  stages : Array[@body.ParameterUses]
  locals : Array[Index]
  program : Index
  work : Int
}

///|
priv struct Budget {
  mut work : Int
  mut pointers : Int
  mut slots : Int
  mut references : Int
  mut text : Int
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn spend(b : Budget, n : Int) -> Unit raise Stop {
  if n > b.work {
    raise Stop(WorkLimit)
  }
  b.work -= n
}

///|
fn retain_pointer(b : Budget, n : Int) -> Unit raise Stop {
  if n > b.pointers {
    raise Stop(PointerLimit)
  }
  b.pointers -= n
}

///|
fn slot(b : Budget, refs : Int) -> Unit raise Stop {
  if b.slots == 0 {
    raise Stop(SlotLimit)
  }
  if refs > b.references {
    raise Stop(ReferenceLimit)
  }
  b.slots -= 1
  b.references -= refs
  spend(b, 1)
  spend(b, refs)
}

///|
fn piece(out : StringBuilder, text : String, b : Budget) -> Unit raise Stop {
  retain_pointer(b, text.length())
  spend(b, text.length())
  out.write_string(text)
}

///|
fn escaped(out : StringBuilder, text : String, b : Budget) -> Unit raise Stop {
  piece(out, "/", b)
  for ch in text.iter() {
    piece(
      out,
      match ch {
        '~' => "~0"
        '/' => "~1"
        _ => ch.to_string()
      },
      b,
    )
  }
}

///|
fn make_index(
  root : @decode.Cursor,
  owner : @stages.Source,
  occurrences : Array[@expression.ParameterOccurrences],
  binding_slots : Array[BindingSlot],
  program : Bool,
  b : Budget,
) -> Index raise Stop {
  spend(b, occurrences.length())
  let mut reference_count = 0
  for o in occurrences {
    reference_count += @expression.parameter_occurrence_count(o)
  }
  let parameters = match
    @parameters.build(root, @stages.declarations(owner), occurrences, {
      max_slots: occurrences.length(),
      max_references: reference_count,
      max_pointer_units: Int::min(b.pointers, b.work),
    }) {
    Ok(v) => v
    Err(e) => raise Stop(Parameters(e))
  }
  let n = @parameters.pointer_units(parameters)
  retain_pointer(b, n)
  spend(b, n)
  let bindings : Array[BindingReference] = []
  let used : Map[String, @bindings.Declaration] = Map([])
  spend(b, binding_slots.length())
  for binding in binding_slots {
    let source = binding.source
    let declaration = binding.declaration
    let out = StringBuilder()
    if program {
      piece(out, "/stages/", b)
      piece(out, source.stage_index.to_string(), b)
    }
    piece(out, "/inputs", b)
    escaped(out, source.input_name, b)
    piece(out, "/request", b)
    escaped(out, source.field_name, b)
    bindings.push({
      name: declaration.name,
      path: out.to_string(),
      declaration,
    })
    used[declaration.name] = declaration
  }
  bindings.sort_by((a, b) => @canonical.compare_utf16(a.path, b.path))
  let used_bindings = used.values().collect()
  used_bindings.sort_by((a, b) => @canonical.compare_utf16(a.name, b.name))
  { parameters, bindings, used_bindings, }
}

///|
/// Compose every stage's operation/Effect uses with the actual Program's static
/// request slots. This closes reference coordinates, not Program validity.
pub fn prepare(
  requests : @requests.Slots,
  stages : Array[@body.ParameterUses],
  limits : Limits,
) -> Result[Inventory, Issue] {
  if limits.max_work < 0 ||
    limits.max_slots < 0 ||
    limits.max_references < 0 ||
    limits.max_pointer_units < 0 ||
    limits.max_request_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let owner = @requests.source(requests)
  let n = @stages.stage_count(owner)
  if stages.length() != n {
    return Err(StageCountMismatch)
  }
  let b : Budget = {
    work: limits.max_work,
    pointers: limits.max_pointer_units,
    slots: limits.max_slots,
    references: limits.max_references,
    text: limits.max_request_text_bytes,
  }
  try {
    spend(b, @requests.work(requests))
    spend(b, n)
    let occurrences : Array[Array[@expression.ParameterOccurrences]] = []
    let binding_slots : Array[Array[BindingSlot]] = []
    for i in 0..<n {
      let stage = @body.stage(@body.parameter_body(stages[i]))
      if @stages.stage_index(stage) != i ||
        !physical_equal(@stages.source(stage), owner) {
        raise Stop(ForeignStage(i))
      }
      spend(b, @body.parameter_work(stages[i]))
      let index = @body.parameter_index(stages[i])
      // Both inherited indices remain alive through the retained stage owner.
      retain_pointer(b, @parameters.pointer_units(index))
      retain_pointer(
        b,
        @parameters.pointer_units(@collection.index(@stages.collection(stage))),
      )
      let group = []
      let mut j = 0
      while @parameters.slot_at(index, j) is Some(o) {
        slot(b, @expression.parameter_occurrence_count(o))
        group.push(o)
        j += 1
      }
      occurrences.push(group)
      binding_slots.push([])
    }
    spend(b, @requests.count(requests))
    for i in 0..<@requests.count(requests) {
      let request = @requests.at(requests, i).unwrap()
      match request.value {
        @requests.Literal(_) => ()
        @requests.Binding(declaration) => {
          slot(b, 1)
          binding_slots[request.stage_index].push({
            source: request,
            declaration,
          })
        }
        @requests.Parameter(_) => {
          slot(b, 1)
          spend(b, 2)
          let expression = match
            @expression.admit(request.source, {
              max_nodes: b.work,
              max_depth: 2,
              max_text_bytes: b.text,
              max_tokens: 0,
              tree: {
                max_nodes: 2,
                max_depth: 1,
                max_string_bytes: b.text,
                max_total_string_bytes: b.text,
              },
            }) {
            Ok(v) => v
            Err(e) => raise Stop(Syntax(e))
          }
          let usage = @expression.usage(expression)
          spend(b, usage.nodes)
          b.text -= usage.text_bytes
          let o = match
            @expression.collect_parameter_occurrences(
              expression,
              max_work=b.work,
            ) {
            Ok(v) => v
            Err(e) => raise Stop(Syntax(e))
          }
          spend(b, @expression.parameter_occurrence_work(o))
          occurrences[request.stage_index].push(o)
        }
      }
    }
    let locals = []
    let all = []
    let all_bindings = []
    for i in 0..<n {
      let root = @stage.stage_body(@stages.stage_at(owner, i).unwrap())
      locals.push(
        make_index(root, owner, occurrences[i], binding_slots[i], false, b),
      )
      spend(b, occurrences[i].length())
      spend(b, binding_slots[i].length())
      for o in occurrences[i] {
        all.push(o)
      }
      for s in binding_slots[i] {
        all_bindings.push(s)
      }
    }
    let program = make_index(
      @stage.program_body(@stages.program(owner)),
      owner,
      all,
      all_bindings,
      true,
      b,
    )
    Ok({
      requests,
      stages: stages.copy(),
      locals,
      program,
      work: limits.max_work - b.work,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn requests(value : Inventory) -> @requests.Slots {
  value.requests
}

///|
pub fn stage_uses(value : Inventory, i : Int) -> @body.ParameterUses? {
  value.stages.get(i)
}

///|
pub fn stage_index(value : Inventory, i : Int) -> Index? {
  value.locals.get(i)
}

///|
pub fn program_index(value : Inventory) -> Index {
  value.program
}

///|
pub fn work(value : Inventory) -> Int {
  value.work
}

///|
pub fn parameters(value : Index) -> @parameters.Index {
  value.parameters
}

///|
pub fn binding_count(value : Index) -> Int {
  value.bindings.length()
}

///|
pub fn binding_at(value : Index, i : Int) -> BindingReference? {
  value.bindings.get(i)
}

///|
pub fn emit_binding_references(
  value : Index,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  for r in value.bindings {
    @encode.begin_object(writer)
    @encode.key(writer, "name")
    @encode.string_value(writer, r.name)
    @encode.key(writer, "path")
    @encode.string_value(writer, r.path)
    @encode.key(writer, "type")
    @bindings.emit_declaration(r.declaration, writer)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
}

///|
pub fn emit_used_bindings(
  value : Index,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for d in value.used_bindings {
    @encode.key(writer, d.name)
    @bindings.emit_declaration(d, writer)
  }
  @encode.end_object(writer)
}
