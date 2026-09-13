///|
pub struct OrderTerm {
  field : @row.FieldName
  direction : @order.Direction
  nulls : @order.NullPlacement
  source : @decode.Cursor
}

///|
struct DedupeSpec {
  keys : Array[@row.FieldName]
  order : Array[OrderTerm]
}

///|
pub fn dedupe_keys(spec : DedupeSpec) -> Array[@row.FieldName] {
  spec.keys.copy()
}

///|
pub fn dedupe_key_count(spec : DedupeSpec) -> Int {
  spec.keys.length()
}

///|
pub fn dedupe_key_at(spec : DedupeSpec, index : Int) -> @row.FieldName? {
  spec.keys.get(index)
}

///|
pub fn dedupe_order(spec : DedupeSpec) -> Array[OrderTerm] {
  spec.order.copy()
}

///|
fn field_contract(
  records : @carrier.Knowledge,
  name : @row.FieldName,
  source : @decode.Cursor,
) -> @contract.Contract raise Stop {
  match @carrier.lookup(records, name) {
    Present({ contract: Some(c), .. }) => c
    Present(_) => fail(source, UnknownFieldType(@row.reference_name(name)))
    _ => fail(source, UnknownField(@row.reference_name(name)))
  }
}

///|
pub fn check_dedupe(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedEvent, Issue] {
  try {
    if limits.max_work < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_text_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : Budget = {
      limits,
      work: limits.max_work,
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
    }
    scan(b, source)
    if @carrier.kind(input) != @carrier.EventsKind {
      fail(source, WrongCarrier(@carrier.kind(input)))
    }
    let records = match input {
      @carrier.EventValue(e) => e.records
      _ => @carrier.unknown_rows()
    }
    let object = decoded(@decode.closed_object(source, ["by", "order_by"]))
    let by_source = decoded(@decode.required(object, "by"))
    let by = decoded(@decode.elements(by_source))
    let keys = []
    spend(b, source, by.length())
    for c in by {
      let key = role_name(c)
      let contract = field_contract(records, key, c)
      if !@contract.key_comparable(contract, contract) {
        fail(c, NotKeyComparable(@row.reference_name(key)))
      }
      keys.push(key)
    }
    let order_source = decoded(@decode.required(object, "order_by"))
    let terms = decoded(@decode.elements(order_source))
    if terms.is_empty() {
      fail(order_source, InvalidOrder)
    }
    let order = []
    for c in terms {
      let term = match @order.read(c) {
        Ok(t) => t
        Err(e) => {
          if e.diagnostic is Some(d) {
            raise Stop({
              kind: Decode(d.kind),
              path: d.path.copy(),
              span: d.span,
            })
          }
          fail(e.source, InvalidOrder)
        }
      }
      spend(b, c, term.work)
      let field = role_spelling(term.field, term.field_source)
      let contract = field_contract(records, field, term.field_source)
      if !@order.author_orderable(contract) {
        fail(term.field_source, NotAuthorOrderable(term.field))
      }
      order.push({
        field,
        direction: term.direction,
        nulls: term.nulls,
        source: c,
      })
    }
    Ok({
      source,
      input,
      output: input,
      options: Dedupe({ keys, order, }),
      usage: {
        work: limits.max_work - b.work,
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    Stop(e) => Err(e)
  }
}
