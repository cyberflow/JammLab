#include "AudioRenderAtomics.h"

#include <stdatomic.h>
#include <stdlib.h>

struct JammLabAtomicInt64 {
    _Atomic int64_t value;
};

JammLabAtomicInt64 *JammLabAtomicInt64Create(int64_t initialValue) {
    JammLabAtomicInt64 *storage = malloc(sizeof(JammLabAtomicInt64));
    if (storage == NULL) {
        abort();
    }
    atomic_init(&storage->value, initialValue);
    return storage;
}

void JammLabAtomicInt64Destroy(JammLabAtomicInt64 *storage) {
    free(storage);
}

int64_t JammLabAtomicInt64Load(const JammLabAtomicInt64 *storage) {
    return atomic_load_explicit(&storage->value, memory_order_acquire);
}

void JammLabAtomicInt64Store(JammLabAtomicInt64 *storage, int64_t value) {
    atomic_store_explicit(&storage->value, value, memory_order_release);
}

int64_t JammLabAtomicInt64Increment(JammLabAtomicInt64 *storage) {
    return atomic_fetch_add_explicit(&storage->value, 1, memory_order_acq_rel) + 1;
}

int64_t JammLabAtomicInt64Decrement(JammLabAtomicInt64 *storage) {
    return atomic_fetch_sub_explicit(&storage->value, 1, memory_order_acq_rel) - 1;
}
