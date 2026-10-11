///|
pub enum SelectorForm {
  ExplicitIds
  RelationIds(from~ : String, field~ : @row.FieldName)
  NodeWhere
}

///|
pub(all) enum SelectorObligation {
  AdmitSelectorIdentities
  RevalidateSelectorReferences
  DeduplicateSelectorIdentities
  RequireSelectorMembership
  ResolveSelectorResources
} derive(Eq, Debug)

///|
struct CheckedSelector {
  source : @decode.Cursor
  form : SelectorForm
  identity : @contract.Contract
  ids : Array[@value.CheckedValue]
  usage : PredicateUsage
  predicate : CheckedPredicate?
  fields : @carrier.Knowledge?
  positions : Array[Array[Int]]
}

///|
// A complete typed identity can itself be an object. Recognize a selector by
// its declared discriminator, not merely by the JSON container kind.
fn check_reach_selector(
  source : @decode.Cursor,
  graph : @carrier.Carrier,
  relation : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedSelector, MatchIssue] {
  let object = @decode.open_object(source)
  if object is Ok(root) && @decode.lookup(root, "where") is Some(_) {
    return check_node_where_selector(
      source, graph, relation, parameters, limits,
    )
  }
  if object is Ok(root) &&
    ["ids", "from", "where"].any(key => @decode.lookup(root, key) is Some(_)) {
    return check_selector(source, graph, relation, parameters, limits)
  }
  try {
    if relation is Some(_) {
      fail(source, InvalidBody)
    }
    guard graph is @carrier.GraphValue(g) else { fail(source, IncompleteGraph) }
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
    let identity = @carrier.graph_identity(g)
    let admitted = match
      @value.admit(identity, source, {
        max_nodes: limits.max_nodes - b.nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_text_bytes - b.text,
      }) {
      Ok(value) => value
      Err(issue) => raise MatchStop(MatchIdentity(issue))
    }
    Ok({
      source,
      form: ExplicitIds,
      identity,
      ids: [admitted],
      predicate: None,
      fields: None,
      positions: [],
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: 0,
      },
    })
  } catch {
    Stop(issue) => Err(MatchStructure(issue))
    MatchStop(issue) => Err(issue)
    _ => abort("unexpected Reach selector exception")
  }
}

///|
/// The caller resolves the Relation named by from; its ordered input edge is separate.
pub fn check_selector(
  source : @decode.Cursor,
  graph : @carrier.Carrier,
  relation : @carrier.Carrier?,
  _parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedSelector, MatchIssue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_tokens < 0 {
      fail(source, InvalidLimits)
    }
    guard graph is @carrier.GraphValue(g) else {
      if @carrier.kind(graph) != @carrier.GraphKind {
        fail(source, WrongCarrier(@carrier.kind(graph)))
      }
      fail(source, IncompleteGraph)
    }
    let identity = @carrier.graph_identity(g)
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
      @decode.closed_object(source, ["ids", "from", "id", "where"]),
    )
    let ids_source = @decode.lookup(root, "ids")
    let from_source = @decode.lookup(root, "from")
    let where_source = @decode.lookup(root, "where")
    let count = (if ids_source is Some(_) { 1 } else { 0 }) +
      (if from_source is Some(_) { 1 } else { 0 }) +
      (if where_source is Some(_) { 1 } else { 0 })
    if count != 1 ||
      (from_source is Some(_)) != (@decode.lookup(root, "id") is Some(_)) ||
      (from_source is Some(_)) != (relation is Some(_)) {
      fail(source, InvalidBody)
    }
    let ids = []
    let form = if from_source is Some(at) {
      let from = decoded(@decode.text(at))
      if from.is_empty() || @canonical.normalize_nfc_lf(from) != Ok(from) {
        fail(at, InvalidName(from))
      }
      let at = decoded(@decode.required(root, "id"))
      let name = decoded(@decode.text(at))
      let input = relation.unwrap()
      guard @carrier.relation_rows(input) is Some(rows) else {
        fail(at, WrongCarrier(@carrier.kind(input)))
      }
      let count = @carrier.field_count(rows)
      spend(b, at, count)
      let mut selected : @carrier.Field? = None
      for i in 0..<count {
        let field = @carrier.field_at(rows, i).unwrap()
        if @row.reference_name(field.name) == name {
          selected = Some(field)
        }
      }
      let field = match selected {
        Some(f) => f
        None => fail(at, UnknownMatchField(name))
      }
      let contract = match field.contract {
        Some(c) => c
        None => fail(at, UntypedMatchField(name))
      }
      ignore(
        align_domains(
          b,
          at,
          singleton_schema(identity),
          singleton_schema(contract),
        ),
      )
      RelationIds(from~, field=field.name)
    } else if ids_source is Some(at) {
      let values = match @decode.view(at) {
        ArrayValue(xs) => xs
        _ => fail(at, InvalidBody)
      }
      if values.is_empty() {
        fail(at, InvalidBody)
      }
      spend(b, at, values.length())
      for value in values {
        let before = b.nodes
        let before_text = b.text
        scan(b, value)
        match
          @value.admit(identity, value, {
            max_nodes: before - b.nodes,
            max_depth: limits.max_depth,
            max_text_bytes: before_text - b.text,
          }) {
          Ok(v) => ids.push(v)
          Err(e) => raise MatchStop(MatchIdentity(e))
        }
      }
      ExplicitIds
    } else {
      fail(where_source.unwrap(), UnsupportedGraphOperation)
    }
    Ok({
      source,
      form,
      identity,
      ids,
      predicate: None,
      fields: None,
      positions: [],
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
        tokens: 0,
      },
    })
  } catch {
    Stop(e) => Err(MatchStructure(e))
    MatchStop(e) => Err(e)
    _ => abort("unexpected graph selector exception")
  }
}

