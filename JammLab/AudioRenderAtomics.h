#ifndef AudioRenderAtomics_h
#define AudioRenderAtomics_h

#include <stdint.h>

typedef struct JammLabAtomicInt64 JammLabAtomicInt64;

JammLabAtomicInt64 * _Nonnull JammLabAtomicInt64Create(int64_t initialValue);
void JammLabAtomicInt64Destroy(JammLabAtomicInt64 * _Nullable storage);
int64_t JammLabAtomicInt64Load(const JammLabAtomicInt64 * _Nonnull storage);
void JammLabAtomicInt64Store(JammLabAtomicInt64 * _Nonnull storage, int64_t value);
int64_t JammLabAtomicInt64Increment(JammLabAtomicInt64 * _Nonnull storage);
int64_t JammLabAtomicInt64Decrement(JammLabAtomicInt64 * _Nonnull storage);

#endif
