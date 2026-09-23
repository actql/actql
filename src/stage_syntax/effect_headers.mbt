///|
pub(all) enum EffectHeaderIssueKind {
  InvalidLimits
  BudgetExceeded
  InvalidDeclaration
  InvalidKind
  InvalidBody
  InvalidSourceResult
  InvalidFailurePolicy
  InvalidMaxItems
} derive(Eq, Debug)

///|
pub struct EffectHeaderIssue {
  kind : EffectHeaderIssueKind
  source : @wire.Cursor
}

///|
pub fn effect_header_issue_kind(
  issue : EffectHeaderIssue,
) -> EffectHeaderIssueKind {
  issue.kind
}

///|
pub fn effect_header_issue_source(issue : EffectHeaderIssue) -> @wire.Cursor {
  issue.source
}

///|
pub struct EffectHeader {
  stage_index : Int
  effect_id : String
  kind : String
  source_result : String?
  contract_ref : String
  failure_policy : String
  body : @wire.Cursor
}

///|
pub fn effect_header_stage(value : EffectHeader) -> Int {
  value.stage_index
}

///|
pub fn effect_header_id(value : EffectHeader) -> String {
  value.effect_id
}

///|
pub fn effect_header_kind(value : EffectHeader) -> String {
  value.kind
}

///|
pub fn effect_header_source_result(value : EffectHeader) -> String? {
  value.source_result
}

///|
pub fn effect_header_contract_ref(value : EffectHeader) -> String {
  value.contract_ref
}

///|
pub fn effect_header_failure_policy(value : EffectHeader) -> String {
  value.failure_policy
}

///|
pub fn effect_header_body(value : EffectHeader) -> @wire.Cursor {
  value.body
}

///|
pub struct EffectHeaders {
  owner : Program
  members : Array[EffectHeader]
  work : Int
}

///|
pub fn effect_header_count(value : EffectHeaders) -> Int {
  value.members.length()
}

///|
pub fn effect_header_at(value : EffectHeaders, index : Int) -> EffectHeader? {
  value.members.get(index)
}

///|
pub fn effect_headers_owner(value : EffectHeaders) -> Program {
  value.owner
}

///|
pub fn effect_headers_work(value : EffectHeaders) -> Int {
  value.work
}

///|
priv suberror EffectHeaderStop {
  EffectHeaderStop(EffectHeaderIssue)
}

///|
priv struct HeaderBudget {
  mut remaining : Int
}

///|
fn[T] header_fail(
  source : @wire.Cursor,
  kind : EffectHeaderIssueKind,
) -> T raise EffectHeaderStop {
  raise EffectHeaderStop({ kind, source, })
}

///|
fn header_spend(
  budget : HeaderBudget,
  count : Int,
  source : @wire.Cursor,
) -> Unit raise EffectHeaderStop {
  if count > budget.remaining {
    header_fail(source, BudgetExceeded)
  }
  budget.remaining -= count
}

///|
fn header_object(
  source : @wire.Cursor,
  fields : Array[String],
) -> @wire.ObjectView raise EffectHeaderStop {
  match @wire.closed_object(source, fields) {
    Ok(value) => value
    Err(_) => header_fail(source, InvalidBody)
  }
}

///|
fn header_required(
  object : @wire.ObjectView,
  name : String,
  source : @wire.Cursor,
) -> @wire.Cursor raise EffectHeaderStop {
  match @wire.lookup(object, name) {
    Some(value) => value
    None => header_fail(source, InvalidBody)
  }
}

///|
fn header_text(source : @wire.Cursor) -> String raise EffectHeaderStop {
  match @wire.text(source) {
    Ok(text) =>
      if text.is_empty() {
        header_fail(source, InvalidBody)
      } else {
        text
      }
    Err(_) => header_fail(source, InvalidBody)
  }
}

///|
fn header_from(
  body : @wire.ObjectView,
  stage : Stage,
  required : Bool,
  source : @wire.Cursor,
) -> String? raise EffectHeaderStop {
  match @wire.lookup(body, "from") {
    None =>
      if required {
        header_fail(source, InvalidSourceResult)
      } else {
        None
      }
    Some(from) => {
      let reference = header_object(from, ["result"])
      let result = header_text(header_required(reference, "result", from))
      if !stage.result_index.contains(result) {
        header_fail(from, InvalidSourceResult)
      }
      Some(result)
    }
  }
}

///|
fn header_object_shape(source : @wire.Cursor) -> Unit raise EffectHeaderStop {
  match @wire.object_length(source) {
    Some(_) => ()
    _ => header_fail(source, InvalidBody)
  }
}

