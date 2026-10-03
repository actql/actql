/- Selected native Array storage. Element ABI, actual backing identity and
   completeness of the allocation census remain correspondence premises. -/
namespace NativeArrayExtent

def extent (elementBytes slots : Nat) : Nat := 24 + 8 + elementBytes * slots

theorem input_bound (bytes slots maximum : Nat) (capacity : slots ≤ maximum) :
    extent bytes slots ≤ extent bytes maximum := by
  have multiplied := Nat.mul_le_mul_left bytes capacity
  unfold extent
  omega

structure Allocation where
  identity : Nat
  bytes : Nat
  ceiling : Nat

def unionBytes (seen : List Nat) : List Allocation → Nat
  | [] => 0
  | a :: rest =>
    if seen.contains a.identity then unionBytes seen rest
    else a.bytes + unionBytes (a.identity :: seen) rest

def totalCeiling : List Allocation → Nat
  | [] => 0
  | a :: rest => a.ceiling + totalCeiling rest

-- The same allocation contributes once; every fresh identity contributes its
-- own extent. The gate separately rejects inconsistent facts for an alias.
theorem union_bounded (allocations : List Allocation) (seen : List Nat)
    (bounded : ∀ a ∈ allocations, a.bytes ≤ a.ceiling) :
    unionBytes seen allocations ≤ totalCeiling allocations := by
  induction allocations generalizing seen with
  | nil => simp [unionBytes, totalCeiling]
  | cons a rest ih =>
    have head := bounded a (by simp)
    have tail : ∀ b ∈ rest, b.bytes ≤ b.ceiling := by
      intro b member
      exact bounded b (by simp [member])
    have kept := ih seen tail
    have fresh := ih (a.identity :: seen) tail
    simp only [unionBytes, totalCeiling]
    split <;> omega

theorem shared_once (identity bytes bound : Nat) :
    unionBytes [] [{ identity, bytes, ceiling := bound },
      { identity, bytes, ceiling := bound }] = bytes := by
  simp [unionBytes]

end NativeArrayExtent