///|
pub fn selector_form(c : CheckedSelector) -> SelectorForm {
  c.form
}

///|
pub fn selector_predicate(c : CheckedSelector) -> CheckedPredicate? {
  c.predicate
}

///|
pub fn selector_fields(c : CheckedSelector) -> @carrier.Knowledge? {
  c.fields
}

///|
pub fn selector_property_position(
  c : CheckedSelector,
  definition : Int,
  field : Int,
) -> Int? {
  c.positions.get(definition).bind(positions => positions.get(field))
}

///|
// Resolve the complete static definition set before evaluating any Graph data.
// The ordinary predicate checker enforces presence and compatible field types.
fn check_node_where_selector(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  relation : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
  limits : PredicateLimits,
) -> Result[CheckedSelector, MatchIssue] {
  try {
    if relation is Some(_) ||
      limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 ||
      limits.max_tokens < 0 {
      fail(source, InvalidBody)
    }
    guard input is @carrier.GraphValue(graph) else {
      fail(source, IncompleteGraph)
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
    let root = decoded(@decode.closed_object(source, ["where"]))
    let at = decoded(@decode.required(root, "where"))
    let profile = @carrier.graph_definition(graph)
    let count = @carrier.graph_node_count(profile)
    spend(b, at, count)
    let candidates = []
    for index in 0..<count {
      candidates.push(index)
    }
    let (fields, positions) = traversal_common_scope(
      profile,
      Nodes,
      candidates,
      at,
      b,
    )
    let predicate = match
      check_predicate_in_scope(
        { fields, usage: { work: 0, nodes: 0, text_bytes: 0, }, },
        at,
        parameters,
        {
          max_work: b.work,
          max_nodes: b.nodes,
          max_depth: limits.max_depth,
          max_text_bytes: b.text,
          max_tokens: limits.max_tokens,
        },
      ) {
      Ok(value) => value
      Err(issue) => raise MatchStop(MatchPredicate(issue))
    }
    Ok({
      source,
      form: NodeWhere,
      identity: @carrier.graph_identity(graph),
      ids: [],
      predicate: Some(predicate),
      fields: Some(fields),
      positions,
      usage: {
        work: limits.max_work - b.work + predicate.usage.work,
        nodes: limits.max_nodes - b.nodes + predicate.usage.nodes,
        text_bytes: limits.max_text_bytes - b.text + predicate.usage.text_bytes,
        tokens: predicate.usage.tokens,
      },
    })
  } catch {
    Stop(issue) => Err(MatchStructure(issue))
    MatchStop(issue) => Err(issue)
    _ => abort("unexpected node selector exception")
  }
}

///|
pub fn selector_identity(c : CheckedSelector) -> @contract.Contract {
  c.identity
}

///|
pub fn selector_source(c : CheckedSelector) -> @decode.Cursor {
  c.source
}

///|
pub fn selector_ids(c : CheckedSelector) -> Array[@value.CheckedValue] {
  c.ids.copy()
}

///|
pub fn selector_id_count(c : CheckedSelector) -> Int {
  c.ids.length()
}

///|
/// O(1), retaining the admitted value; invalid indices return None.
pub fn selector_id_at(c : CheckedSelector, index : Int) -> @value.CheckedValue? {
  c.ids.get(index)
}

///|
pub fn selector_usage(c : CheckedSelector) -> PredicateUsage {
  c.usage
}

///|
pub fn selector_pending(c : CheckedSelector) -> Array[SelectorObligation] {
  let out = []
  selector_pending_each(c, item => out.push(item))
  out
}

///|
// One bounded enumeration rule shared by copied and indexed reads.
fn selector_pending_each(
  c : CheckedSelector,
  emit : (SelectorObligation) -> Unit,
) -> Unit {
  emit(AdmitSelectorIdentities)
  emit(DeduplicateSelectorIdentities)
  emit(RequireSelectorMembership)
  emit(ResolveSelectorResources)
  if c.form is RelationIds(..) {
    emit(RevalidateSelectorReferences)
  }
}

///|
/// O(1), independent of input data size; no obligation array is materialized.
pub fn selector_pending_count(c : CheckedSelector) -> Int {
  let mut count = 0
  selector_pending_each(c, _ => count += 1)
  count
}

///|
/// O(1), without copying the obligation array; invalid indices return None.
pub fn selector_pending_at(
  c : CheckedSelector,
  index : Int,
) -> SelectorObligation? {
  if index < 0 {
    return None
  }
  let mut count = 0
  let mut found = None
  selector_pending_each(c, item => {
    if count == index {
      found = Some(item)
    }
    count += 1
  })
  found
}
