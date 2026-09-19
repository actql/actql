///|
pub enum MatchIssue {
  MatchStructure(Issue)
  MatchPredicate(PredicateIssue)
  MatchIdentity(@value.Issue)
}

///|
pub(all) enum MatchObligation {
  AdmitMatchGraphData
  ValidateSelectedIdentityMembership
  FilterSelectedEdgeTypes
  EvaluateMatchPredicate
  CanonicalMatchOrder
  ResolveMatchResources
  ResolveMatchProfile
} derive(Eq, Debug)

///|
struct CheckedMatch {
  input : @carrier.Carrier
  entity : EntityKind
  source : @decode.Cursor
  output : @carrier.Carrier
  predicate : CheckedPredicate?
  fields : Array[@row.FieldName]
  ids : Array[@value.CheckedValue]
  types : Array[String]?
  usage : PredicateUsage
}

///|
priv suberror MatchStop {
  MatchStop(MatchIssue)
}

///|
pub fn check_match(
  entity : EntityKind,
  source : @decode.Cursor,
  input : @carrier.Carrier,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedMatch, MatchIssue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_tokens < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits: {
        max_work: limits.max_work,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_text_bytes,
      },
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    let root = decoded(
      @decode.closed_object(
        source,
        if entity == Nodes {
          ["ids", "where", "fields"]
        } else {
          ["types", "where", "fields"]
        },
      ),
    )
    let ids_source = @decode.lookup(root, "ids")
    let where_source = @decode.lookup(root, "where")
    if entity == Nodes && (ids_source is Some(_)) == (where_source is Some(_)) {
      fail(source, InvalidBody)
    }
    let scoped = match
      check_scope(entity, source, input, {
        ..b.limits,
        max_work: b.work,
        max_nodes: b.nodes,
        max_text_bytes: b.text,
      }) {
      Ok(s) => s
      Err(e) => raise Stop(e)
    }
    b.work -= scoped.usage.work
    b.text -= scoped.usage.text_bytes
    let at = decoded(@decode.required(root, "fields"))
    let selected = match @decode.view(at) {
      ArrayValue(xs) => xs
      _ => fail(at, InvalidBody)
    }
    if selected.is_empty() {
      fail(at, InvalidBody)
    }
    let visible : Map[String, @carrier.Field] = Map([])
    spend(b, source, @carrier.field_count(scoped.fields))
    for i in 0..<@carrier.field_count(scoped.fields) {
      let f = @carrier.field_at(scoped.fields, i).unwrap()
      visible[@row.reference_name(f.name)] = f
    }
    let output : Array[(@row.FieldName, @contract.Contract?)] = []
    let seen : Map[String, Bool] = Map([])
    spend(b, at, selected.length())
    for at in selected {
      let name = decoded(@decode.text(at))
      if seen.contains(name) {
        fail(at, DuplicateMatchField(name))
      }
      seen[name] = true
      let field = match visible.get(name) {
        Some(f) => f
        None => fail(at, UnknownMatchField(name))
      }
      if field.contract is None {
        fail(at, UntypedMatchField(name))
      }
      output.push((field.name, field.contract))
      charge(b, at, name)
    }
    let rows = match
      @carrier.rows(
        output,
        field_set=Closed,
        max_fields=output.length(),
        max_name_bytes=b.limits.max_text_bytes,
      ) {
      Ok(r) => r
      Err(_) => fail(at, InvalidBody)
    }
    let types = match @decode.lookup(root, "types") {
      None => None
      Some(at) => {
        let xs = match @decode.view(at) {
          ArrayValue(xs) => xs
          _ => fail(at, InvalidBody)
        }
        spend(b, at, xs.length())
        let out = []
        for x in xs {
          let text = decoded(@decode.text(x))
          if text.is_empty() || @canonical.normalize_nfc_lf(text) != Ok(text) {
            fail(x, InvalidName(text))
          }
          out.push(text)
        }
        Some(out)
      }
    }
    let ids = []
    if ids_source is Some(at) {
      let values = match @decode.view(at) {
        ArrayValue(xs) => xs
        _ => fail(at, InvalidBody)
      }
      if values.is_empty() {
        fail(at, InvalidBody)
      }
      guard input is @carrier.GraphValue(g) else { fail(at, IncompleteGraph) }
      spend(b, at, values.length())
      for value in values {
        // Debit the complete value walk before the independent typed admission.
        let before = b.nodes
        scan(b, value)
        let checked = match
          @value.admit(@carrier.graph_identity(g), value, {
            max_nodes: before - b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: limits.max_text_bytes,
          }) {
          Ok(v) => v
          Err(e) => raise MatchStop(MatchIdentity(e))
        }
        ids.push(checked)
      }
    }
    let predicate = match where_source {
      None => None
      Some(at) => {
        let p = match
          check_predicate(entity, at, input, parameters, {
            max_work: b.work,
            max_nodes: b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: b.text,
            max_tokens: limits.max_tokens,
          }) {
          Ok(p) => p
          Err(e) => raise MatchStop(MatchPredicate(e))
        }
        b.work -= p.usage.work
        b.nodes -= p.usage.nodes
        b.text -= p.usage.text_bytes
        Some(p)
      }
    }
    Ok({
      entity,
      input,
      source,
      output: @carrier.relation(rows),
      predicate,
      fields: output.map(value => value.0),
      ids,
      types,
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: predicate.map(p => p.usage.tokens).unwrap_or(0),
      },
    })
  } catch {
    Stop(e) => Err(MatchStructure(e))
    MatchStop(e) => Err(e)
    _ => abort("unexpected graph match checker exception")
  }
}

