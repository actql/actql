///|
/// Deterministic xorshift32 so every target sees the same cases.
struct Rng {
  mut state : UInt
}

///|
fn Rng::next(self : Rng, bound : Int) -> Int {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  (x % bound.reinterpret_as_uint()).reinterpret_as_int()
}

///|
let property_names : Array[String] = ["a", "b", "c"]

///|
/// Never named by a generated selector: it stands for every value of an
/// open dimension that no entry mentions, including undiscovered members.
let property_fresh : String = "#fresh"

///|
fn random_selector(rng : Rng) -> Selector {
  if rng.next(3) == 0 {
    return All
  }
  let values = []
  for name in property_names {
    if rng.next(2) == 0 {
      values.push(name)
    }
  }
  if values.is_empty() {
    values.push(property_names[rng.next(property_names.length())])
  }
  AnyOf(values)
}

///|
fn random_box(rng : Rng) -> SelectorBox {
  {
    principal: random_selector(rng),
    connection: random_selector(rng),
    resource: random_selector(rng),
    operation: random_selector(rng),
  }
}

///|
fn random_configuration(rng : Rng) -> RawAccountConfiguration {
  let outcomes : Array[ConfiguredOutcome] = [Allow, Deny, Delegate]
  let entries = []
  let count = 1 + rng.next(4)
  for index in 0..<count {
    let exclusions = []
    for _ in 0..<rng.next(4) {
      // Exclusions are a set: a repeated tuple selection is not admitted.
      let box = random_box(rng)
      if !exclusions.contains(box) {
        exclusions.push(box)
      }
    }
    entries.push(RawAccountEntry::{
      entry_id: "e\{index}",
      outcome: outcomes[rng.next(3)],
      scope: random_box(rng),
      exclusions,
    })
  }
  { account_id: "acct", entries, bootstrap: None, }
}

///|
fn brute_selector(selector : Selector, value : String) -> Bool {
  match selector {
    All => true
    AnyOf(values) => values.contains(value)
  }
}

///|
fn brute_box(box : SelectorBox, tuple : AccessTuple) -> Bool {
  brute_selector(box.principal, tuple.principal) &&
  brute_selector(box.connection, tuple.connection) &&
  brute_selector(box.resource, tuple.resource) &&
  brute_selector(box.operation, tuple.operation)
}

///|
fn brute_entry(entry : RawAccountEntry, tuple : AccessTuple) -> Bool {
  brute_box(entry.scope, tuple) &&
  !entry.exclusions.iter().any(box => brute_box(box, tuple))
}

///|
fn property_universe() -> Array[AccessTuple] {
  let values = property_names.copy()
  values.push(property_fresh)
  let tuples = []
  for p in values {
    for c in values {
      for r in values {
        for o in values {
          tuples.push(AccessTuple::{
            principal: p,
            connection: c,
            resource: r,
            operation: o,
          })
        }
      }
    }
  }
  tuples
}

///|
fn concrete(value : WitnessValue) -> String {
  match value {
    Named(name) => name
    AnyOtherThan(names) => {
      assert_true(!names.contains(property_fresh)) catch {
        _ => abort("fresh named")
      }
      property_fresh
    }
  }
}

///|
fn brute_conflict(
  raw : RawAccountConfiguration,
  universe : Array[AccessTuple],
) -> Bool {
  for tuple in universe {
    let mut seen : ConfiguredOutcome? = None
    for entry in raw.entries {
      if brute_entry(entry, tuple) {
        match seen {
          None => seen = Some(entry.outcome)
          Some(outcome) => if outcome != entry.outcome { return true }
        }
      }
    }
  }
  false
}

///|
fn find_entry(raw : RawAccountConfiguration, id : String) -> RawAccountEntry {
  for entry in raw.entries {
    if entry.entry_id == id {
      return entry
    }
  }
  abort("missing entry")
}

///|
test "symbolic overlap agrees with brute force over a finite universe with fresh values" {
  let rng : Rng = { state: 0x9E3779B9, }
  let universe = property_universe()
  let mut conflicts = 0
  let mut admissions = 0
  for _ in 0..<3000 {
    let raw = random_configuration(rng)
    let expected = brute_conflict(raw, universe)
    match admit_account_configuration(raw) {
      Err(ConflictingOutcomes(found)) => {
        conflicts = conflicts + 1
        assert_true(expected)
        assert_true(found.first_outcome != found.second_outcome)
        let witness : AccessTuple = {
          principal: concrete(found.witness.principal),
          connection: concrete(found.witness.connection),
          resource: concrete(found.witness.resource),
          operation: concrete(found.witness.operation),
        }
        let first = find_entry(raw, found.first_entry_id)
        let second = find_entry(raw, found.second_entry_id)
        assert_eq(first.outcome, found.first_outcome)
        assert_eq(second.outcome, found.second_outcome)
        assert_true(brute_entry(first, witness))
        assert_true(brute_entry(second, witness))
      }
      Ok(admitted) => {
        admissions = admissions + 1
        assert_true(!expected)
        for tuple in universe {
          let mut least : RawAccountEntry? = None
          for entry in raw.entries {
            if brute_entry(entry, tuple) {
              match least {
                Some(current) if current.entry_id.compare(entry.entry_id) <= 0 =>
                  ()
                _ => least = Some(entry)
              }
            }
          }
          let outcome = evaluate_account(admitted, tuple)
          match (least, outcome) {
            (None, Deny(NoMatch)) => ()
            (Some({ outcome: Allow, entry_id, .. }), Allow(found)) =>
              assert_eq(found, entry_id)
            (Some({ outcome: Deny, entry_id, .. }), Deny(Explicit(found))) =>
              assert_eq(found, entry_id)
            (Some({ outcome: Delegate, entry_id, .. }), Delegate(found)) => {
              assert_eq(found.entry_id, entry_id)
              assert_eq(found.tuple, tuple)
            }
            _ => fail("evaluation disagrees with brute force")
          }
        }
      }
      Err(_) => fail("unexpected issue")
    }
    // Entry order has no effect on admission.
    let reversed = { ..raw, entries: raw.entries.rev(), }
    assert_eq(
      admit_account_configuration(reversed).map(_ => ()),
      admit_account_configuration(raw).map(_ => ()),
    )
  }
  // Both branches must be exercised substantially.
  assert_true(conflicts > 300)
  assert_true(admissions > 300)
}
