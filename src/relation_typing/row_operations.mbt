///|
pub struct OrderTerm {
  field : @schema.FieldName
  direction : @order.Direction
  nulls : @order.NullPlacement
  explicit_nulls : Bool
  source : @decode.Cursor
}

///|
pub struct KeyField {
  field : @schema.FieldName
  source : @decode.Cursor
}

///|
pub(all) enum CountValue {
  Literal(Int64)
  Parameter(String)
} derive(Eq, Debug)

///|
pub enum RowOperation {
  Watermark(
    time~ : KeyField,
    timestamp~ : Bool,
    threshold~ : WatermarkSource,
    policy~ : LatePolicy
  )
  AssertWhere
  AssertUnique(Array[KeyField])
  Sort(Array[OrderTerm])
  Take(count~ : CountValue, offset~ : CountValue)
  DistinctRows
  DistinctKeys(Array[KeyField])
  DedupeRows(by~ : Array[KeyField], order~ : Array[OrderTerm])
  TopK(count~ : CountValue, order~ : Array[OrderTerm])
  TopKBy(
    partition~ : Array[KeyField],
    count~ : CountValue,
    order~ : Array[OrderTerm]
  )
  Lag(
    partition~ : Array[KeyField],
    order~ : Array[OrderTerm],
    field~ : KeyField,
    output~ : String,
    offset~ : CountValue
  )
}

///|
pub(all) enum ValidationKind {
  SortOrderCompletion
  StableInputOrder
  FailOnTopTie
  BoundInteger(name~ : String, minimum~ : Int64)
  ValidateReshapeRows
  ExpansionEnvelope
  AtomicRowAssertion
  AssertionConsumption
  AggregateDemand
  GroupPartitioning
  PivotPartitioning
  BoundFill(String)
  AnalyticPeerOrder
  AnalyticPositionOrder
  AnalyticFrameDemand
  AnalyticEnvelope
  BoundFrameOrder
  TopKSelectionEnvelope
  TopKPartitioning
  AggregateEnvelope
  NumericAggregateObservation
  StatisticalAggregateLaw
  BoundFraction(String)
  LagCandidateKeyOrder
  WatermarkPrefixOrder
  WatermarkArithmetic
  BoundFinite(String)
  BoundDuration(String)
} derive(Eq, Debug)

///|
/// Requirements for later checking/execution, never established proofs.
pub struct PendingValidation {
  kind : ValidationKind
  source : @decode.Cursor
}

///|
pub fn pending_validations(
  value : CheckedOperation,
) -> Array[PendingValidation] {
  value.pending.copy()
}

///|
pub fn row_operation(value : CheckedOperation) -> RowOperation? {
  value.row_operation.map(op => {
    match op {
      Watermark(time~, timestamp~, threshold~, policy~) =>
        Watermark(time~, timestamp~, threshold~, policy~)
      AssertWhere => AssertWhere
      AssertUnique(keys) => AssertUnique(keys.copy())
      Sort(terms) => Sort(terms.copy())
      Take(count~, offset~) => Take(count~, offset~)
      DistinctRows => DistinctRows
      DistinctKeys(keys) => DistinctKeys(keys.copy())
      DedupeRows(by~, order~) => DedupeRows(by=by.copy(), order=order.copy())
      TopK(count~, order~) => TopK(count~, order=order.copy())
      TopKBy(partition~, count~, order~) =>
        TopKBy(partition=partition.copy(), count~, order=order.copy())
      Lag(partition~, order~, field~, output~, offset~) =>
        Lag(
          partition=partition.copy(),
          order=order.copy(),
          field~,
          output~,
          offset~,
        )
    }
  })
}

///|
// Preflight the entire owned body, including otherwise unvisited invalid data.
fn row_source(b : Budget, root : @decode.Cursor) -> Unit raise Stop {
  let work = [(root, 0)]
  while work.pop() is Some((s, depth)) {
    spend(b, s)
    if b.nodes == 0 {
      fail(s, BudgetExceeded)
    }
    b.nodes -= 1
    match @decode.view(s) {
      TextValue(text) => charge(b, s, text)
      ArrayValue(items) => {
        if depth >= b.limits.max_depth {
          fail(s, BudgetExceeded)
        }
        spend(b, s, count=items.length())
        for item in items {
          work.push((item, depth + 1))
        }
      }
      ObjectValue(obj) => {
        if depth >= b.limits.max_depth {
          fail(s, BudgetExceeded)
        }
        let names = @decode.object_field_names(s).unwrap()
        spend(b, s, count=names.length())
        for name in names {
          charge(b, s, name)
          work.push((@decode.lookup(obj, name).unwrap(), depth + 1))
        }
      }
      _ => ()
    }
  }
}

