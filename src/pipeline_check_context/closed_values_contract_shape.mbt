///|
/// Preconstruction cardinalities of the existing contract collector for exactly
/// one Stage, one literal-only Number Values operation, one projected Result,
/// no inputs/parameters/effects and no numeric reductions. These are not a
/// validator, grant or complete preparation-memory quote. The shape owner must
/// establish those original-source preconditions before using this dependency.
pub(all) struct ClosedValuesContractShape {
  roots : Int
  bodies : Int
  dependency_owners : Int
  unique_edges : Int
  visited_edges : Int
  stages : Int
} derive(Eq, Debug)

///|
/// No source or output traversal and no contract collection occurs here.
/// Roots: environment3 + stage semantics5 + Result1 + transfer1 + Values3
/// + RelA adopted laws2. Bodies: expression15 (4 + inherited11), grammar4,
/// adopted3, source1, stage semantics4, canonical identity1, transfer1, Values3.
/// Edges: environment7 + expression root3 + regex1 + inherited12 + Values1.
/// Repeated GraphLaw and UnicodeData sites are visited but deduplicated in the
/// retained adjacency. Every selected CID is borrowed from its fixed contract
/// owner; this collection does not clone the interpreted installation Catalog.
pub fn closed_values_contract_shape() -> ClosedValuesContractShape {
  {
    roots: 15,
    bodies: 32,
    dependency_owners: 8,
    unique_edges: 22,
    visited_edges: 24,
    stages: 1,
  }
}
