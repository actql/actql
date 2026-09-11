///|
pub enum ParameterIssue {
  InvalidLimits
  WorkLimit
  Syntax(@expression.Issue)
  References(@references.Issue)
}

///|
struct ParameterUses {
  body : Body
  index : @references.Index
  work : Int
}

///|
priv suberror ParameterStop {
  ParameterStop(ParameterIssue)
}

///|
fn parameter_spend(b : Budget, n : Int) -> Unit raise ParameterStop {
  if n > b.remaining {
    raise ParameterStop(WorkLimit)
  }
  b.remaining -= n
}

///|
fn is_hole(cursor : @decode.Cursor) -> Bool {
  @decode.object_length(cursor) == Some(1) &&
  @decode.field_at(cursor, 0).unwrap().0 == "$param"
}

///|
/// Index operation and Effect value references in source stage coordinates.
/// Input/SourceView and opaque Binding references are not included here.
pub fn collect_parameter_uses(
  body : Body,
  limits : @collection.Limits,
) -> Result[ParameterUses, ParameterIssue] {
  if limits.max_work < 0 ||
    limits.max_slots < 0 ||
    limits.max_references < 0 ||
    limits.max_pointer_units < 0 ||
    limits.max_direct_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let b : Budget = { remaining: limits.max_work, }
  let collected = @stages.collection(body.owner)
  let previous = @collection.index(collected)
  let slots : Array[@expression.ParameterOccurrences] = []
  let direct : Array[@decode.Cursor] = []
  try {
    parameter_spend(b, body.work)
    let old_pointers = @references.pointer_units(previous)
    if old_pointers > limits.max_pointer_units {
      raise ParameterStop(References(PointerLimit))
    }
    let old_text = @collection.direct_text_bytes(collected)
    if old_text > limits.max_direct_text_bytes {
      raise ParameterStop(WorkLimit)
    }
    let mut text_left = limits.max_direct_text_bytes - old_text
    let mut count = 0
    let append = fn(
      occurrences : @expression.ParameterOccurrences,
    ) -> Unit raise ParameterStop {
      if slots.length() >= limits.max_slots {
        raise ParameterStop(References(SlotLimit))
      }
      let n = @expression.parameter_occurrence_count(occurrences)
      if n > limits.max_references - count {
        raise ParameterStop(References(ReferenceLimit))
      }
      count += n
      parameter_spend(b, 1)
      slots.push(occurrences)
    }
    let mut i = 0
    while @references.slot_at(previous, i) is Some(slot) {
      append(slot)
      i += 1
    }
    for selector in body.selector_list {
      let occurrences = match
        @expression.collect_parameter_occurrences(
          @selector.expression(selector),
          max_work=b.remaining,
        ) {
        Ok(v) => v
        Err(e) => raise ParameterStop(Syntax(e))
      }
      parameter_spend(b, @expression.parameter_occurrence_work(occurrences))
      append(occurrences)
    }
    let add = fn(cursor : @decode.Cursor) -> Unit raise ParameterStop {
      parameter_spend(b, 1)
      if is_hole(cursor) {
        if direct.length() >= limits.max_slots - slots.length() {
          raise ParameterStop(References(SlotLimit))
        }
        direct.push(cursor)
      }
    }
    for (name, effects) in body.fields {
      if name != "effects" {
        continue
      }
      let n = @decode.object_length(effects).unwrap()
      parameter_spend(b, n)
      for i in 0..<n {
        let declaration = @decode.field_at(effects, i).unwrap().1
        let n = @decode.object_length(declaration).unwrap()
        parameter_spend(b, n)
        for j in 0..<n {
          let (kind, effect) = @decode.field_at(declaration, j).unwrap()
          if kind == "meta" {
            continue
          }
          parameter_spend(b, @decode.object_length(effect).unwrap())
          let view = @decode.open_object(effect).unwrap()
          if @decode.lookup(view, "max_items") is Some(bound) {
            add(bound)
          }
          if kind == "update" || kind == "delete" {
            if @decode.lookup(view, "ids") is Some(ids) {
              add(ids)
              if @decode.array_length(ids) is Some(n) {
                parameter_spend(b, n)
                for k in 0..<n {
                  add(@decode.element_at(ids, k).unwrap())
                }
              }
            }
            if @decode.lookup(view, "external_id") is Some(external) {
              if @decode.object_length(external) is Some(n) {
                parameter_spend(b, n)
                if @decode.lookup(
                    @decode.open_object(external).unwrap(),
                    "value",
                  )
                  is Some(value) {
                  add(value)
                }
              }
            }
          }
          let map_key = if kind == "command" { "input" } else { "set" }
          if kind == "command" || kind == "update" || kind == "upsert" {
            if @decode.lookup(view, map_key) is Some(values) {
              if @decode.object_length(values) is Some(n) {
                parameter_spend(b, n)
                for k in 0..<n {
                  let value = @decode.field_at(values, k).unwrap().1
                  // EffectValue is not common expression syntax. Only the
                  // immediate payload of an exact literal wrapper is a hole.
                  if @decode.object_length(value) == Some(1) {
                    let (tag, payload) = @decode.field_at(value, 0).unwrap()
                    if tag == "literal" {
                      add(payload)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    for raw in direct {
      parameter_spend(b, 2)
      let expression = match
        @expression.admit(raw, {
          max_nodes: b.remaining,
          max_depth: 2,
          max_tokens: 0,
          max_text_bytes: text_left,
          tree: {
            max_nodes: 2,
            max_depth: 1,
            max_string_bytes: text_left,
            max_total_string_bytes: text_left,
          },
        }) {
        Ok(v) => v
        Err(e) => raise ParameterStop(Syntax(e))
      }
      let used = @expression.usage(expression)
      parameter_spend(b, used.nodes)
      text_left -= used.text_bytes
      let occurrences = match
        @expression.collect_parameter_occurrences(
          expression,
          max_work=b.remaining,
        ) {
        Ok(v) => v
        Err(e) => raise ParameterStop(Syntax(e))
      }
      parameter_spend(b, @expression.parameter_occurrence_work(occurrences))
      append(occurrences)
    }
    parameter_spend(b, count)
    let index = match
      @references.build(
        body.source,
        @stages.declarations(@stages.source(body.owner)),
        slots,
        {
          max_slots: limits.max_slots,
          max_references: limits.max_references,
          max_pointer_units: Int::min(
            b.remaining,
            limits.max_pointer_units - old_pointers,
          ),
        },
      ) {
      Ok(v) => v
      Err(e) => raise ParameterStop(References(e))
    }
    parameter_spend(b, @references.pointer_units(index))
    Ok({ body, index, work: limits.max_work - b.remaining, })
  } catch {
    ParameterStop(e) => Err(e)
  }
}

///|
pub fn parameter_body(uses : ParameterUses) -> Body {
  uses.body
}

///|
pub fn parameter_index(uses : ParameterUses) -> @references.Index {
  uses.index
}

///|
pub fn parameter_work(uses : ParameterUses) -> Int {
  uses.work
}
