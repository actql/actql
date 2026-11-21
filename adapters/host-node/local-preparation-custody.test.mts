import test from 'node:test';
import assert from 'node:assert/strict';
import {createLocalPreparationCustody} from './local-preparation-custody.mjs';
import type {installLocalPreparationRegistry} from './local-preparation-registry.mjs';

type Assert<T extends true> = T;
type Registry = ReturnType<typeof installLocalPreparationRegistry>;
type Resource = NonNullable<Parameters<typeof installLocalPreparationRegistry>[2]>;
type AsyncBorrow = () => PromiseLike<object>;
declare const override: unique symbol;
type PrototypeMethod = {prototypeMethod(): void};
type SymbolOverride = {[override]: true};
type CopiesPrototype = (value: PrototypeMethod) => PrototypeMethod;
type CopiesSymbolOverride = (value: object, changes: SymbolOverride) => SymbolOverride;
type _SynchronousBorrow = Assert<AsyncBorrow extends Resource['borrow'] ? false : true>;
type _NoPrototypeMethodClaim = Assert<Registry['copy'] extends CopiesPrototype ? false : true>;
type _NoSymbolOverrideClaim = Assert<Registry['copy'] extends CopiesSymbolOverride ? false : true>;


test('Local preparation custody accepts only its frozen nominal handle', () => {
  const value = {};
  const owner = createLocalPreparationCustody(value);
  const other = createLocalPreparationCustody(value);
  assert.ok(Object.isFrozen(owner));
  assert.ok(Object.isFrozen(owner.handle));
  assert.deepEqual(Reflect.ownKeys(owner.handle), []);
  assert.throws(() => owner.borrow(other.handle), /ForeignLocalPreparation/);
  assert.throws(() => owner.borrow({}), /ForeignLocalPreparation/);
  const borrow = owner.borrow(owner.handle);
  assert.ok(Object.isFrozen(borrow));
  assert.equal(borrow.prepared, value);
  assert.equal(Object.hasOwn(Object.getOwnPropertyDescriptor(borrow, 'prepared')!, 'value'), false);
  borrow.release();
  assert.throws(() => borrow.prepared, /BorrowReleased/);
});

test('Local preparation custody retains pending cleanup and closes new borrowing', () => {
  const value = {};
  const owner = createLocalPreparationCustody(value);
  const first = owner.borrow(owner.handle);
  const last = owner.borrow(owner.handle);
  owner.requestRetirement();
  owner.requestRetirement();
  assert.throws(() => owner.borrow(owner.handle), /Retired/);
  first.release();
  first.release();
  // Pending or unknown cleanup has no completion capability invocation.
  assert.equal(last.prepared, value);
  owner.confirmRetired();
  assert.equal(last.prepared, value);
  last.release();
  assert.throws(() => last.prepared, /BorrowReleased/);
  owner.confirmRetired();
  assert.throws(() => owner.borrow(owner.handle), /Retired/);
});

test('Local preparation custody allows completion after final borrower release only after retirement request', () => {
  const owner = createLocalPreparationCustody({});
  assert.throws(() => owner.confirmRetired(), /RetirementNotRequested/);
  const borrow = owner.borrow(owner.handle);
  borrow.release();
  const another = owner.borrow(owner.handle);
  another.release();
  owner.requestRetirement();
  owner.confirmRetired();
  assert.throws(() => owner.borrow(owner.handle), /Retired/);
  assert.throws(() => another.prepared, /BorrowReleased/);
});
