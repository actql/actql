///|
pub enum SelectorForm {
  ExplicitIds
  RelationIds(from~ : String, field~ : @row.FieldName)
  PredicateNodes
}

///|
pub(all) enum SelectorObligation {
  AdmitSelectorIdentities
  RevalidateSelectorReferences
  DeduplicateSelectorIdentities
  RequireSelectorMembership
  EvaluateSelectorPredicate
  ResolveSelectorResources
} derive(Eq, Debug)

///|
struct CheckedSelector {
  source : @decode.Cursor
  form : SelectorForm
  identity : @contract.Contract
  ids : Array[@value.CheckedValue]
  predicate : CheckedPredicate?
  usage : PredicateUsage
}

///|
/// The caller resolves the Relation named by from; its ordered input edge is separate.
pub fn check_selector(
  source : @decode.Cursor,
  graph : @carrier.Carrier,
  relation : @carrier.Carrier?,
  parameters : @parameter.Declarations?,
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
    let mut predicate : CheckedPredicate? = None
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
      let at = where_source.unwrap()
      let p = match
        check_predicate(Nodes, at, graph, parameters, {
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
      predicate = Some(p)
      PredicateNodes
    }
    Ok({
      source,
      form,
      identity,
      ids,
      predicate,
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
    _ => abort("unexpected graph selector exception")
  }
}

///|
pub fn selector_form(c : CheckedSelector) -> SelectorForm {
  c.form
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
pub fn selector_predicate(c : CheckedSelector) -> CheckedPredicate? {
  c.predicate
}

///|
pub fn selector_usage(c : CheckedSelector) -> PredicateUsage {
  c.usage
}

///|
pub fn selector_pending(c : CheckedSelector) -> Array[SelectorObligation] {
  let out = [
    AdmitSelectorIdentities,
    DeduplicateSelectorIdentities,
    RequireSelectorMembership,
    ResolveSelectorResources,
  ]
  if c.form is RelationIds(..) {
    out.push(RevalidateSelectorReferences)
  }
  if c.predicate is Some(_) {
    out.push(EvaluateSelectorPredicate)
  }
  out
}
