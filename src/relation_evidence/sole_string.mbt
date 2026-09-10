///|
/// Selects exactly one distinct non-null string singleton field, not the first
/// of several canonical candidates. Repeated witnesses for one field count once.
pub fn select_sole_string_key(
  source : @decode.Cursor,
  value : KeySet,
  limits : TransferLimits,
) -> Result[KeySelection, Issue] {
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let mut selected : KeyedRelation? = None
    let mut ambiguous = false
    spend(b, source, value.witnesses.length())
    for key in value.witnesses {
      spend(b, source, key.aliases.length())
      for aliases in key.aliases {
        spend(b, source, aliases.length())
        for field in aliases {
          charge(b, source, field.name)
          if key.aliases.length() != 1 {
            continue
          }
          guard field.contract is Some(c) &&
            !c.nullable &&
            c.shape is @contract.Text(_) else {
            continue
          }
          match selected {
            None =>
              selected = Some({ ..key, fields: [field], aliases: [[field]], })
            Some(first) =>
              if first.fields[0].name != field.name {
                ambiguous = true
              }
          }
        }
      }
    }
    Ok({
      key: if ambiguous {
        None
      } else {
        selected
      },
      work: limits.max_work - b.work,
      name_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
