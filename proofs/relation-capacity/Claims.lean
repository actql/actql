-- Independent consumer proposition signatures. Premises cannot disappear when
-- a theorem is relabeled or its conclusion is weakened.
example (registry : RelationCapacity.Registry) (live base parent : Nat → Bool)
    (children : List RelationCapacity.Child) (retained execution : Nat)
    (covered : ∀ id ∈ registry.ids, live id = true →
      (base id || RelationCapacity.childrenLive children id || parent id) = true)
    (baseBound : RelationCapacity.charge registry.ids registry.size base ≤ retained)
    (childBounds : ∀ child ∈ children,
      RelationCapacity.charge registry.ids registry.size child.live ≤ child.retained + child.execution)
    (parentBound : RelationCapacity.charge registry.ids registry.size parent ≤ children.length * 256) :
    RelationCapacity.charge registry.ids registry.size live ≤
      retained + max execution (RelationCapacity.childCapacity children + children.length * 256) :=
  RelationCapacity.live_chain_bound registry live base parent children retained execution
    covered baseBound childBounds parentBound

example (ids : List Nat) (size : Nat → Nat) (live : Nat → Bool) :
    RelationCapacity.charge ids size (fun id => live id || live id) =
      RelationCapacity.charge ids size live :=
  RelationCapacity.shared_identity_once ids size live

example (a b : Nat) (different : a ≠ b) (size : Nat → Nat) :
    [a, b].Pairwise (fun x y => x ≠ y) ∧
    RelationCapacity.charge [a, b] size (fun _ => true) = size a + size b :=
  RelationCapacity.distinct_copy_counts a b different size

example (a b : Nat) (validB : b ≤ RelationCapacity.int64Max) :
    a ≤ RelationCapacity.int64Max - b ↔ a + b ≤ RelationCapacity.int64Max :=
  RelationCapacity.subtraction_guard_equivalent a b validB
