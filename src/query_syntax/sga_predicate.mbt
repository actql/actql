///|
// An immutable source Expression owner, not a checked predicate or capability.
// Equality is owner identity only; it never proves semantic/evaluation reuse.
pub struct SgaPredicate {
  expression : Expression
}

///|
pub impl Eq for SgaPredicate with fn equal(self : SgaPredicate, other : SgaPredicate) -> Bool {
  physical_equal(self.expression, other.expression)
}

///|
pub impl @debug.Debug for SgaPredicate with fn to_repr(self : SgaPredicate) -> @debug.Repr {
  ignore(self)
  @debug.Repr::string("<source predicate>")
}

///|
/// Observe the original opaque Expression. Its ordinary node accessors copy
/// mutable path/child arrays and retain the original document and source spans.
pub fn sga_predicate_expression(predicate : SgaPredicate) -> Expression {
  predicate.expression
}
