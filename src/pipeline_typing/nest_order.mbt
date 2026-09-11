///|
pub(all) enum NestOrderStrategy {
  Authored
  Inherited
  CandidateKey
  ProjectedFields
} derive(Eq, Debug)

///|
pub struct NestOrderTerm {
  field : @schema.FieldName
  direction : @order.Direction
  nulls : @order.NullPlacement
  authored : Bool
}

///|
/// Conditional child-array order; neither parent order nor execution permission.
struct NestOrder {
  consumer : CheckedStep
  child : Target
  strategy : NestOrderStrategy
  terms : Array[NestOrderTerm]
  inherited : LogicalOrder?
  key : @evidence.KeyedRelation?
  work : Int
  text : Int
}

///|
pub fn nest_order_consumer(v : NestOrder) -> CheckedStep {
  v.consumer
}

///|
pub fn nest_order_child(v : NestOrder) -> Target {
  v.child
}

///|
pub fn nest_order_strategy(v : NestOrder) -> NestOrderStrategy {
  v.strategy
}

///|
pub fn nest_order_term_count(v : NestOrder) -> Int {
  v.terms.length()
}

///|
pub fn nest_order_term_at(v : NestOrder, index : Int) -> NestOrderTerm? {
  v.terms.get(index)
}

///|
pub fn nest_order_inherited(v : NestOrder) -> LogicalOrder? {
  v.inherited
}

///|
pub fn nest_order_key(v : NestOrder) -> @evidence.KeyedRelation? {
  v.key
}

///|
pub fn nest_order_usage(v : NestOrder) -> (Int, Int) {
  (v.work, v.text)
}

///|
/// Resolves child order before projection. Authored ties may use a retained
/// total sequence, but cannot fall back to sorting the projected fields.
pub fn resolve_nest_order(
  p : CheckedPipeline,
  index : Int,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[NestOrder, Issue] {
  try {
    if max_work < 0 || max_text_bytes < 0 {
      fail(p.source, InvalidLimits)
    }
    guard p.steps.get(index) is Some(consumer) else {
      fail(p.source, InvalidBody)
    }
    guard consumer.operation is Nest(right~, checked~) else {
      fail(consumer.source, InvalidBody)
    }
    let source = @nest.source(checked)
    let b : Budget = {
      limits: {
        max_steps: 0,
        max_work,
        max_text_bytes,
        max_nodes: 0,
        max_tokens: 0,
        max_depth: 0,
      },
      work: max_work,
      text: max_text_bytes,
      nodes: 0,
      tokens: 0,
    }
    spend(b, source, 1)
    let authored = @nest.order_count(checked)
    let available = logical_order(p, right)
    let terms : Array[NestOrderTerm] = []
    let mut inherited : LogicalOrder? = None
    let mut selected : @evidence.KeyedRelation? = None
    let strategy = if authored is None && available is Some(_) {
      inherited = available
      Inherited
    } else {
      if candidate_keys(p, right) is Some(keys) {
        let selection = match
          @evidence.select_key(source, keys, CanonicalOrder, {
            max_work: b.work,
            max_name_bytes: b.text,
          }) {
          Ok(v) => v
          Err(e) => fail(source, KeyEvidence(e.kind))
        }
        b.work -= selection.work
        b.text -= selection.name_bytes
        selected = selection.key
      }
      let seen : Map[String, Bool] = Map([])
      if authored is Some(n) {
        spend(b, source, n)
        for i in 0..<n {
          let t = @nest.order_at(checked, i).unwrap()
          charge(b, t.source, @schema.reference_name(t.field))
          seen[order_field_key(t.field)] = true
          terms.push({
            field: t.field,
            direction: t.direction,
            nulls: t.nulls,
            authored: true,
          })
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
            charge(b, source, @schema.reference_name(field))
            if seen.contains(order_field_key(field)) {
              covered = true
            }
          }
          if !covered {
            let field = @evidence.key_field_at(key, i).unwrap().name
            charge(b, source, @schema.reference_name(field))
            terms.push({
              field,
              direction: @order.Asc,
              nulls: @order.Last,
              authored: false,
            })
          }
        }
        if authored is Some(_) {
          Authored
        } else {
          CandidateKey
        }
      } else if authored is Some(_) {
        guard available is Some(_) else { fail(source, UnresolvedOrder) }
        inherited = available
        Authored
      } else {
        let child_schema = @nest.input_schema(checked, Right)
        spend(b, source, @nest.projection_count(checked))
        for i in 0..<@nest.projection_count(checked) {
          let field = @nest.projection_at(checked, i).unwrap()
          charge(b, field.source, @schema.reference_name(field.input))
          let contract = @schema.lookup(child_schema, field.input).unwrap()
          match contract.shape {
            Text(_)
            | Number
            | Boolean
            | Decimal(..)
            | Date
            | Timestamp
            | ResourceRef(..)
            | ArtifactRef(..) => ()
            _ => fail(field.source, UnresolvedOrder)
          }
          terms.push({
            field: field.input,
            direction: @order.Asc,
            nulls: @order.Last,
            authored: false,
          })
        }
        ProjectedFields
      }
    }
    Ok({
      consumer,
      child: right,
      strategy,
      terms,
      inherited,
      key: selected,
      work: max_work - b.work,
      text: max_text_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
