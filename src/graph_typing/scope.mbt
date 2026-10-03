///|
pub(all) enum EntityKind {
  Nodes
  Edges
} derive(Eq, Debug)

///|
priv struct CheckedScope {
  fields : @carrier.Knowledge
  usage : Usage
}
