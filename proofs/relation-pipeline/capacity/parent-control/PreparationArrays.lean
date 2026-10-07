/- Conditional preparation storage component. Element widths, source cardinality,
   live buffers and implementation correspondence are premises. Clearing does
   not discharge initialized referents or prove physical reclamation. -/
namespace PreparationArrays

def envelope (ports fields : Nat) : Nat :=
  80 + 16 * ArrayBacking.ceiling 0 ports + 8 * ArrayBacking.ceiling 0 fields

structure Footprint where
  owners : Nat
  headers : Nat
  selectedSlots : Nat
  columnsSlots : Nat

def Footprint.bytes (s : Footprint) : Nat :=
  s.owners + s.headers + 8 * s.selectedSlots + 4 * s.columnsSlots

theorem storage_bound (ports fields : Nat) (s : Footprint)
    (owners : s.owners ≤ 48) (headers : s.headers ≤ 32)
    (selected : s.selectedSlots ≤ 2 * ArrayBacking.ceiling 0 ports)
    (columns : s.columnsSlots ≤ 2 * ArrayBacking.ceiling 0 fields) :
    s.bytes ≤ envelope ports fields := by
  have a := Nat.mul_le_mul_left 8 selected
  have b := Nat.mul_le_mul_left 4 columns
  unfold Footprint.bytes envelope
  omega

-- A transfer of the same Array is an alias, not an additional allocation.
-- This reuses the existing identity-aware resource model rather than adding
-- bytes once for the cursor and again for the published ProducerRead.
theorem same_storage_charge (r : RelationCapacity.Registry) (live : Nat → Bool) :
    RelationCapacity.charge r.ids r.size (fun id => live id || live id) =
      RelationCapacity.charge r.ids r.size live := by
  simp

end PreparationArrays