///|
fn header_nonempty_array(source : @wire.Cursor) -> Unit raise EffectHeaderStop {
  match @wire.array_length(source) {
    Some(n) if n > 0 => ()
    _ => header_fail(source, InvalidBody)
  }
}

///|
fn header_positive_guard(source : @wire.Cursor) -> Unit raise EffectHeaderStop {
  match @wire.safe_integer(source) {
    Ok(value) if value > 0L => return
    _ => ()
  }
  if @wire.object_length(source) != Some(1) {
    header_fail(source, InvalidMaxItems)
  }
  let parameter = match @wire.closed_object(source, ["$param"]) {
    Ok(value) => value
    Err(_) => header_fail(source, InvalidMaxItems)
  }
  match @wire.lookup(parameter, "$param") {
    Some(value) =>
      match @wire.text(value) {
        Ok(name) if !name.is_empty() => ()
        _ => header_fail(value, InvalidMaxItems)
      }
    None => header_fail(source, InvalidMaxItems)
  }
}

///|
fn header_metadata(
  outer : @wire.ObjectView,
  budget : HeaderBudget,
) -> Unit raise EffectHeaderStop {
  match @wire.lookup(outer, "meta") {
    None => ()
    Some(node) => {
      let count = match @wire.object_length(node) {
        Some(n) if n > 0 => n
        _ => header_fail(node, InvalidDeclaration)
      }
      header_spend(budget, count, node)
      for i in 0..<count {
        let (key, value) = @wire.field_at(node, i).unwrap()
        if key.has_prefix("actql_") {
          header_fail(value, InvalidDeclaration)
        }
      }
    }
  }
}

///|
fn header_value_map(
  source : @wire.Cursor,
  nonempty : Bool,
  allow_field : Bool,
  budget : HeaderBudget,
) -> Unit raise EffectHeaderStop {
  let count = match @wire.object_length(source) {
    Some(n) if !nonempty || n > 0 => n
    _ => header_fail(source, InvalidBody)
  }
  header_spend(budget, count, source)
  for i in 0..<count {
    let (name, value) = @wire.field_at(source, i).unwrap()
    if name.is_empty() {
      header_fail(value, InvalidBody)
    }
    let wrapper = header_object(value, ["literal", "field"])
    let literal = @wire.lookup(wrapper, "literal")
    let field = @wire.lookup(wrapper, "field")
    if (literal is Some(_)) == (field is Some(_)) {
      header_fail(value, InvalidBody)
    }
    if field is Some(field_source) {
      if !allow_field {
        header_fail(field_source, InvalidSourceResult)
      }
      ignore(header_text(field_source))
    }
  }
}

///|
fn header_selector(
  body : @wire.ObjectView,
  stage : Stage,
  source : @wire.Cursor,
) -> String? raise EffectHeaderStop {
  let mut selector : String? = None
  for key in ["id", "match", "ids", "external_id", "where"] {
    if @wire.lookup(body, key) is Some(_) {
      if selector is Some(_) {
        header_fail(source, InvalidBody)
      }
      selector = Some(key)
    }
  }
  let selected = match selector {
    Some(value) => value
    None => header_fail(source, InvalidBody)
  }
  match selected {
    "id" => ignore(header_text(@wire.lookup(body, "id").unwrap()))
    "match" => {
      let node = @wire.lookup(body, "match").unwrap()
      let pair = header_object(node, ["target_field", "result_field"])
      ignore(header_text(header_required(pair, "target_field", node)))
      ignore(header_text(header_required(pair, "result_field", node)))
    }
    "ids" => header_nonempty_array(@wire.lookup(body, "ids").unwrap())
    "external_id" => {
      let node = @wire.lookup(body, "external_id").unwrap()
      let pair = header_object(node, ["field", "value"])
      ignore(header_text(header_required(pair, "field", node)))
      ignore(header_required(pair, "value", node))
    }
    "where" => header_nonempty_array(@wire.lookup(body, "where").unwrap())
    _ => abort("closed selector inventory")
  }
  let correlated = selected == "id" || selected == "match"
  let from = header_from(body, stage, correlated, source)
  if !correlated && from is Some(_) {
    header_fail(source, InvalidSourceResult)
  }
  from
}

