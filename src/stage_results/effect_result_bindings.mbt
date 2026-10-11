///|
pub(all) enum EffectResultBindingIssueKind {
  InvalidLimits
  WorkLimit
  ForeignProgram
  MissingResult
  MissingTableInput
  MissingField
  InvalidCommandTarget
  UnsupportedTableInput
} derive(Eq, Debug)

///|
pub struct EffectResultBindingIssue {
  kind : EffectResultBindingIssueKind
  stage_index : Int
  effect_id : String
  field : String?
}

///|
pub fn effect_result_binding_issue_kind(
  issue : EffectResultBindingIssue,
) -> EffectResultBindingIssueKind {
  issue.kind
}

///|
pub fn effect_result_binding_issue_stage(
  issue : EffectResultBindingIssue,
) -> Int {
  issue.stage_index
}

///|
pub fn effect_result_binding_issue_effect(
  issue : EffectResultBindingIssue,
) -> String {
  issue.effect_id
}

///|
pub fn effect_result_binding_issue_field(
  issue : EffectResultBindingIssue,
) -> String? {
  issue.field
}

///|
pub struct EffectResultBinding {
  header : @syntax.EffectHeader
  result : @results.ResultDefinition?
  table_input : @results.TableInputDefinition?
  fields : Array[EffectResultFieldBinding]
}

///|
pub(all) enum EffectResultFieldRole {
  EffectSelector
  EffectUpsertKey
  EffectCommandTarget
  EffectValue(String)
} derive(Eq, Debug)

///|
pub struct EffectResultFieldBinding {
  role : EffectResultFieldRole
  field : @schema.Field
}

///|
pub fn effect_result_field_binding_role(
  binding : EffectResultFieldBinding,
) -> EffectResultFieldRole {
  binding.role
}

///|
pub fn effect_result_field_binding_field(
  binding : EffectResultFieldBinding,
) -> @schema.Field {
  binding.field
}

///|
pub fn effect_result_field_binding_count(binding : EffectResultBinding) -> Int {
  binding.fields.length()
}

///|
pub fn effect_result_field_binding_at(
  binding : EffectResultBinding,
  index : Int,
) -> EffectResultFieldBinding? {
  binding.fields.get(index)
}

///|
pub fn effect_result_binding_header(
  binding : EffectResultBinding,
) -> @syntax.EffectHeader {
  binding.header
}

///|
pub fn effect_result_binding_result(
  binding : EffectResultBinding,
) -> @results.ResultDefinition? {
  binding.result
}

///|
/// A private Table source is never returned through the public Result getter.
pub fn effect_result_binding_table_input(
  binding : EffectResultBinding,
) -> @results.TableInputDefinition? {
  binding.table_input
}

///|
pub struct EffectResultBindings {
  owner : Checked
  headers : @syntax.EffectHeaders
  members : Array[EffectResultBinding]
  work : Int
}

///|
pub fn effect_result_bindings_owner(value : EffectResultBindings) -> Checked {
  value.owner
}

///|
pub fn effect_result_bindings_headers(
  value : EffectResultBindings,
) -> @syntax.EffectHeaders {
  value.headers
}

///|
pub fn effect_result_binding_count(value : EffectResultBindings) -> Int {
  value.members.length()
}

///|
pub fn effect_result_binding_at(
  value : EffectResultBindings,
  index : Int,
) -> EffectResultBinding? {
  value.members.get(index)
}

///|
pub fn effect_result_bindings_work(value : EffectResultBindings) -> Int {
  value.work
}

///|
fn binding_issue(
  kind : EffectResultBindingIssueKind,
  header : @syntax.EffectHeader,
  field? : String? = None,
) -> EffectResultBindingIssue {
  {
    kind,
    stage_index: @syntax.effect_header_stage(header),
    effect_id: @syntax.effect_header_id(header),
    field,
  }
}

///|
fn binding_field(
  header : @syntax.EffectHeader,
  result : @results.ResultDefinition,
  name : String,
) -> Result[@schema.Field, EffectResultBindingIssue] {
  match @schema.lookup_reference(@results.output_schema(result), name) {
    None => Err(binding_issue(MissingField, header, field=Some(name)))
    Some(field) => Ok(field)
  }
}

///|
fn binding_charge(
  header : @syntax.EffectHeader,
  remaining : Int,
  amount : Int,
) -> Result[Int, EffectResultBindingIssue] {
  if amount > remaining {
    Err(binding_issue(WorkLimit, header))
  } else {
    Ok(remaining - amount)
  }
}

