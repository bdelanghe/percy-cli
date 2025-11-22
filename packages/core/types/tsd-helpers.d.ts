// Simple replacement for tsd's expectType and expectError
// Uses TypeScript's type system directly
// expectType: ensures value matches type T (TypeScript will error if not)
// expectError: ensures value has a type error (assign to never to trigger error if valid)

export function expectType<T>(value: T): void;
export function expectError<T>(value: T & never): void;

