///|
pub(all) struct KeySetLimits {
  max_keys : Int
  max_work : Int
  max_name_bytes : Int
}

///|
struct KeySet {
  records : @carrier.Knowledge
  witnesses : Array[KeyedRelation]
  work : Int
  name_bytes : Int
}

///|
/// Wraps an already admitted witness without rescanning its immutable contents.
pub fn singleton_key(value : KeyedRelation) -> KeySet {
  { records: value.records, witnesses: [value], work: 0, name_bytes: 0, }
}

///|
fn same_records(a : @carrier.Knowledge, b : @carrier.Knowledge) -> Bool {
  if physical_equal(a, b) {
    return true
  }
  match (@carrier.complete_schema(a), @carrier.complete_schema(b)) {
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
/// Collects independent conditional witnesses bound to the same row contract.
/// Empty collections are allowed; no key or ordering is inferred from emptiness.
pub fn collect_keys(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  witnesses : Array[KeyedRelation],
  limits : KeySetLimits,
) -> Result[KeySet, Issue] {
  try {
    if limits.max_keys < 0 || limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let records = match @carrier.relation_rows(input) {
      Some(r) => r
      None => fail(source, WrongCarrier(@carrier.kind(input)))
    }
    if witnesses.length() > limits.max_keys {
      fail(source, LimitExceeded)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    spend(b, source, witnesses.length())
    for key in witnesses {
      if !same_records(records, key.records) {
        fail(source, InputContractMismatch)
      }
      spend(b, source, key.aliases.length())
      for aliases in key.aliases {
        spend(b, source, aliases.length())
        for field in aliases {
          charge(b, source, field.name)
        }
      }
    }
    Ok({
      records,
      witnesses: witnesses.copy(),
      work: limits.max_work - b.work,
      name_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn key_set_records(value : KeySet) -> @carrier.Knowledge {
  value.records
}

///|
/// Witness count is not the number of distinct canonical field tuples.
pub fn key_witness_count(value : KeySet) -> Int {
  value.witnesses.length()
}

///|
pub fn key_witness_at(value : KeySet, index : Int) -> KeyedRelation? {
  value.witnesses.get(index)
}

///|
pub fn key_set_usage(value : KeySet) -> (Int, Int) {
  (value.work, value.name_bytes)
}

///|
pub(all) enum KeyUse {
  CanonicalOrder
  ScalarIdentity
} derive(Eq, Debug)

///|
pub struct KeySelection {
  key : KeyedRelation?
  work : Int
  name_bytes : Int
}

///|
fn eligible(field : KeyField, usage : KeyUse) -> Bool {
  guard field.contract is Some(c) && !c.nullable else { return false }
  match c.shape {
    Text(_) | Number | Boolean | Decimal(..) | Date | Timestamp => true
    ResourceRef(..) | ArtifactRef(..) => usage == CanonicalOrder
    _ => false
  }
}

///|
fn tuple_compare(a : Array[KeyField], b : Array[KeyField]) -> Int {
  if a.length() != b.length() {
    return if a.length() < b.length() { -1 } else { 1 }
  }
  for i in 0..<a.length() {
    let n = @canonical.compare_utf16(
      @row.reference_name(a[i].name),
      @row.reference_name(b[i].name),
    )
    if n != 0 {
      return n
    }
  }
  0
}

///|
/// Applies canonical completion selection without expanding alias combinations.
/// Identical tuples are equivalent for selection, but all input witnesses remain
/// available on KeySet; this API does not implement a sole-candidate rule.
pub fn select_key(
  source : @decode.Cursor,
  value : KeySet,
  usage : KeyUse,
  limits : TransferLimits,
) -> Result[KeySelection, Issue] {
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let mut selected : KeyedRelation? = None
    spend(b, source, value.witnesses.length())
    for key in value.witnesses {
      let candidates : Array[(KeyField, Array[KeyField])] = []
      let mut valid = true
      spend(b, source, key.aliases.length())
      for aliases in key.aliases {
        let mut best : KeyField? = None
        let surviving : Array[KeyField] = []
        spend(b, source, aliases.length())
        for field in aliases {
          charge(b, source, field.name)
          if eligible(field, usage) {
            surviving.push(field)
            if best is None ||
              @canonical.compare_utf16(
                @row.reference_name(field.name),
                @row.reference_name(best.unwrap().name),
              ) <
              0 {
              best = Some(field)
            }
          }
        }
        match best {
          Some(field) => candidates.push((field, surviving))
          None => valid = false
        }
      }
      if !valid {
        continue
      }
      candidates.sort_by((a, b) => {
        @canonical.compare_utf16(
          @row.reference_name(a.0.name),
          @row.reference_name(b.0.name),
        )
      })
      let fields = candidates.map(p => p.0)
      spend(b, source, fields.length())
      if selected is None || tuple_compare(fields, selected.unwrap().fields) < 0 {
        selected = Some({ ..key, fields, aliases: candidates.map(p => p.1), })
      }
    }
    Ok({
      key: selected,
      work: limits.max_work - b.work,
      name_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