///|
/// Bind authored member fields to the admitted Stage Result schema, or a
/// whole-Relation Store source to its checked private Table declaration.
/// This retains exact source ownership and checked field contracts, and
/// rejects a Command target that is not a non-null ResourceRef. It does not establish
/// Mapping/Command compatibility, current authority, Preview, or apply
/// admission. The binding is not an execution permit.
pub fn bind_effect_results(
  headers : @syntax.EffectHeaders,
  checked : Checked,
  max_work : Int,
) -> Result[EffectResultBindings, EffectResultBindingIssue] {
  if max_work < 0 {
    return Err({
      kind: InvalidLimits,
      stage_index: -1,
      effect_id: "",
      field: None,
    })
  }
  let program = match @parameters.complete_program(
    @parameters.operations_source(operations(checked)),
  ) {
    Some(program) => program
    None =>
      return Err({
        kind: ForeignProgram,
        stage_index: -1,
        effect_id: "",
        field: None,
      })
  }
  if !physical_equal(@syntax.effect_headers_owner(headers), program) {
    return Err({
      kind: ForeignProgram,
      stage_index: -1,
      effect_id: "",
      field: None,
    })
  }
  let count = @syntax.effect_header_count(headers)
  let first = @syntax.effect_header_at(headers, 0)
  if count > max_work {
    return Err(binding_issue(WorkLimit, first.unwrap()))
  }
  let mut remaining = max_work - count
  let members : Array[EffectResultBinding] = []
  for index in 0..<count {
    let header = @syntax.effect_header_at(headers, index).unwrap()
    let table_input = match @syntax.effect_header_source_table_input(header) {
      None => None
      Some(name) => {
        if @syntax.effect_header_kind(header) != "store" ||
          @syntax.effect_header_source_result(header) is Some(_) {
          return Err(binding_issue(UnsupportedTableInput, header))
        }
        guard stage_table_inputs_at(
            checked,
            @syntax.effect_header_stage(header),
          )
          is Some(inputs) &&
          @results.lookup_table_input(inputs, name) is Some(input) else {
          return Err(binding_issue(MissingTableInput, header))
        }
        Some(input)
      }
    }
    let fields : Array[EffectResultFieldBinding] = []
    let result = match @syntax.effect_header_source_result(header) {
      None => None
      Some(name) => {
        let stage = match
          stage_at(checked, @syntax.effect_header_stage(header)) {
          Some(value) => value
          None => return Err(binding_issue(MissingResult, header))
        }
        match @results.lookup(stage, name) {
          Some(value) => Some(value)
          None => return Err(binding_issue(MissingResult, header))
        }
      }
    }
    if result is Some(definition) {
      let body = @decode.open_object(@syntax.effect_header_body(header)).unwrap()
      let kind = @syntax.effect_header_kind(header)
      let mut direct : @decode.Cursor? = None
      let mut direct_role = EffectSelector
      if kind == "update" || kind == "delete" {
        if @decode.lookup(body, "id") is Some(value) {
          direct = Some(value)
        } else if @decode.lookup(body, "match") is Some(value) {
          let match_body = @decode.open_object(value).unwrap()
          direct = @decode.lookup(match_body, "result_field")
        }
      } else if kind == "upsert" {
        direct = @decode.lookup(body, "key")
        direct_role = EffectUpsertKey
      } else if kind == "command" {
        let target = @decode.lookup(body, "target").unwrap()
        direct = @decode.lookup(@decode.open_object(target).unwrap(), "field")
        direct_role = EffectCommandTarget
      }
      if direct is Some(cursor) {
        remaining = match binding_charge(header, remaining, 1) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        let name = @decode.text(cursor).unwrap()
        match binding_field(header, definition, name) {
          Ok(field) => {
            if direct_role == EffectCommandTarget &&
              @contract.nonnull_resource_ref_kind(@schema.field_contract(field))
              is None {
              return Err(
                binding_issue(InvalidCommandTarget, header, field=Some(name)),
              )
            }
            fields.push({ role: direct_role, field, })
          }
          Err(issue) => return Err(issue)
        }
      }
      let values = if kind == "command" {
        @decode.lookup(body, "input")
      } else if kind == "update" || kind == "upsert" {
        @decode.lookup(body, "set")
      } else {
        None
      }
      if values is Some(map) {
        let n = @decode.object_length(map).unwrap()
        remaining = match binding_charge(header, remaining, n) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        for i in 0..<n {
          let (target, value) = @decode.field_at(map, i).unwrap()
          let wrapper = @decode.open_object(value).unwrap()
          if @decode.lookup(wrapper, "field") is Some(field) {
            let name = @decode.text(field).unwrap()
            match binding_field(header, definition, name) {
              Ok(field) => fields.push({ role: EffectValue(target), field, })
              Err(issue) => return Err(issue)
            }
          }
        }
      }
    }
    members.push({ header, result, table_input, fields, })
  }
  Ok({ owner: checked, headers, members, work: max_work - remaining, })
}
