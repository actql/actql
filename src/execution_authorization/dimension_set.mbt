///|
/// A subset of one open dimension: a finite set or the complement of a finite
/// set. Arrays are strictly ascending under `code_unit_compare`. The universe is
/// infinite, so `Cofinite(_)` is never empty.
priv enum DimSet {
  Finite(Array[String])
  Cofinite(Array[String])
}

///|
/// Lexicographic order on UTF-16 code units (a proper prefix sorts first).
/// Used for every sorted set and for entry order, independently of the
/// standard library's `String::compare`.
fn code_unit_compare(left : String, right : String) -> Int {
  let shared = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<shared {
    let a = left[index].to_int()
    let b = right[index].to_int()
    if a != b {
      return if a < b { -1 } else { 1 }
    }
  }
  left.length() - right.length()
}

///|
fn sort_names(values : Array[String]) -> Array[String] {
  let sorted = values.copy()
  sorted.sort_by(code_unit_compare)
  sorted
}

///|
fn sorted_contains(values : Array[String], value : String) -> Bool {
  let mut low = 0
  let mut high = values.length()
  while low < high {
    let middle = low + (high - low) / 2
    let order = code_unit_compare(values[middle], value)
    if order == 0 {
      return true
    } else if order < 0 {
      low = middle + 1
    } else {
      high = middle
    }
  }
  false
}

///|
fn sorted_intersection(
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let result = []
  let mut i = 0
  let mut j = 0
  while i < left.length() && j < right.length() {
    let order = code_unit_compare(left[i], right[j])
    if order == 0 {
      result.push(left[i])
      i = i + 1
      j = j + 1
    } else if order < 0 {
      i = i + 1
    } else {
      j = j + 1
    }
  }
  result
}

///|
fn sorted_union(left : Array[String], right : Array[String]) -> Array[String] {
  let result = []
  let mut i = 0
  let mut j = 0
  while i < left.length() || j < right.length() {
    if j >= right.length() {
      result.push(left[i])
      i = i + 1
    } else if i >= left.length() {
      result.push(right[j])
      j = j + 1
    } else {
      let order = code_unit_compare(left[i], right[j])
      if order == 0 {
        result.push(left[i])
        i = i + 1
        j = j + 1
      } else if order < 0 {
        result.push(left[i])
        i = i + 1
      } else {
        result.push(right[j])
        j = j + 1
      }
    }
  }
  result
}

///|
fn sorted_difference(
  left : Array[String],
  right : Array[String],
) -> Array[String] {
  let result = []
  let mut i = 0
  let mut j = 0
  while i < left.length() {
    if j >= right.length() {
      result.push(left[i])
      i = i + 1
    } else {
      let order = code_unit_compare(left[i], right[j])
      if order == 0 {
        i = i + 1
        j = j + 1
      } else if order < 0 {
        result.push(left[i])
        i = i + 1
      } else {
        j = j + 1
      }
    }
  }
  result
}

///|
fn DimSet::contains(self : DimSet, value : String) -> Bool {
  match self {
    Finite(values) => sorted_contains(values, value)
    Cofinite(values) => !sorted_contains(values, value)
  }
}

///|
fn DimSet::size(self : DimSet) -> Int {
  match self {
    Finite(values) | Cofinite(values) => values.length()
  }
}

///|
/// Work units charged for combining two regions: one plus every named value
/// the set operations may visit.
fn Region::work(self : Region, other : Region) -> Int {
  let mut total = 1
  for k in 0..<4 {
    total = total + self.dims[k].size() + other.dims[k].size()
  }
  total
}

///|
fn DimSet::is_empty(self : DimSet) -> Bool {
  match self {
    Finite(values) => values.is_empty()
    Cofinite(_) => false
  }
}

///|
fn DimSet::intersect(self : DimSet, other : DimSet) -> DimSet {
  match (self, other) {
    (Finite(a), Finite(b)) => Finite(sorted_intersection(a, b))
    (Finite(a), Cofinite(b)) => Finite(sorted_difference(a, b))
    (Cofinite(a), Finite(b)) => Finite(sorted_difference(b, a))
    (Cofinite(a), Cofinite(b)) => Cofinite(sorted_union(a, b))
  }
}

///|
fn DimSet::minus(self : DimSet, other : DimSet) -> DimSet {
  match (self, other) {
    (Finite(a), Finite(b)) => Finite(sorted_difference(a, b))
    (Finite(a), Cofinite(b)) => Finite(sorted_intersection(a, b))
    (Cofinite(a), Finite(b)) => Cofinite(sorted_union(a, b))
    (Cofinite(a), Cofinite(b)) => Finite(sorted_difference(b, a))
  }
}

///|
fn DimSet::witness(self : DimSet) -> WitnessValue {
  match self {
    Finite(values) => Named(values[0])
    Cofinite(values) => AnyOtherThan(values.copy())
  }
}

///|
/// A Cartesian region: exactly four dimension sets in tuple order.
priv struct Region {
  dims : FixedArray[DimSet]
}

///|
fn Region::contains(self : Region, tuple : AccessTuple) -> Bool {
  self.dims[0].contains(tuple.principal) &&
  self.dims[1].contains(tuple.connection) &&
  self.dims[2].contains(tuple.resource) &&
  self.dims[3].contains(tuple.operation)
}

///|
fn Region::witness(self : Region) -> WitnessTuple {
  {
    principal: self.dims[0].witness(),
    connection: self.dims[1].witness(),
    resource: self.dims[2].witness(),
    operation: self.dims[3].witness(),
  }
}

///|
fn Region::intersect(self : Region, other : Region) -> Region? {
  let dims = FixedArray::make(4, Finite([]))
  for k in 0..<4 {
    let dim = self.dims[k].intersect(other.dims[k])
    if dim.is_empty() {
      return None
    }
    dims[k] = dim
  }
  Some({ dims, })
}

///|
priv suberror OverlapBudgetExhausted {
  OverlapBudgetExhausted
}

///|
/// Returns a region of `region` not covered by `exclusions[index:]`, or
/// `None` when the exclusions cover it. Exact over the open universe: each
/// step splits `region \ exclusion` into at most four disjoint regions
/// (`region ∩ E` on earlier dimensions, `region_k \ E_k` on dimension `k`,
/// unconstrained later dimensions), so no value class is lost or invented.
fn uncovered_region(
  region : Region,
  exclusions : Array[Region],
  index : Int,
  budget : Ref[Int],
) -> Region? raise OverlapBudgetExhausted {
  if index == exclusions.length() {
    return Some(region)
  }
  let exclusion = exclusions[index]
  budget.val = budget.val - region.work(exclusion)
  if budget.val < 0 {
    raise OverlapBudgetExhausted
  }
  let overlap = match region.intersect(exclusion) {
    None => return uncovered_region(region, exclusions, index + 1, budget)
    Some(value) => value
  }
  for k in 0..<4 {
    let rest = region.dims[k].minus(exclusion.dims[k])
    if !rest.is_empty() {
      let dims = FixedArray::make(4, Finite([]))
      for j in 0..<4 {
        dims[j] = if j < k {
          overlap.dims[j]
        } else if j == k {
          rest
        } else {
          region.dims[j]
        }
      }
      match uncovered_region({ dims, }, exclusions, index + 1, budget) {
        Some(found) => return Some(found)
        None => ()
      }
    }
  }
  None
}
