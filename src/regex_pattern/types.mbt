///|
pub(all) enum ClassItem {
  Scalar(Int)
  Range(Int, Int)
  Escape(String)
} derive(Eq, Debug)

///|
/// Child indices belong to this Pattern only; arrays returned by node_at are copies.
pub(all) enum Node {
  Literal(Int)
  ClassEscape(String)
  CharacterClass(Bool, Array[ClassItem])
  Dot
  Anchor(String)
  Capture(Int, Int)
  Sequence(Array[Int])
  Alternation(Array[Int])
  Repeat(Double, Double?, Int)
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_input_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_ast_bytes : Int
  max_ast_nodes : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidUnicode(Int)
  NonCanonicalText
  InvalidSyntax(Int)
  InvalidRange(Int)
  InvalidQuantifier(Int)
  QuantifierOutOfRange(Int)
  NullableRepeat(Int)
} derive(Eq, Debug)

///|
priv struct Entry {
  node : Node
  nullable : Bool
  depth : Int
}

///|
struct Pattern {
  entries : Array[Entry]
  root : Int
  captures : Int
  cid : String
  input_bytes : Int
  ast_bytes : Int
  ast_nodes : Int
}

///|
pub fn root(v : Pattern) -> Int {
  v.root
}

///|
pub fn capture_count(v : Pattern) -> Int {
  v.captures
}

///|
pub fn cid(v : Pattern) -> String {
  v.cid
}

///|
pub fn node_count(v : Pattern) -> Int {
  v.entries.length()
}

///|
pub fn node_at(v : Pattern, index : Int) -> Node? {
  v.entries
  .get(index)
  .map(fn(e) {
    match e.node {
      CharacterClass(n, items) => CharacterClass(n, items.copy())
      Sequence(items) => Sequence(items.copy())
      Alternation(items) => Alternation(items.copy())
      node => node
    }
  })
}

///|
pub fn nullable(v : Pattern) -> Bool {
  v.entries[v.root].nullable
}

///|
/// Input UTF-8 bytes, complete AST bytes, complete AST JSON nodes.
pub fn usage(v : Pattern) -> (Int, Int, Int) {
  (v.input_bytes, v.ast_bytes, v.ast_nodes)
}
