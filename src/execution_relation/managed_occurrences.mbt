///|
/// Owned occurrence indices or an already range-checked contiguous interval.
/// Neither variant is evidence that an executor actually selected these rows.
priv enum ManagedOccurrences {
  Indices(Array[Int])
  Slice(Int, Int)
}

///|
fn ManagedOccurrences::length(self : ManagedOccurrences) -> Int {
  match self {
    Indices(rows) => rows.length()
    Slice(_, count) => count
  }
}

///|
fn ManagedOccurrences::get(self : ManagedOccurrences, position : Int) -> Int? {
  if position < 0 || position >= self.length() {
    return None
  }
  match self {
    Indices(rows) => rows.get(position)
    Slice(start, _) => Some(start + position)
  }
}
