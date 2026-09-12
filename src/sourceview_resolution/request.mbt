///|
pub(all) struct RequestLimits {
  max_work : Int
  max_pairs : Int
  values : @value.Limits
}

///|
pub(all) enum RequestIssueKind {
  InvalidLimits
  ForeignSource
  ForeignInput
  WorkLimit
  PairLimit
  UnknownField(String)
  MissingField(String)
  IncompatibleParameter(String)
  IncompatibleBinding(String)
  Literal(@value.Issue)
} derive(Eq, Debug)

///|
pub struct RequestIssue {
  kind : RequestIssueKind
  source : @decode.Cursor?
}

///|
struct RequestContext {
  resolved : Resolved
  slots : @slots.Slots
  fields : Map[(Int, String), Array[@slots.Slot]]
  work : Int
}

///|
pub enum RequestValue {
  LiteralValue(@value.CheckedValue)
  ParameterValue(@parameters.Declaration)
  BindingValue(@bindings.Declaration)
}

///|
pub struct RequestField {
  slot : @slots.Slot
  contract : @contract.Contract
  value : RequestValue
}

///|
struct DirectRequest {
  context : RequestContext
  input : ResolvedInput
  fields : Array[RequestField]
  work : Int
  pairs : Int
  nodes : Int
  text : Int
}

///|
priv suberror RequestStop {
  RequestStop(RequestIssue)
}

///|
fn[T] request_fail(
  kind : RequestIssueKind,
  source : @decode.Cursor?,
) -> T raise RequestStop {
  raise RequestStop({ kind, source, })
}

///|
fn request_charge(
  b : Budget,
  n : Int,
  source : @decode.Cursor?,
) -> Unit raise RequestStop {
  if n > b.work {
    request_fail(WorkLimit, source)
  }
  b.work -= n
}

///|
/// Indexes the complete source-owned slot inventory once. No request type or
/// usage classification is established by this context alone.
pub fn prepare_requests(
  resolved : Resolved,
  slots : @slots.Slots,
  max_work : Int,
) -> Result[RequestContext, RequestIssue] {
  if max_work < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  if !physical_equal(
      @slots.source(slots),
      @inputs.source(resolved.owner.inputs),
    ) {
    return Err({ kind: ForeignSource, source: None, })
  }
  let b = { work: max_work, }
  let fields : Map[(Int, String), Array[@slots.Slot]] = Map([])
  try {
    request_charge(b, resolved.work, None)
    request_charge(b, @slots.work(slots), None)
    for i in 0..<@slots.count(slots) {
      let slot = @slots.at(slots, i).unwrap()
      request_charge(b, 1, Some(slot.source))
      request_charge(b, slot.input_name.length(), Some(slot.source))
      let key = (slot.stage_index, slot.input_name)
      match fields.get(key) {
        Some(list) => list.push(slot)
        None => fields[key] = [slot]
      }
    }
    Ok({ resolved, slots, fields, work: max_work - b.work, })
  } catch {
    RequestStop(e) => Err(e)
  }
}

