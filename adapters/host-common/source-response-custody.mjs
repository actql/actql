// One consuming grammar for the standard reader's response borrow callback.
// Capturing or calling this port supplies no grant, charge, retirement or ACK.
import {types} from 'node:util';

export function captureSourceResponseCustody(holder, invalid, retainUnjoinedNative) {
  if (holder === undefined) return undefined;
  if (types.isProxy(holder) || holder === null || typeof holder !== 'object') throw invalid();
  const fields = Object.getOwnPropertyDescriptors(holder);
  if (!Object.isFrozen(holder) || Reflect.ownKeys(fields).length !== 1 ||
      !Object.hasOwn(fields.retain ?? {}, 'value') || typeof fields.retain.value !== 'function') {
    throw invalid();
  }
  const retain = fields.retain.value;
  return function retainSourceResponse(response) {
    const returned = Reflect.apply(retain, holder, [response]);
    if (returned === undefined) return;
    // A non-Unit callback may still own an in-flight response borrow. Join
    // that exact result before refusing; never turn its result into an ACK.
    if (types.isPromise(returned)) {
      let observation, observationFailed = false;
      let joined;
      try {
        joined = Reflect.apply(Promise.prototype.then, returned, [() => {
          if (observationFailed) throw observation;
          throw invalid();
        }, cause => {throw observationFailed ? observation : cause;}]);
      } catch (cause) {
        // Native then still observes constructor/species before returning its
        // join. If that fails, only the existing physical Owner can retain the
        // unresolved original; the thrown error is not its cleanup ACK.
        retainUnjoinedNative?.(returned, cause);
        throw cause;
      }
      // Retain the actual native join before a caller-substituted public
      // getter can throw. Its failure stays primary after actual settlement.
      try {void returned.then;}
      catch (cause) {observation = cause;observationFailed = true;}
      return joined;
    }
    return Promise.resolve(returned).then(() => {throw invalid();});
  };
}
