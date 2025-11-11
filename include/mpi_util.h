/*
* Copyright (c) 2018
* Markus Goetz
*
* This software may be modified and distributed under the terms of MIT-style license.
*
* Description: MPI type selection utility
*
* Maintainer: m.goetz
*
* Email: markus.goetz@kit.edu
*/

#ifndef MPI_UTIL_H
#define MPI_UTIL_H

#include <cstdint>

#include <mpi.h>

template <typename T>
struct MPI_Types;

#define SPECIALIZE_MPI_TYPE(type, mpi_type) \
template <> \
struct MPI_Types<type> { \
    static MPI_Datatype map() {\
        return mpi_type; \
    } \
}

SPECIALIZE_MPI_TYPE(uint8_t,  MPI_UINT8_T);
SPECIALIZE_MPI_TYPE(uint16_t, MPI_UINT16_T);
SPECIALIZE_MPI_TYPE(uint32_t, MPI_UINT32_T);
SPECIALIZE_MPI_TYPE(uint64_t, MPI_UINT64_T);

SPECIALIZE_MPI_TYPE(int8_t,  MPI_INT8_T);
SPECIALIZE_MPI_TYPE(int16_t, MPI_INT16_T);
SPECIALIZE_MPI_TYPE(int32_t, MPI_INT32_T);
SPECIALIZE_MPI_TYPE(int64_t, MPI_INT64_T);

SPECIALIZE_MPI_TYPE(float,  MPI_FLOAT);
SPECIALIZE_MPI_TYPE(double, MPI_DOUBLE);

// NOTE: do not add additional SPECIALIZE_MPI_TYPE entries for aliases like
// `size_t` or `long` here. On some platforms (LP64) the fixed-width typedefs
// such as uint64_t / int64_t are aliases of `unsigned long` / `long` and
// adding additional specializations causes duplicate-definition errors.
// If a mapping for `size_t` or `long` is needed, prefer a platform-aware
// fallback or conditional mapping elsewhere.

// Portable helper returning an MPI_Datatype for size_t.
// Avoids template specialization collisions on LP64 platforms.
inline MPI_Datatype MPI_Type_for_size_t() {
#if SIZE_MAX == UINT64_MAX
    return MPI_UNSIGNED_LONG;
#elif SIZE_MAX == UINT32_MAX
    return MPI_UNSIGNED;
#else
#error "Unsupported size_t width for MPI mapping"
#endif
}

#endif // MPI_UTIL_H
