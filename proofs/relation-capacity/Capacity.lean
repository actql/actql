/- Conditional allocation-capacity model. Registry identities are physical
   allocations, not values/CIDs. Each ID has one stable nonnegative byte size.
   Neither child bounds nor the 256-byte parent bound are asserted as facts. -/
namespace RelationCapacity

structure Registry where
  ids : List Nat
  unique : ids.Pairwise (fun a b => a ≠ b)
  size : Nat → Nat

def charge (ids : List Nat) (size : Nat → Nat) (live : Nat → Bool) : Nat :=
  match ids with
  | [] => 0
  | id :: rest => (if live id then size id else 0) + charge rest size live

structure Child where
  retained : Nat
  execution : Nat
  live : Nat → Bool

def childrenLive (children : List Child) (id : Nat) : Bool :=
  match children with
  | [] => false
  | child :: rest => child.live id || childrenLive rest id

def childCapacity (children : List Child) : Nat :=
  match children with
  | [] => 0
  | child :: rest => child.retained + child.execution + childCapacity rest

def reservation (baseRetained baseExecution : Nat) (children : List Child) : Nat :=
  baseRetained + max baseExecution (childCapacity children + children.length * 256)

theorem charge_mono (ids : List Nat) (size : Nat → Nat) (a b : Nat → Bool)
    (covered : ∀ id ∈ ids, a id = true → b id = true) :
    charge ids size a ≤ charge ids size b := by
  induction ids with
  | nil => simp [charge]
  | cons id rest ih =>
    have tail := ih (by intro x member yes; exact covered x (by simp [member]) yes)
    have head : (if a id then size id else 0) ≤ (if b id then size id else 0) := by
      cases ha : a id <;> cases hb : b id <;> simp_all
    simp only [charge]
    omega

theorem charge_union (ids : List Nat) (size : Nat → Nat) (a b : Nat → Bool) :
    charge ids size (fun id => a id || b id) ≤ charge ids size a + charge ids size b := by
  induction ids with
  | nil => simp [charge]
  | cons id rest ih =>
    cases ha : a id <;> cases hb : b id <;> simp only [charge, ha, hb,
      Bool.or_false, Bool.or_true, Bool.false_eq_true, ↓reduceIte] <;> omega

theorem shared_identity_once (ids : List Nat) (size : Nat → Nat) (a : Nat → Bool) :
    charge ids size (fun id => a id || a id) = charge ids size a := by
  have same : (fun id => a id || a id) = a := by
    funext id; cases a id <;> rfl
  rw [same]

theorem distinct_copy_counts (a b : Nat) (different : a ≠ b) (size : Nat → Nat) :
    ([a, b].Pairwise (fun x y => x ≠ y)) ∧
    charge [a, b] size (fun _ => true) = size a + size b := by
  simp [charge, different]

theorem children_bound (ids : List Nat) (size : Nat → Nat) (children : List Child)
    (bounds : ∀ child ∈ children,
      charge ids size child.live ≤ child.retained + child.execution) :
    charge ids size (childrenLive children) ≤ childCapacity children := by
  induction children with
  | nil => induction ids <;> simp_all [charge, childrenLive, childCapacity]
  | cons child rest ih =>
    have head := bounds child (by simp)
    have tail := ih (by intro x member; exact bounds x (by simp [member]))
    have union := charge_union ids size child.live (childrenLive rest)
    change charge ids size (fun id => child.live id || childrenLive rest id) ≤
      child.retained + child.execution + childCapacity rest
    omega

theorem live_chain_bound (registry : Registry) (live base parent : Nat → Bool)
    (children : List Child) (baseRetained baseExecution : Nat)
    (coverage : ∀ id ∈ registry.ids, live id = true →
      (base id || childrenLive children id || parent id) = true)
    (baseBound : charge registry.ids registry.size base ≤ baseRetained)
    (childBounds : ∀ child ∈ children,
      charge registry.ids registry.size child.live ≤ child.retained + child.execution)
    (parentBound : charge registry.ids registry.size parent ≤ children.length * 256) :
    charge registry.ids registry.size live ≤ reservation baseRetained baseExecution children := by
  have covered := charge_mono registry.ids registry.size live
    (fun id => base id || childrenLive children id || parent id) coverage
  have outer := charge_union registry.ids registry.size
    (fun id => base id || childrenLive children id) parent
  have inner := charge_union registry.ids registry.size base (childrenLive children)
  have childrenBound := children_bound registry.ids registry.size children childBounds
  unfold reservation
  have room := Nat.le_max_right baseExecution (childCapacity children + children.length * 256)
  omega

-- Cleanup pending means the actual live predicates have not shrunk merely
-- because a terminal poll was observed. Proven releases may only shrink them.
theorem confirmed_release_nonincreasing (registry : Registry) (before after : Nat → Bool)
    (released : ∀ id ∈ registry.ids, after id = true → before id = true) :
    charge registry.ids registry.size after ≤ charge registry.ids registry.size before :=
  charge_mono registry.ids registry.size after before released

theorem pending_cleanup_keeps_bytes (registry : Registry) (before after : Nat → Bool)
    (pending : after = before) :
    charge registry.ids registry.size after = charge registry.ids registry.size before := by
  rw [pending]

theorem old_and_new_coexist (registry : Registry) (old fresh : Nat → Bool) :
    charge registry.ids registry.size old ≤
      charge registry.ids registry.size (fun id => old id || fresh id) :=
  charge_mono registry.ids registry.size old (fun id => old id || fresh id)
    (by intro id _ oldLive; simp [oldLive])

def int64Max : Nat := 9223372036854775807
def checkedAdd (a b : Nat) : Option Nat :=
  if a + b ≤ int64Max then some (a + b) else none

theorem checked_add_exact (a b : Nat) (fits : a + b ≤ int64Max) :
    checkedAdd a b = some (a + b) := by simp [checkedAdd, fits]

theorem checked_add_rejects_overflow (a b : Nat) (overflow : int64Max < a + b) :
    checkedAdd a b = none := by simp [checkedAdd, Nat.not_le.mpr overflow]

theorem subtraction_guard_equivalent (a b : Nat) (validB : b ≤ int64Max) :
    a ≤ int64Max - b ↔ a + b ≤ int64Max := Nat.le_sub_iff_add_le validB

theorem int_count_handles_fit (count : Nat) (intRange : count ≤ 2147483647) :
    count * 256 ≤ int64Max := by unfold int64Max; omega

theorem checked_add_boundary :
    checkedAdd int64Max 0 = some int64Max ∧ checkedAdd int64Max 1 = none := by
  constructor
  · simpa using checked_add_exact int64Max 0 (by omega)
  · exact checked_add_rejects_overflow int64Max 1 (by omega)

end RelationCapacity