///|
fn row_order(
  b : Budget,
  source : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
) -> Array[OrderTerm] raise Stop {
  let items = decoded(@decode.elements(source), source)
  spend(b, source, count=items.length())
  let terms : Array[OrderTerm] = []
  for item in items {
    let key = match @order.read(item) {
      Ok(k) => k
      Err(e) => {
        if e.diagnostic is Some(d) {
          raise Stop({
            source: e.source,
            kind: InvalidOrder,
            path: d.path.copy(),
            span: d.span,
            range: None,
          })
        }
        fail(e.source, InvalidOrder)
      }
    }
    spend(b, item, count=key.work)
    let field = input_reference(b, key.field_source, key.field, visible)
    if !@order.author_orderable(visible.get(key.field).unwrap().0) {
      fail(key.field_source, NotAuthorOrderable(key.field))
    }
    terms.push({
      field,
      direction: key.direction,
      nulls: key.nulls,
      explicit_nulls: key.explicit_nulls,
      source: item,
    })
  }
  terms
}

///|
fn row_keys(
  b : Budget,
  source : @decode.Cursor,
  visible : Map[String, (@contract.Contract, ReferenceTarget)],
  unique~ : Bool,
) -> Array[KeyField] raise Stop {
  let items = decoded(@decode.elements(source), source)
  spend(b, source, count=items.length())
  let keys : Array[KeyField] = []
  let seen : Map[String, Bool] = Map([])
  for item in items {
    let name = decoded(@decode.text(item), item)
    let field = input_reference(b, item, name, visible)
    if unique && seen.contains(name) {
      fail(item, DuplicateOutput(name))
    }
    seen[name] = true
    let contract = visible.get(name).unwrap().0
    if !@contract.key_comparable(contract, contract) {
      fail(item, NotKeyComparable(name))
    }
    keys.push({ field, source: item, })
  }
  keys
}

///|
fn row_count(
  b : Budget,
  source : @decode.Cursor,
  minimum : Int64,
  parameters : Map[String, @contract.Contract],
  pending : Array[PendingValidation],
) -> CountValue raise Stop {
  spend(b, source)
  match @decode.view(source) {
    NumberValue(n) => {
      if n == 0.0 && 1.0 / n < 0.0 {
        fail(source, InvalidCount)
      }
      match @scalar.read_safe_integer(n) {
        Some(n) =>
          if n >= minimum {
            Literal(n)
          } else {
            fail(source, InvalidCount)
          }
        None => fail(source, InvalidCount)
      }
    }
    _ => {
      let obj = decoded(@decode.closed_object(source, ["$param"]), source)
      let s = decoded(@decode.required(obj, "$param"), source)
      let name = decoded(@decode.text(s), s)
      charge(b, s, name)
      let c = match parameters.get(name) {
        Some(c) => c
        None => fail(s, UnknownParameter(name))
      }
      if !(c.shape is @contract.Number) {
        fail(s, InvalidCount)
      }
      pending.push({ kind: BoundInteger(name~, minimum~), source, })
      Parameter(name)
    }
  }
}

///|
/// Recognized order-preserving rules, not evidence that the input is ordered.
/// Reads private checked metadata without copying authored order arrays.
pub fn preserves_input_order(value : CheckedOperation) -> Bool {
  match value.operation {
    Filter
    | Derive
    | Select
    | Rename
    | Drop
    | Take
    | AssertRows
    | Distinct
    | Analytic
    | JsonPick
    | Lag
    | WatermarkRows => true
    Sort =>
      match value.row_operation {
        Some(Sort(terms)) => terms.is_empty()
        _ => false
      }
    _ => false
  }
}

///|
pub fn sort_term_count(value : CheckedOperation) -> Int {
  match value.row_operation {
    Some(Sort(terms)) => terms.length()
    _ => 0
  }
}

///|
/// Existing input-sequence requirements; excludes operators that may complete
/// or construct a different order, such as take, lag and aggregate-local sorts.
pub fn existing_order_requirement(value : CheckedOperation) -> ValidationKind? {
  match value.row_operation {
    Some(Watermark(threshold=PrefixSkew(_, ..), ..)) =>
      Some(WatermarkPrefixOrder)
    _ =>
      match value.pivot {
        Some(p) if p.function is First => Some(StableInputOrder)
        _ => None
      }
  }
}

///|
pub fn sort_term_at(value : CheckedOperation, index : Int) -> OrderTerm? {
  match value.row_operation {
    Some(Sort(terms)) => terms.get(index)
    _ => None
  }
}

///|
/// Authored ranking terms of sort, top_k or top_k_by, without copying arrays.
pub fn ranking_term_count(value : CheckedOperation) -> Int {
  match value.row_operation {
    Some(Sort(terms))
    | Some(TopK(order=terms, ..))
    | Some(TopKBy(order=terms, ..)) => terms.length()
    _ => 0
  }
}

///|
pub fn ranking_term_at(value : CheckedOperation, index : Int) -> OrderTerm? {
  match value.row_operation {
    Some(Sort(terms))
    | Some(TopK(order=terms, ..))
    | Some(TopKBy(order=terms, ..)) => terms.get(index)
    _ => None
  }
}

///|
pub fn lag_term_count(value : CheckedOperation) -> Int {
  match value.row_operation {
    Some(Lag(order=terms, ..)) => terms.length()
    _ => 0
  }
}

///|
pub fn lag_term_at(value : CheckedOperation, index : Int) -> OrderTerm? {
  match value.row_operation {
    Some(Lag(order=terms, ..)) => terms.get(index)
    _ => None
  }
}
