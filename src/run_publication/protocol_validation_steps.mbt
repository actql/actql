///|
priv enum ProtocolValidationFrame {
  Visit(@json.CanonicalValue, Int)
  ArrayNext(@json.FrozenArray[@json.CanonicalValue], Int, Int)
  ArrayResult(@json.FrozenArray[@json.CanonicalValue], Int, Int)
  ContainsNext(@json.FrozenArray[@json.CanonicalValue], Int, Int)
  ContainsResult(@json.FrozenArray[@json.CanonicalValue], Int, Int)
  TupleNext(@json.FrozenArray[@json.CanonicalValue], Array[Int], Int)
  TupleResult(@json.FrozenArray[@json.CanonicalValue], Array[Int], Int)
  Required(@json.FrozenArray[(String, @json.CanonicalValue)], Int, Int, Int)
  ObjectNext(@json.FrozenArray[(String, @json.CanonicalValue)], Int, Int)
  ObjectResult(@json.FrozenArray[(String, @json.CanonicalValue)], Int, Int)
  Alternatives(@json.CanonicalValue, Array[Int], Int, Int, Bool)
  AlternativeResult(@json.CanonicalValue, Array[Int], Int, Int, Bool)
  All(@json.CanonicalValue, Array[Int], Int)
  AllResult(@json.CanonicalValue, Array[Int], Int)
  NotResult
  ConditionalResult(@json.CanonicalValue, Int, Int)
}

///|
/// The existing protocol checker, with collection iteration retained as
/// continuations. Rule visits consume the same shared semantic budget as the
/// blocking entry point; collection/control transitions do not reset it.
/// Unique-array serialization and scalar metadata predicates remain blocking.
/// This cursor alone is not a bounded public capture-issuance guarantee.
priv struct ProtocolValidationCursor {
  nodes : Array[ProtocolSchemaRule]
  budget : ProtocolValidationBudget
  pending : Array[ProtocolValidationFrame]
  // Only the private historical RunState reader selects this exact root.
  // It does not alter current schema validation or any nested object's rules.
  mut historical_run_state_root : @json.FrozenArray[
    (String, @json.CanonicalValue),
  ]?
  mut result : Bool
  mut closed : Bool
}

///|
fn start_protocol_validation(
  value : @json.CanonicalValue,
  index : Int,
  nodes : Array[ProtocolSchemaRule],
  budget : ProtocolValidationBudget,
  historical_run_state? : Bool = false,
) -> ProtocolValidationCursor {
  {
    nodes,
    budget,
    pending: [Visit(value, index)],
    historical_run_state_root: if historical_run_state {
      match value {
        @json.Object(fields) => Some(fields)
        _ => None
      }
    } else {
      None
    },
    result: false,
    closed: false,
  }
}

