///|
pub(all) enum Resource {
  Tokens
  SyntaxNodes
  SyntaxDepth
  LiteralBytes
  Symbols
  GeneratedSteps
  GeneratedFields
  LoweringWork
} derive(Eq, Debug)

///|
pub(all) struct FrontendLimits {
  max_tokens : Int
  max_syntax_nodes : Int
  max_syntax_depth : Int
  max_literal_bytes : Int
  max_symbol_count : Int
  max_generated_steps : Int
  max_generated_fields : Int
  max_lowering_work : Int
}

///|
priv suberror LimitAbort {
  LimitAbort(Resource, Int)
}

///|
priv struct Budget {
  caps : Array[Int]
  used : Array[Int]
}

///|
fn resource_index(resource : Resource) -> Int {
  match resource {
    Tokens => 0
    SyntaxNodes => 1
    SyntaxDepth => 2
    LiteralBytes => 3
    Symbols => 4
    GeneratedSteps => 5
    GeneratedFields => 6
    LoweringWork => 7
  }
}

///|
fn budget(limits : FrontendLimits) -> Budget? {
  let caps = [
    limits.max_tokens,
    limits.max_syntax_nodes,
    limits.max_syntax_depth,
    limits.max_literal_bytes,
    limits.max_symbol_count,
    limits.max_generated_steps,
    limits.max_generated_fields,
    limits.max_lowering_work,
  ]
  if caps.any(n => n < 0 || n == 2147483647) {
    return None
  }
  Some({ caps, used: Array::make(8, 0), })
}

///|
fn Budget::charge(
  self : Budget,
  resource : Resource,
  amount : Int,
  at : Int,
) -> Unit raise LimitAbort {
  let index = resource_index(resource)
  if resource == SyntaxDepth {
    if amount > self.caps[index] {
      raise LimitAbort(resource, at)
    }
    self.used[index] = self.used[index].max(amount)
  } else {
    if amount < 0 || amount > self.caps[index] - self.used[index] {
      raise LimitAbort(resource, at)
    }
    self.used[index] += amount
  }
}

///|
fn Budget::left(self : Budget, resource : Resource) -> Int {
  let index = resource_index(resource)
  self.caps[index] - self.used[index]
}

///|
/// Observed frontend accounting for an immutable, successfully admitted source.
/// Depth is a peak; all other values are cumulative across the whole document.
pub fn usage(parsed : Parsed, resource : Resource) -> Int {
  parsed.usage[resource_index(resource)]
}