///|
/// Direct request coverage and static values only. Parameter/Binding variants
/// require concrete binding and request revalidation before executable planning.
pub fn check_direct_request(
  context : RequestContext,
  input : ResolvedInput,
  limits : RequestLimits,
) -> Result[DirectRequest, RequestIssue] {
  let source = Some(input.declaration.source)
  if limits.max_work < 0 ||
    limits.max_pairs < 0 ||
    limits.values.max_nodes < 0 ||
    limits.values.max_depth < 0 ||
    limits.values.max_text_bytes < 0 {
    return Err({ kind: InvalidLimits, source, })
  }
  if !physical_equal(context.resolved.owner, input.owner) {
    return Err({ kind: ForeignInput, source, })
  }
  let b = { work: limits.max_work, }
  let mut pairs = limits.max_pairs
  let mut nodes = limits.values.max_nodes
  let mut text = limits.values.max_text_bytes
  let fields = []
  let seen : Map[String, Bool] = Map([])
  let schema = @environment.source_request_schema(input.selected.contract)
  try {
    request_charge(b, 1, source)
    request_charge(b, input.declaration.input_name.length(), source)
    let slots = context.fields
      .get((input.declaration.stage_index, input.declaration.input_name))
      .unwrap_or([])
    for slot in slots {
      let at = Some(slot.source)
      request_charge(b, 1, at)
      request_charge(b, slot.field_name.length(), at)
      let target = match
        @row.lookup(schema, @row.Unqualified(slot.field_name)) {
        Some(c) => c
        None => request_fail(UnknownField(slot.field_name), at)
      }
      seen[slot.field_name] = true
      let value = match slot.value {
        @slots.Literal(cursor) => {
          let (checked, used_nodes, used_text) = match
            @value.admit_usage(target, cursor, {
              max_nodes: nodes,
              max_depth: limits.values.max_depth,
              max_text_bytes: text,
            }) {
            Ok(v) => v
            Err(e) => request_fail(Literal(e), at)
          }
          nodes -= used_nodes
          text -= used_text
          LiteralValue(checked)
        }
        @slots.Parameter(declaration) => {
          let (compatible, used) = @contract.assignable_usage(
            declaration.parameter_type.contract,
            target,
            pairs,
          ) catch {
            _ => request_fail(PairLimit, at)
          }
          pairs -= used
          if !compatible {
            request_fail(IncompatibleParameter(declaration.name), at)
          }
          ParameterValue(declaration)
        }
        @slots.Binding(declaration) => {
          let compatible = match (declaration.constraint, target.shape) {
            (@bindings.Resource(a), @contract.ResourceRef(resource_kind=kind)) => {
              request_charge(b, a.length(), at)
              request_charge(b, kind.length(), at)
              a == kind
            }
            (@bindings.Artifact(a), @contract.ArtifactRef(media_type=expected)) => {
              if a is Some(s) {
                request_charge(b, s.length(), at)
              }
              if expected is Some(s) {
                request_charge(b, s.length(), at)
              }
              expected is None || a == expected
            }
            _ => false
          }
          if !compatible {
            request_fail(IncompatibleBinding(declaration.name), at)
          }
          BindingValue(declaration)
        }
      }
      fields.push({ slot, contract: target, value, })
    }
    for i in 0..<@row.field_count(schema) {
      let field = @row.field_at(schema, i).unwrap()
      let name = @row.reference_name(field.name)
      request_charge(b, 1, source)
      request_charge(b, name.length(), source)
      if !seen.contains(name) {
        request_fail(
          MissingField(name),
          Some(input.declaration.request.unwrap_or(input.declaration.source)),
        )
      }
    }
    Ok({
      context,
      input,
      fields,
      work: limits.max_work - b.work,
      pairs: limits.max_pairs - pairs,
      nodes: limits.values.max_nodes - nodes,
      text: limits.values.max_text_bytes - text,
    })
  } catch {
    RequestStop(e) => Err(e)
  }
}

///|
pub fn request_context_source(v : RequestContext) -> Resolved {
  v.resolved
}

///|
pub fn request_context_slots(v : RequestContext) -> @slots.Slots {
  v.slots
}

///|
pub fn request_context_work(v : RequestContext) -> Int {
  v.work
}

///|
pub fn request_context(v : DirectRequest) -> RequestContext {
  v.context
}

///|
pub fn request_input(v : DirectRequest) -> ResolvedInput {
  v.input
}

///|
pub fn request_field_count(v : DirectRequest) -> Int {
  v.fields.length()
}

///|
pub fn request_field_at(v : DirectRequest, i : Int) -> RequestField? {
  v.fields.get(i)
}

///|
pub fn request_usage(v : DirectRequest) -> (Int, Int, Int, Int) {
  (v.work, v.pairs, v.nodes, v.text)
}
