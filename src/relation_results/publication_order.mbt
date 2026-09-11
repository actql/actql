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
    let source = definition.source
    let b : Budget = {
      limits: {
        max_results: 1,
        max_work,
        max_nodes: 0,
        max_text_bytes,
        max_depth: 0,
      },
      work: max_work,
      nodes: 0,
      text: max_text_bytes,
    }
    spend(b, source, 1)
    let inherited = if definition.order is None {
      @pipeline.logical_order(results.pipeline, definition.target)
    } else {
      None
    }
    let terms : Array[PublicationTerm] = []
    let mut selected : @evidence.KeyedRelation? = None
    let strategy = if inherited is Some(_) {
      Inherited
    } else {
      if @pipeline.candidate_keys(results.pipeline, definition.target)
        is Some(keys) {
        let selection = match
          @evidence.select_key(source, keys, CanonicalOrder, {
            max_work: b.work,
            max_name_bytes: b.text,
          }) {
          Ok(v) => v
          Err(_) => fail(source, BudgetExceeded)
        }
        b.work -= selection.work
        b.text -= selection.name_bytes
        selected = selection.key
      }
      let seen : Map[String, Bool] = Map([])
      if definition.order is Some(authored) {
        let input = @carrier.complete_schema(
          @carrier.relation_rows(
            @pipeline.carrier_at(results.pipeline, definition.target).unwrap(),
          ).unwrap(),
        ).unwrap()
        let fields : Map[String, @schema.FieldName] = Map([])
        spend(b, source, @schema.field_count(input))
        for i in 0..<@schema.field_count(input) {
          let field = @schema.field_at(input, i).unwrap().name
          let name = @schema.reference_name(field)
          charge(b, source, name)
          fields[name] = field
        }
        spend(b, source, authored.length())
        for term in authored {
          charge(b, term.source, term.field)
          seen[publication_field_key(fields[term.field])] = true
          terms.push({
            field: fields[term.field],
            direction: term.direction,
            nulls: term.nulls,
            authored: true,
          })
        }
        // Authored order takes priority: never replace it with projected-field
        // fallback or inherited order when its ties remain unresolved.
        if selected is None {
          fail(source, UnresolvedOrder)
        }
      }
      if selected is Some(key) {
        spend(b, source, @evidence.key_field_count(key))
        for i in 0..<@evidence.key_field_count(key) {
          let mut covered = false
          let n = @evidence.key_alias_count(key, i)
          spend(b, source, n)
          for j in 0..<n {
            let field = @evidence.key_alias_at(key, i, j).unwrap().name
            let name = @schema.reference_name(field)
            charge(b, source, name)
            if seen.contains(publication_field_key(field)) {
              covered = true
            }
          }
          if !covered {
            let field = @evidence.key_field_at(key, i).unwrap().name
            charge(b, source, @schema.reference_name(field))
            terms.push({ field, direction: Asc, nulls: Last, authored: false, })
          }
        }
        if definition.order is Some(_) {
          Authored
        } else {
          CandidateKey
        }
      } else {
        spend(b, source, @schema.field_count(definition.schema))
        let projected : Map[String, @schema.Field] = Map([])
        for i in 0..<@schema.field_count(definition.schema) {
          let field = @schema.field_at(definition.schema, i).unwrap()
          let name = @schema.reference_name(field.name)
          charge(b, source, name)
          projected[name] = field
        }
        spend(b, source, definition.fields.length())
        for name in definition.fields {
          let field = projected[name]
          match field.contract.shape {
            Text(_)
            | Number
            | Boolean
            | Decimal(..)
            | Date
            | Timestamp
            | ResourceRef(..)
            | ArtifactRef(..) => ()
            _ => fail(source, UnresolvedOrder)
          }
          charge(b, source, @schema.reference_name(field.name))
          terms.push({
            field: field.name,
            direction: Asc,
            nulls: Last,
            authored: false,
          })
        }
        ProjectedFields
      }
    }
    Ok({
      results,
      index,
      strategy,
      terms,
      inherited,
      key: selected,
      work: max_work - b.work,
      text_bytes: max_text_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
fn publication_field_key(field : @schema.FieldName) -> String {
  match field {
    Unqualified(name) => "u:" + name
    Qualified(Left, name) => "l:" + name
    Qualified(Right, name) => "r:" + name
  }
}
