/*
* Copyright (c) 2018
* Markus Goetz
*
* This software may be modified and distributed under the terms of MIT-style license.
*
* Description: Dataset abstraction
*
* Maintainer: m.goetz
*
* Email: markus.goetz@kit.edu
*/

#ifndef DATASET_H
#define DATASET_H

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#ifdef WITH_MPI
#include <mpi.h>
#endif

#include "constants.h"

struct Dataset {
    // shape: number of rows and columns (features)
    size_t m_shape[2];
    // chunk describes the local chunk size per process (rows, cols)
    size_t m_chunk[2];
    // offset of this chunk inside the global dataset
    size_t m_offset[2] = {0, 0};
    // size in bytes of a single element
    size_t m_element_size;
    // raw pointer to the data buffer
    void* m_p;

    // construct an empty dataset given shape and element size
    Dataset(const size_t shape[2], size_t element_size) {
        m_shape[0] = shape[0];
        m_shape[1] = shape[1];
        m_chunk[0] = m_shape[0];
        m_chunk[1] = m_shape[1];

        m_element_size = element_size;
        m_p = malloc(m_shape[0] * m_shape[1] * m_element_size);
        if (!m_p) throw std::bad_alloc();
    }

    // construct from typed data (copies into internal buffer)
    template <typename T>
    Dataset(T* data, const size_t shape[2], size_t element_size) : Dataset(shape, element_size) {
        size_t total = static_cast<size_t>(shape[0]) * static_cast<size_t>(shape[1]);
        std::copy(data, data + total, static_cast<T*>(m_p));

        #ifdef WITH_MPI
        // determine the global shape (sum over first dimension)
        MPI_Allreduce(MPI_IN_PLACE, m_shape, 1, MPI_UNSIGNED_LONG, MPI_SUM, MPI_COMM_WORLD);
        // ... and the chunk offset
        int rank;
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
        MPI_Exscan(m_chunk, m_offset, 1, MPI_UNSIGNED_LONG, MPI_SUM, MPI_COMM_WORLD);
        if (rank == 0) m_offset[0] = 0;
        #endif
    }

    ~Dataset() {
        free(m_p);
    }
};

#endif // DATASET_H
