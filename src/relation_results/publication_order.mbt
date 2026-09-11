///|
pub(all) enum OrderStrategy {
  Authored
  Inherited
  CandidateKey
  ProjectedFields
} derive(Eq, Debug)

///|
pub struct PublicationTerm {
  field : @schema.FieldName
  direction : Direction
  nulls : NullPlacement
  authored : Bool
}

///|
struct PublicationOrder {
  results : CheckedResults
  index : Int
  strategy : OrderStrategy
  terms : Array[PublicationTerm]
  inherited : @pipeline.LogicalOrder?
  key : @evidence.KeyedRelation?
  work : Int
  text_bytes : Int
}

///|
pub fn publication_strategy(p : PublicationOrder) -> OrderStrategy {
  p.strategy
}

///|
pub fn publication_term_count(p : PublicationOrder) -> Int {
  p.terms.length()
}

///|
pub fn publication_term_at(p : PublicationOrder, i : Int) -> PublicationTerm? {
  p.terms.get(i)
}

///|
pub fn publication_inherited_order(
  p : PublicationOrder,
) -> @pipeline.LogicalOrder? {
  p.inherited
}

///|
pub fn publication_key(p : PublicationOrder) -> @evidence.KeyedRelation? {
  p.key
}

///|
pub fn publication_results(p : PublicationOrder) -> CheckedResults {
  p.results
}

///|
pub fn publication_result_index(p : PublicationOrder) -> Int {
  p.index
}

///|
pub fn publication_order_usage(p : PublicationOrder) -> (Int, Int) {
  (p.work, p.text_bytes)
}

///|
/// Resolves the static publication strategy, conditional on retained execution
/// and key validation obligations. Does not emit a Plan or execute a sort.
pub fn resolve_publication_order(
  results : CheckedResults,
  index : Int,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[PublicationOrder, Issue] {
  try {
    if max_work < 0 || max_text_bytes < 0 {
      fail(results.source, InvalidLimits)
    }
    guard results.definitions.get(index) is Some(definition) else {
      fail(results.source, InvalidBody)
    }
    let authored = definition.order.map(terms => {
      terms.map(term => @policy.AuthoredTerm::{
        field: term.field,
        direction: term.direction,
        nulls: term.nulls,
        source: term.source,
      })
    })
    let plan = match
      @policy.decide(
        definition.source,
        @pipeline.schema_at(results.pipeline, definition.target).unwrap(),
        definition.schema,
        definition.fields,
        authored,
        @pipeline.candidate_keys(results.pipeline, definition.target),
        @pipeline.logical_order(results.pipeline, definition.target),
        max_work~,
        max_text_bytes~,
      ) {
      Ok(v) => v
      Err(e) =>
        fail(
          e.source,
          match e.kind {
            @policy.InvalidLimits => InvalidLimits
            @policy.InvalidInput => InvalidBody
            @policy.BudgetExceeded => BudgetExceeded
            @policy.UnresolvedOrder => UnresolvedOrder
          },
        )
    }
    Ok({
      results,
      index,
      strategy: match plan.strategy {
        @policy.Authored => Authored
        @policy.Inherited => Inherited
        @policy.CandidateKey => CandidateKey
        @policy.ProjectedFields => ProjectedFields
      },
      terms: plan.terms.map(term => {
        field: term.field,
        direction: term.direction,
        nulls: term.nulls,
        authored: term.authored,
      }),
      inherited: plan.inherited,
      key: plan.key,
      work: plan.work,
      text_bytes: plan.text_bytes,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
