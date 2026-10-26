// One consuming grammar for the standard reader's response borrow callback.
// Capturing or calling this port supplies no grant, charge, retirement or ACK.
import {types} from 'node:util';

export function captureSourceResponseCustody(holder, invalid) {
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
    return Promise.resolve(returned).then(
      () => {throw invalid();},
      () => {throw invalid();},
    );
  };
}