///|
fn header_member(
  stage_index : Int,
  stage : Stage,
  effect_id : String,
  declaration : @wire.Cursor,
  budget : HeaderBudget,
) -> EffectHeader raise EffectHeaderStop {
  let outer = match
    @wire.closed_object(declaration, [
      "meta", "create", "update", "upsert", "delete", "command", "store",
    ]) {
    Ok(value) => value
    Err(_) => header_fail(declaration, InvalidDeclaration)
  }
  header_metadata(outer, budget)
  let mut kind : String? = None
  for candidate in ["create", "update", "upsert", "delete", "command", "store"] {
    if @wire.lookup(outer, candidate) is Some(_) {
      if kind is Some(_) {
        header_fail(declaration, InvalidKind)
      }
      kind = Some(candidate)
    }
  }
  let selected = match kind {
    Some(value) => value
    None => header_fail(declaration, InvalidKind)
  }
  let source = @wire.lookup(outer, selected).unwrap()
  let fields = match selected {
    "create" =>
      ["target", "mapping", "from", "payload", "max_items", "on_item_failure"]
    "update" =>
      [
        "target", "mapping", "from", "id", "match", "ids", "external_id", "where",
        "set", "max_items", "on_item_failure",
      ]
    "upsert" =>
      [
        "target", "mapping", "from", "key", "set", "max_items", "on_item_failure",
      ]
    "delete" =>
      [
        "target", "mapping", "from", "id", "match", "ids", "external_id", "where",
        "max_items", "on_item_failure",
      ]
    "store" => ["target", "mapping", "from", "max_items", "on_item_failure"]
    "command" =>
      ["from", "target", "contract", "input", "max_items", "on_item_failure"]
    _ => abort("closed effect kind")
  }
  let body = header_object(source, fields)
  let contract_ref = header_text(
    header_required(
      body,
      if selected == "command" {
        "contract"
      } else {
        "mapping"
      },
      source,
    ),
  )
  if selected == "command" {
    let target = header_required(body, "target", source)
    let view = header_object(target, ["field"])
    ignore(header_text(header_required(view, "field", target)))
    ignore(header_required(body, "input", source))
  } else {
    ignore(header_text(header_required(body, "target", source)))
  }
  let failure_policy = match @wire.lookup(body, "on_item_failure") {
    None => "halt"
    Some(policy) => {
      if @wire.text(policy) != Ok("continue") {
        header_fail(policy, InvalidFailurePolicy)
      }
      "continue"
    }
  }
  if @wire.lookup(body, "max_items") is Some(max_items) {
    header_positive_guard(max_items)
  }
  let from = match selected {
    "create" => {
      let value = header_from(body, stage, false, source)
      let payload = @wire.lookup(body, "payload")
      if (value is Some(_)) == (payload is Some(_)) {
        header_fail(source, InvalidSourceResult)
      }
      if payload is Some(node) {
        header_object_shape(node)
      }
      value
    }
    "update" | "delete" => header_selector(body, stage, source)
    "upsert" | "store" | "command" => header_from(body, stage, true, source)
    _ => abort("closed effect kind")
  }
  if selected == "update" || selected == "upsert" {
    header_value_map(
      header_required(body, "set", source),
      true,
      from is Some(_),
      budget,
    )
  }
  if selected == "command" {
    header_value_map(
      header_required(body, "input", source),
      false,
      true,
      budget,
    )
  }
  if selected == "upsert" {
    ignore(header_text(header_required(body, "key", source)))
  }
  {
    stage_index,
    effect_id,
    kind: selected,
    source_result: from,
    contract_ref,
    failure_policy,
    body: source,
  }
}

///|
/// Retain bounded structural Effect headers from the original Program. This
/// does not resolve Mapping/Command Contracts, Result field types, Preview
/// guards, current authority, or execution permission. Work counts one unit
/// per Effect, metadata field, or EffectValue field; all other reads are
/// constant-sized header checks over a separately admitted source tree.
pub fn collect_effect_headers(
  program : Program,
  max_members : Int,
  max_work : Int,
) -> Result[EffectHeaders, EffectHeaderIssue] {
  if max_members < 0 || max_work < 0 {
    return Err({ kind: InvalidLimits, source: program.body, })
  }
  let members : Array[EffectHeader] = []
  let budget : HeaderBudget = { remaining: max_work, }
  for stage_index in 0..<program.stages.length() {
    let stage = program.stages[stage_index]
    if stage.effects.length() > max_members - members.length() ||
      stage.effects.length() > budget.remaining {
      return Err({ kind: BudgetExceeded, source: stage.body, })
    }
    let stage_body = @wire.open_object(stage.body).unwrap()
    let effects = @wire.lookup(stage_body, "effects")
    let effect_view = effects.map(cursor => @wire.open_object(cursor).unwrap())
    for effect_id in stage.effects {
      header_spend(budget, 1, stage.body) catch {
        EffectHeaderStop(issue) => return Err(issue)
      }
      let declaration = @wire.lookup(effect_view.unwrap(), effect_id).unwrap()
      let effect = header_member(
        stage_index, stage, effect_id, declaration, budget,
      ) catch {
        EffectHeaderStop(issue) => return Err(issue)
      }
      members.push(effect)
    }
  }
  Ok({ owner: program, members, work: max_work - budget.remaining, })
}
