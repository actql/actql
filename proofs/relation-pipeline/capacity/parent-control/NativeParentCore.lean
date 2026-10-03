/- Retained native parent-core model only. ABI/layout and complete source
   coverage are correspondence premises. Selection, edge and returned objects
   remain separate obligations; this is not a replacement for count * 256. -/
namespace NativeParentCore

def slots (count : Nat) : Nat := ArrayBacking.ceiling 1 count
def envelope (count : Nat) : Nat := 680 + 16 * slots count

structure Footprint where
  references : Nat
  owner : Nat
  callbacks : Nat
  environment : Nat
  reported : Nat
  arrayOwners : Nat
  backingHeaders : Nat
  backingSlots : Nat

def Footprint.bytes (s : Footprint) : Nat :=
  s.references + s.owner + s.callbacks + s.environment + s.reported +
  s.arrayOwners + s.backingHeaders + 8 * s.backingSlots

theorem phase_bound (count : Nat) (s : Footprint)
    (references : s.references ≤ 160) (owner : s.owner ≤ 56)
    (callbacks : s.callbacks ≤ 248) (environment : s.environment ≤ 120)
    (reported : s.reported ≤ 32) (owners : s.arrayOwners ≤ 48)
    (headers : s.backingHeaders ≤ 16) (backings : s.backingSlots ≤ 2 * slots count) :
    s.bytes ≤ envelope count := by
  have scaled := Nat.mul_le_mul_left 8 backings
  unfold Footprint.bytes envelope
  omega

-- Reuses the existing grow-at-full rule, including old/new overlap. This does
-- not pretend that a single current-buffer observation explores the overlap.
theorem growth_overlap (count old next : Nat)
    (a : old ≤ slots count) (b : next ≤ slots count) :
    8 * (old + next) ≤ 16 * slots count := by
  have sum := ArrayBacking.growth_overlap 1 count old next a b
  have scaled := Nat.mul_le_mul_left 8 sum
  omega

-- A model witness, not an implementation/GC assertion. Closed children do
-- not imply that the immutable parent callbacks and their held Refs vanished.
def retired : Footprint := ⟨136, 56, 248, 120, 16, 24, 0, 0⟩
theorem retired_owner_witness : retired.bytes = 600 := by rfl

end NativeParentCore