///|
pub fn match_output(c : CheckedMatch) -> @carrier.Carrier {
  c.output
}

///|
pub fn match_entity(c : CheckedMatch) -> EntityKind {
  c.entity
}

///|
pub fn match_usage(c : CheckedMatch) -> PredicateUsage {
  c.usage
}

///|
pub fn match_source(c : CheckedMatch) -> @decode.Cursor {
  c.source
}

///|
pub fn match_predicate(c : CheckedMatch) -> CheckedPredicate? {
  c.predicate
}

///|
pub fn match_field_count(c : CheckedMatch) -> Int {
  c.fields.length()
}

///|
pub fn match_field_at(c : CheckedMatch, index : Int) -> @row.FieldName? {
  c.fields.get(index)
}

///|
pub fn match_ids(c : CheckedMatch) -> Array[@value.CheckedValue] {
  c.ids.copy()
}

///|
pub fn match_id_count(c : CheckedMatch) -> Int {
  c.ids.length()
}

///|
pub fn match_id_at(c : CheckedMatch, index : Int) -> @value.CheckedValue? {
  c.ids.get(index)
}

///|
pub fn match_type_count(c : CheckedMatch) -> Int? {
  c.types.map(xs => xs.length())
}

///|
pub fn match_type_at(c : CheckedMatch, index : Int) -> String? {
  match c.types {
    Some(xs) => xs.get(index)
    None => None
  }
}

///|
pub fn match_types(c : CheckedMatch) -> Array[String]? {
  c.types.map(xs => xs.copy())
}

///|
pub fn match_pending(c : CheckedMatch) -> Array[MatchObligation] {
  let out = []
  match_pending_each(c, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn match_pending_each(
  c : CheckedMatch,
  emit : (MatchObligation) -> Unit,
) -> Unit {
  emit(AdmitMatchGraphData)
  emit(CanonicalMatchOrder)
  emit(ResolveMatchResources)
  emit(ResolveMatchProfile)
  if !c.ids.is_empty() {
    emit(ValidateSelectedIdentityMembership)
  }
  if c.types is Some(_) {
    emit(FilterSelectedEdgeTypes)
  }
  if c.predicate is Some(_) {
    emit(EvaluateMatchPredicate)
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn match_pending_count(c : CheckedMatch) -> Int {
  let mut count = 0
  match_pending_each(c, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn match_pending_at(c : CheckedMatch, index : Int) -> MatchObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  match_pending_each(c, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}

///|
pub fn match_input(c : CheckedMatch) -> @carrier.Carrier {
  c.input
}
