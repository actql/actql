// Private, presently unactivated Local ownership helper. This is neither a
// public preparation API nor a resource reservation or heap-size proof.
// The installing cleanup owner alone retains the controller. It may confirm
// retirement only after its existing original cleanup duties have completed.
export function createLocalPreparationCustody(prepared) {
  if (prepared === null || typeof prepared !== 'object') {
    throw new TypeError('InvalidLocalPreparation');
  }
  const handle = Object.freeze(Object.create(null));
  let retirementRequested = false;
  let retirementConfirmed = false;
  let borrowers = 0;
  const clearIfRetired = () => {
    if (retirementRequested && retirementConfirmed && borrowers === 0) {
      prepared = undefined;
    }
  };
  return Object.freeze({
    handle,
    borrow(original) {
      if (original !== handle) throw new TypeError('ForeignLocalPreparation');
      if (retirementRequested || prepared === undefined) {
        throw new Error('LocalPreparationRetired');
      }
      if (borrowers === Number.MAX_SAFE_INTEGER) {
        throw new RangeError('LocalPreparationBorrowCountOverflow');
      }
      borrowers++;
      let active = true;
      // The getter never embeds a raw preparation in a retained borrow object.
      // Trusted borrowers must discard any cached getter result before release;
      // JavaScript cannot revoke an object already copied by such a borrower.
      return Object.freeze({
        get prepared() {
          if (!active) throw new Error('LocalPreparationBorrowReleased');
          return prepared;
        },
        release() {
          if (!active) return;
          active = false;
          borrowers--;
          clearIfRetired();
        },
      });
    },
    requestRetirement() {
      retirementRequested = true;
      clearIfRetired();
    },
    // Private completion capability: never expose this controller to clients
    // or call this from a terminal-status Boolean or an uncertain cleanup path.
    confirmRetired() {
      if (!retirementRequested) throw new Error('LocalPreparationRetirementNotRequested');
      retirementConfirmed = true;
      clearIfRetired();
    },
  });
}
