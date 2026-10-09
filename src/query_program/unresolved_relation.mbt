///|
/// An owned semantic reference retained by the existing relation resolver.
/// Its private path cannot be edited through the returned diagnostic.
pub struct RelationResolutionReference {
  priv path : Array[@query.NamePart]
}

///|
fn unresolved_relation_issue(path : Array[@query.NamePart]) -> Issue {
  UnresolvedRelation({ path: path.copy(), })
}

///|
/// Retain the exact name-resolution witness without exposing mutable ownership
/// of its path. A bare failure from another lowering domain has no witness.
/// Authored coordinates and disclosable Source absence require separate facts.
pub fn unresolved_relation_reference(issue : Issue) -> Array[@query.NamePart]? {
  match issue {
    UnresolvedRelation(reference) => Some(reference.path.copy())
    _ => None
  }
}

///|
/// Reconcile the retained resolver witness against a separately admitted
/// publication using the resolver's own matching rule. This is only membership;
/// namespace completeness and permission to disclose require their own facts.
pub fn unresolved_relation_namespace_presence(
  issue : Issue,
  context : Context,
) -> Bool? {
  match issue {
    UnresolvedRelation(reference) =>
      Some(
        context.inputs.any(input => {
          input_relation_matches(reference.path, input)
        }),
      )
    _ => None
  }
}