///|
fn ProtocolValidationCursor::step(self : ProtocolValidationCursor) -> Unit {
  guard self.pending.pop() is Some(frame) else { return }
  let pending = self.pending
  match frame {
    Visit(value, index) => {
      if index < 0 || index >= self.nodes.length() || self.budget.remaining < 1 {
        self.result = false
        return
      }
      self.budget.remaining -= 1
      match self.nodes[index] {
        AnyRule => self.result = true
        NullRule => self.result = value is @json.Null
        BoolRule(exact) =>
          self.result = match value {
            @json.Bool(actual) =>
              exact.map(expected => expected == actual).unwrap_or(true)
            _ => false
          }
        StringRule(exact, choices, pattern, min_length) =>
          self.result = match value {
            @json.String(text) =>
              text.length() >= min_length &&
              exact.map(expected => expected == text).unwrap_or(true) &&
              (choices.is_empty() || choices.contains(text)) &&
              protocol_string_pattern(text, pattern)
            _ => false
          }
        StringCeilingRule(maximum) =>
          self.result = match value {
            @json.String(text) => protocol_scalar_length(text) <= maximum
            _ => false
          }
        ObjectCeilingRule(maximum) =>
          self.result = match value {
            @json.Object(fields) => @json.array_count(fields) <= maximum
            _ => true
          }
        NumberRule => self.result = value is @json.Number(_)
        IntegerRule(minimum, maximum) =>
          self.result = match value {
            @json.Number(number) =>
              match @scalar.read_safe_integer(number) {
                Some(actual) =>
                  minimum.map(bound => actual >= bound).unwrap_or(true) &&
                  maximum.map(bound => actual <= bound).unwrap_or(true)
                None => false
              }
            _ => false
          }
        ArrayRule(items, min_items, unique, max_items) =>
          match value {
            @json.Array(values) => {
              let count = @json.array_count(values)
              if count < min_items ||
                (max_items >= 0 && count > max_items) ||
                (
                  unique &&
                  !(if items >= 0 &&
                    items < self.nodes.length() &&
                    self.nodes[items] is StringRule(_, _, _, _) {
                    protocol_unique_string_array(
                      @json.array_values(values),
                      self.budget,
                    )
                  } else {
                    protocol_unique_array(
                      @json.array_values(values),
                      self.budget,
                    )
                  })
                ) {
                self.result = false
              } else {
                pending.push(ArrayNext(values, items, 0))
              }
            }
            _ => self.result = false
          }
        ContainsRule(item) =>
          match value {
            @json.Array(values) => pending.push(ContainsNext(values, item, 0))
            // JSON Schema's contains keyword constrains arrays only. Its
            // sibling type/items rules still apply independently.
            _ => self.result = true
          }
        TupleRule(items) =>
          match value {
            @json.Array(values) =>
              if @json.array_count(values) != items.length() {
                self.result = false
              } else {
                pending.push(TupleNext(values, items, 0))
              }
            _ => self.result = false
          }
        ObjectRule(_, _, _, min_properties, _, _) =>
          match value {
            @json.Object(fields) =>
              if @json.array_count(fields) < min_properties {
                self.result = false
              } else {
                pending.push(Required(fields, index, 0, 0))
              }
            _ => self.result = false
          }
        OneOfRule(alternatives) =>
          pending.push(Alternatives(value, alternatives, 0, 0, true))
        AnyOfRule(alternatives) =>
          pending.push(Alternatives(value, alternatives, 0, 0, false))
        AllOfRule(conditions) => pending.push(All(value, conditions, 0))
        NotRule(excluded) =>
          if self.budget.remaining <= 1 {
            self.result = false
          } else {
            pending.push(NotResult)
            pending.push(Visit(value, excluded))
          }
        ConditionalRule(condition, when_true, when_false) => {
          pending.push(ConditionalResult(value, when_true, when_false))
          pending.push(Visit(value, condition))
        }
      }
    }
    ArrayNext(values, items, index) =>
      if index == @json.array_count(values) {
        self.result = true
      } else {
        pending.push(ArrayResult(values, items, index))
        pending.push(Visit(@json.array_at(values, index).unwrap(), items))
      }
    ArrayResult(values, items, index) =>
      if self.result {
        pending.push(ArrayNext(values, items, index + 1))
      }
    ContainsNext(values, item, index) =>
      if index == @json.array_count(values) || self.budget.remaining < 1 {
        self.result = false
      } else {
        pending.push(ContainsResult(values, item, index))
        pending.push(Visit(@json.array_at(values, index).unwrap(), item))
      }
    ContainsResult(values, item, index) =>
      if !self.result {
        pending.push(ContainsNext(values, item, index + 1))
      }
    TupleNext(values, items, index) =>
      if index == items.length() {
        self.result = true
      } else {
        pending.push(TupleResult(values, items, index))
        pending.push(
          Visit(@json.array_at(values, index).unwrap(), items[index]),
        )
      }
    TupleResult(values, items, index) =>
      if self.result {
        pending.push(TupleNext(values, items, index + 1))
      }
    Required(fields, schema, required_index, search) => {
      guard self.nodes[schema] is ObjectRule(_, required, _, _, _, _) else {
        self.result = false
        return
      }
      if required_index == required.length() {
        pending.push(ObjectNext(fields, schema, 0))
      } else if required[required_index] == "revision" &&
        self.historical_run_state_root is Some(root) &&
        physical_equal(root, fields) {
        pending.push(Required(fields, schema, required_index + 1, 0))
      } else if search == @json.array_count(fields) {
        self.result = false
      } else {
        let (name, _) = @json.array_at(fields, search).unwrap()
        if name == required[required_index] {
          pending.push(Required(fields, schema, required_index + 1, 0))
        } else {
          pending.push(Required(fields, schema, required_index, search + 1))
        }
      }
    }
    ObjectNext(fields, schema, index) => {
      guard self.nodes[schema]
        is ObjectRule(properties, _, additional, _, forbidden_prefix, pattern) else {
        self.result = false
        return
      }
      if index == @json.array_count(fields) {
        self.result = true
      } else {
        let (name, child) = @json.array_at(fields, index).unwrap()
        if !protocol_string_pattern(name, pattern) ||
          forbidden_prefix
          .map(prefix => name.has_prefix(prefix))
          .unwrap_or(false) {
          self.result = false
          return
        }
        match protocol_property_schema(properties, name) {
          Some(child_schema) => {
            pending.push(ObjectResult(fields, schema, index))
            pending.push(Visit(child, child_schema))
          }
          None if additional >= 0 => {
            pending.push(ObjectResult(fields, schema, index))
            pending.push(Visit(child, additional))
          }
          None if additional == -1 => self.result = false
          None => pending.push(ObjectNext(fields, schema, index + 1))
        }
      }
    }
    ObjectResult(fields, schema, index) =>
      if self.result {
        pending.push(ObjectNext(fields, schema, index + 1))
      }
    Alternatives(value, choices, index, matches, exact) =>
      if index == choices.length() {
        self.result = if exact {
          self.budget.remaining > 0 && matches == 1
        } else {
          matches > 0
        }
      } else {
        pending.push(AlternativeResult(value, choices, index, matches, exact))
        pending.push(Visit(value, choices[index]))
      }
    AlternativeResult(value, choices, index, matches, exact) => {
      let count = matches + (if self.result { 1 } else { 0 })
      pending.push(Alternatives(value, choices, index + 1, count, exact))
    }
    All(value, conditions, index) =>
      if index == conditions.length() {
        self.result = true
      } else {
        pending.push(AllResult(value, conditions, index))
        pending.push(Visit(value, conditions[index]))
      }
    AllResult(value, conditions, index) =>
      if self.result {
        pending.push(All(value, conditions, index + 1))
      }
    NotResult => self.result = self.budget.remaining > 0 && !self.result
    ConditionalResult(value, when_true, when_false) =>
      pending.push(
        Visit(value, if self.result { when_true } else { when_false }),
      )
  }
}

///|
fn ProtocolValidationCursor::advance(
  self : ProtocolValidationCursor,
  quantum : Int,
) -> (Bool, Int) {
  if self.closed || quantum < 1 {
    return (false, 0)
  }
  let mut used = 0
  while used < quantum && !self.pending.is_empty() {
    self.step()
    used += 1
  }
  (self.pending.is_empty(), used)
}

///|
fn ProtocolValidationCursor::cancel(self : ProtocolValidationCursor) -> Unit {
  self.closed = true
  self.pending.clear()
  self.historical_run_state_root = None
  self.result = false
}
