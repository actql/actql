///|
pub enum Issue {
  InvalidLimits
  WorkLimit
  Decode(@decode.Issue)
  Steps(@steps.Issue)
  Selector(@selector.Issue)
  InvalidMetadata(@decode.Cursor)
  InvalidEffect(@decode.Cursor)
}

///|
pub(all) struct Limits {
  max_work : Int
  selectors : @expression.Limits
}

///|
struct Body {
  owner : @stages.CollectedStage
  source : @decode.Cursor
  fields : Array[(String, @decode.Cursor)]
  steps : @steps.Steps
  step_index : Int
  annotations : Map[Int, Bool]
  selectors : Map[Int, @selector.Selector]
  selector_list : Array[@selector.Selector]
  work : Int
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
fn open(c : @decode.Cursor) -> @decode.ObjectView raise Stop {
  match @decode.open_object(c) {
    Ok(v) => v
    Err(e) => raise Stop(Decode(e))
  }
}

///|
fn annotation(
  root : @decode.Cursor,
  declaration : @decode.Cursor,
  omitted : Map[Int, Bool],
  b : Budget,
) -> Unit raise Stop {
  // Short-form Inputs are not objects. Annotations exist only on declarations,
  // never on arbitrary nested objects whose business keys happen to be meta.
  if @decode.object_length(declaration) is Some(n) {
    spend(b, n)
    let view = open(declaration)
    if @decode.lookup(view, "meta") is Some(meta) {
      let n = match @decode.object_length(meta) {
        Some(n) if n > 0 => n
        _ => raise Stop(InvalidMetadata(meta))
      }
      spend(b, n)
      for i in 0..<n {
        let (key, child) = @decode.field_at(meta, i).unwrap()
        spend(b, key.length())
        if key.has_prefix("actql_") {
          raise Stop(InvalidMetadata(child))
        }
      }
      // All descendant JSON validity and normalization were checked by the
      // opaque Stage source parser. Do not re-interpret metadata descendants.
      omitted[@decode.tree_index(root, meta).unwrap()] = true
    }
  }
}

///|
/// Prepare local_body from one source-bound stage. This is source projection,
/// not complete Input/Effect admission, used-reference closure or a stage CID.
pub fn prepare(
  owner : @stages.CollectedStage,
  limits : Limits,
) -> Result[Body, Issue] {
  let e = limits.selectors
  let t = e.tree
  if limits.max_work < 0 ||
    e.max_nodes < 0 ||
    e.max_depth < 0 ||
    e.max_text_bytes < 0 ||
    e.max_tokens < 0 ||
    t.max_nodes < 0 ||
    t.max_depth < 0 ||
    t.max_string_bytes < 0 ||
    t.max_total_string_bytes < 0 {
    return Err(InvalidLimits)
  }
  let b : Budget = { remaining: limits.max_work, }
  try {
    spend(b, @stages.collection_work(owner))
    let steps = match
      @steps.prepare(@stages.collection(owner), max_work=b.remaining) {
      Ok(v) => v
      Err(e) => raise Stop(Steps(e))
    }
    spend(b, @steps.work(steps))
    let source = @syntax.stage_body(
      @stages.stage_at(@stages.source(owner), @stages.stage_index(owner)).unwrap(),
    )
    let view = open(source)
    let fields = []
    let annotations : Map[Int, Bool] = Map([])
    let selectors : Map[Int, @selector.Selector] = Map([])
    let selector_list = []
    let mut remaining = e
    // Explicit canonical order; absent effects is emitted separately as {}.
    for name in ["effects", "from", "inputs", "results", "steps"] {
      if @decode.lookup(view, name) is Some(value) {
        fields.push((name, value))
      }
    }
    let step_source = @decode.lookup(view, "steps").unwrap()
    for name in ["inputs", "results", "effects"] {
      if @decode.lookup(view, name) is Some(declarations) {
        let n = @decode.object_length(declarations).unwrap()
        spend(b, n)
        for i in 0..<n {
          let (_, declaration) = @decode.field_at(declarations, i).unwrap()
          annotation(source, declaration, annotations, b)
          if name != "effects" {
            continue
          }
          let n = match @decode.object_length(declaration) {
            Some(n) => n
            None => raise Stop(InvalidEffect(declaration))
          }
          spend(b, n)
          let mut kinds = 0
          for j in 0..<n {
            let (kind, body) = @decode.field_at(declaration, j).unwrap()
            if kind == "meta" {
              continue
            }
            match kind {
              "create" | "update" | "upsert" | "delete" | "command" | "store" =>
                ()
              _ => raise Stop(InvalidEffect(body))
            }
            kinds += 1
            let count = match @decode.object_length(body) {
              Some(n) => n
              None => raise Stop(InvalidEffect(body))
            }
            spend(b, count)
            let body_view = open(body)
            if kind == "update" || kind == "delete" {
              if @decode.lookup(body_view, "where") is Some(predicates) {
                let count = match @decode.array_length(predicates) {
                  Some(n) if n > 0 => n
                  _ => raise Stop(InvalidEffect(predicates))
                }
                spend(b, count)
                for k in 0..<count {
                  let raw = @decode.element_at(predicates, k).unwrap()
                  let selected = match
                    @selector.admit(raw, remaining, max_work=b.remaining) {
                    Ok(v) => v
                    Err(e) => raise Stop(Selector(e))
                  }
                  spend(b, @selector.work(selected))
                  let used = @expression.usage(@selector.expression(selected))
                  remaining = {
                    ..remaining,
                    max_nodes: remaining.max_nodes - used.nodes,
                    max_text_bytes: remaining.max_text_bytes - used.text_bytes,
                    max_tokens: remaining.max_tokens - used.tokens,
                  }
                  selectors[@decode.tree_index(source, raw).unwrap()] = selected
                  selector_list.push(selected)
                }
              }
            }
          }
          if kinds != 1 {
            raise Stop(InvalidEffect(declaration))
          }
        }
      }
    }
    // Bound raw source traversal as well as normalized expression work. The
    // source parser already establishes JSON scalar validity for these values.
    let pending = fields.map(pair => pair.1)
    while pending.pop() is Some(cursor) {
      spend(b, 1)
      let index = @decode.tree_index(source, cursor).unwrap()
      if index == @decode.tree_index(source, step_source).unwrap() ||
        annotations.contains(index) ||
        selectors.contains(index) {
        continue
      }
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
    Ok({
      owner,
      source,
      fields,
      steps,
      step_index: @decode.tree_index(source, step_source).unwrap(),
      annotations,
      selectors,
      selector_list,
      work: limits.max_work - b.remaining,
    })
  } catch {
    Stop(issue) => Err(issue)
  }
}

///|
priv enum Frame {
  Value(@decode.Cursor)
  ArrayRest(@decode.Cursor, Int, Int)
  ObjectRest(Array[(String, @decode.Cursor)], Int)
}

///|
pub fn emit(
  body : Body,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if body.fields.length() == 0 || body.fields[0].0 != "effects" {
    @encode.key(writer, "effects")
    @encode.begin_object(writer)
    @encode.end_object(writer)
  }
  let pending : Array[Frame] = [ObjectRest(body.fields, 0)]
  while pending.pop() is Some(frame) {
    match frame {
      Value(cursor) => {
        let index = @decode.tree_index(body.source, cursor).unwrap()
        if index == body.step_index {
          @steps.emit(body.steps, writer)
        } else if body.selectors.get(index) is Some(selector) {
          @expression.emit_source(@selector.expression(selector), writer)
        } else if @decode.array_length(cursor) is Some(n) {
          @encode.begin_array(writer)
          pending.push(ArrayRest(cursor, 0, n))
        } else if @decode.object_length(cursor) is Some(n) {
          @encode.begin_object(writer)
          let fields = []
          for i in 0..<n {
            let pair = @decode.field_at(cursor, i).unwrap()
            if !body.annotations.contains(
                @decode.tree_index(body.source, pair.1).unwrap(),
              ) {
              fields.push(pair)
            }
          }
          fields.sort_by((a, b) => @canonical.compare_utf16(a.0, b.0))
          pending.push(ObjectRest(fields, 0))
        } else {
          match @decode.view(cursor) {
            @decode.NullValue => @encode.null_value(writer)
            @decode.BoolValue(v) => @encode.bool_value(writer, v)
            @decode.NumberValue(v) => @encode.number_value(writer, v)
            @decode.TextValue(v) => @encode.string_value(writer, v)
            _ => raise @encode.InvalidStructure
          }
        }
      }
      ArrayRest(cursor, i, n) =>
        if i == n {
          @encode.end_array(writer)
        } else {
          pending.push(ArrayRest(cursor, i + 1, n))
          pending.push(Value(@decode.element_at(cursor, i).unwrap()))
        }
      ObjectRest(fields, i) =>
        if i == fields.length() {
          @encode.end_object(writer)
        } else {
          @encode.key(writer, fields[i].0)
          pending.push(ObjectRest(fields, i + 1))
          pending.push(Value(fields[i].1))
        }
    }
  }
}

///|
pub fn stage(body : Body) -> @stages.CollectedStage {
  body.owner
}

///|
pub fn steps(body : Body) -> @steps.Steps {
  body.steps
}

///|
pub fn selector_count(body : Body) -> Int {
  body.selector_list.length()
}

///|
pub fn selector_at(body : Body, index : Int) -> @selector.Selector? {
  body.selector_list.get(index)
}

///|
pub fn work(body : Body) -> Int {
  body.work
}
