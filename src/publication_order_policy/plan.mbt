///|
/// Policy output only, not proof that its inputs belong to a checked pipeline.
pub(all) enum Strategy {
  Authored
  Inherited
  CandidateKey
  ProjectedFields
} derive(Eq, Debug)

///|
pub(all) struct AuthoredTerm {
  field : String
  direction : @order.Direction
  nulls : @order.NullPlacement
  source : @decode.Cursor
}

///|
pub struct Term {
  field : @schema.FieldName
  direction : @order.Direction
  nulls : @order.NullPlacement
  authored : Bool
}

///|
pub struct Decision[T] {
  strategy : Strategy
  terms : Array[Term]
  inherited : T?
  key : @evidence.KeyedRelation?
  work : Int
  text_bytes : Int
}

///|
pub(all) enum IssueKind {
  InvalidLimits
  InvalidInput
  BudgetExceeded
  UnresolvedOrder
} derive(Eq, Debug)

///|
pub struct Issue {
  kind : IssueKind
  source : @decode.Cursor
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
priv struct Budget {
  mut work : Int
  mut text : Int
}

///|
fn[T] fail(source : @decode.Cursor, kind : IssueKind) -> T raise Stop {
  raise Stop({ source, kind, })
}

///|
fn spend(b : Budget, source : @decode.Cursor, amount : Int) -> Unit raise Stop {
  if amount < 0 || amount > b.work {
    fail(source, BudgetExceeded)
  }
  b.work -= amount
}

///|
fn charge(
  b : Budget,
  source : @decode.Cursor,
  value : String,
) -> Unit raise Stop {
  match @scalar.admit_utf8_length(value, b.text) {
    Ok(n) => b.text -= n
    Err(_) => fail(source, BudgetExceeded)
  }
}

///|
/// Derive a conditional policy plan from supplied, previously admitted facts.
/// Only the owning checker may bind this plan to authoritative source evidence.
pub fn[T] decide(
  source : @decode.Cursor,
  input : @schema.Schema,
  output : @schema.Schema,
  selected_fields : Array[String],
  authored_order : Array[AuthoredTerm]?,
  keys : @evidence.KeySet?,
  prior_order : T?,
  max_work~ : Int,
  max_text_bytes~ : Int,
) -> Result[Decision[T], Issue] {
  try {
    if max_work < 0 || max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = { work: max_work, text: max_text_bytes, }
    spend(b, source, 1)
    let mut inherited = if authored_order is None { prior_order } else { None }
    let terms : Array[Term] = []
    let mut selected : @evidence.KeyedRelation? = None
    let strategy = if inherited is Some(_) {
      Inherited
    } else {
      if keys is Some(keys) {
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
      if authored_order is Some(authored) {
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
          let resolved_field = match fields.get(term.field) {
            Some(f) => f
            None => fail(term.source, InvalidInput)
          }
          charge(b, term.source, term.field)
          seen[field_key(resolved_field)] = true
          terms.push({
            field: resolved_field,
            direction: term.direction,
            nulls: term.nulls,
            authored: true,
          })
        }
        // Keep ordinary key and retained-sequence precedence. Only an authored
        // Result may additionally use an admitted Graph edge identity; this
        // does not make its nullable label a general Relation candidate key.
        if selected is None && prior_order is None && keys is Some(keys) {
          let selection = match
            @evidence.select_graph_order_identity(source, keys, {
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
        // Authored order takes priority: never replace it with projected-field
        // fallback or inherited order when its ties remain unresolved.
        if selected is None {
          inherited = prior_order
          if inherited is None {
            fail(source, UnresolvedOrder)
          }
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
            if seen.contains(field_key(field)) {
              covered = true
            }
          }
          if !covered {
            let field = @evidence.key_field_at(key, i).unwrap().name
            charge(b, source, @schema.reference_name(field))
            terms.push({ field, direction: Asc, nulls: Last, authored: false, })
          }
        }
        if authored_order is Some(_) {
          Authored
        } else {
          CandidateKey
        }
      } else if authored_order is Some(_) {
        // The authored terms are primary; the retained sequence breaks ties
        // under stable sorting, without becoming a replacement order.
        Authored
      } else {
        spend(b, source, @schema.field_count(output))
        let projected : Map[String, @schema.Field] = Map([])
        for i in 0..<@schema.field_count(output) {
          let field = @schema.field_at(output, i).unwrap()
          let name = @schema.reference_name(field.name)
          charge(b, source, name)
          projected[name] = field
        }
        spend(b, source, selected_fields.length())
        for name in selected_fields {
          let field = match projected.get(name) {
            Some(f) => f
            None => fail(source, InvalidInput)
          }
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
fn field_key(field : @schema.FieldName) -> String {
  match field {
    Unqualified(name) => "u:" + name
    Qualified(Left, name) => "l:" + name
    Qualified(Right, name) => "r:" + name
  }
}
