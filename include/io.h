/*
* Copyright (c) 2018
* Markus Goetz
*
* This software may be modified and distributed under the terms of MIT-style license.
*
* Description: HDF5 I/O layer for HPDBSCAN
*
* Maintainer: m.goetz
*
* Email: markus.goetz@kit.edu
*/

#ifndef IO_H
#define IO_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstddef>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef WITH_MPI
#include <mpi.h>
#include "mpi_util.h"
#endif

#include "constants.h"
#include "dataset.h"

class IO {
public:
    // HDF5 handling removed; use read_csv instead

    // Read a CSV file where each row is a point and columns are features.
    // The CSV parser expects numeric values separated by commas. Missing values or
    // non-numeric entries will throw a runtime_error.
    static Dataset read_csv(const std::string& path) {
        std::ifstream in(path);
        if (!in.is_open()) {
            throw std::invalid_argument("Could not open " + path);
        }

        std::string line;
        std::vector<double> values;
        size_t rows = 0;
        size_t cols = 0;

        // read file line by line
        while (std::getline(in, line)) {
            if (line.empty()) continue;
            std::istringstream ss(line);
            std::string token;
            size_t current_cols = 0;
            while (std::getline(ss, token, ',')) {
                // trim whitespace
                size_t start = token.find_first_not_of(" \t\r\n");
                size_t end = token.find_last_not_of(" \t\r\n");
                if (start == std::string::npos) token = "";
                else token = token.substr(start, end - start + 1);

                if (token.empty()) {
                    throw std::runtime_error("Empty field in CSV is not supported");
                }

                char* endptr = nullptr;
                double v = std::strtod(token.c_str(), &endptr);
                if (endptr == token.c_str() || *endptr != '\0') {
                    throw std::runtime_error("Non-numeric value in CSV: " + token);
                }
                values.push_back(v);
                ++current_cols;
            }
            if (cols == 0) cols = current_cols;
            else if (current_cols != cols) {
                throw std::runtime_error("Inconsistent number of columns in CSV");
            }
            ++rows;
        }

        if (rows == 0 || cols == 0) {
            throw std::runtime_error("CSV file seems empty or malformed");
        }

    size_t shape[2];
    shape[0] = static_cast<size_t>(rows);
    shape[1] = static_cast<size_t>(cols);

    // create a Dataset and copy the values into it (double precision)
    Dataset dataset(shape, sizeof(double));
        double* target = static_cast<double*>(dataset.m_p);
        std::copy(values.begin(), values.end(), target);

        #ifdef WITH_MPI
        // In MPI mode, scatter rows across ranks so each process has its chunk
        int rank, size;
        MPI_Comm_rank(MPI_COMM_WORLD, &rank);
        MPI_Comm_size(MPI_COMM_WORLD, &size);

        // compute local chunk sizes
        size_t base = rows / static_cast<size_t>(size);
        size_t rem = rows % static_cast<size_t>(size);
        size_t local_rows = base + (static_cast<size_t>(rank) < rem ? 1 : 0);

        // build receive buffer for local_rows * cols
        double* local_buf = static_cast<double*>(malloc(local_rows * cols * sizeof(double)));
        if (!local_buf) throw std::bad_alloc();

        // prepare sendcounts/displs in terms of doubles
        std::vector<int> sendcounts(size);
        std::vector<int> displs(size);
        size_t offset = 0;
        for (int r = 0; r < size; ++r) {
            size_t rrows = base + (static_cast<size_t>(r) < rem ? 1 : 0);
            sendcounts[r] = static_cast<int>(rrows * cols);
            displs[r] = static_cast<int>(offset * cols);
            offset += rrows;
        }

        MPI_Scatterv(values.data(), sendcounts.data(), displs.data(), MPI_DOUBLE,
                     local_buf, static_cast<int>(local_rows * cols), MPI_DOUBLE,
                     0, MPI_COMM_WORLD);

        // replace dataset buffer with local buffer and set chunk/offset
        free(dataset.m_p);
        dataset.m_p = local_buf;
        dataset.m_chunk[0] = local_rows;
        dataset.m_chunk[1] = cols;
        dataset.m_offset[0] = displs[rank] / cols;
        #else
        // single process: chunk == shape
        dataset.m_chunk[0] = static_cast<size_t>(shape[0]);
        dataset.m_chunk[1] = static_cast<size_t>(shape[1]);
        #endif

        return dataset;
    }

    static void write_csv(const std::string& path, Clusters& clusters) {
        std::ofstream out(path);
        if (!out.is_open()) {
            throw std::invalid_argument("Could not open " + path);
        }
        // write one cluster label per line
        for (size_t i = 0; i < clusters.size(); ++i) {
            out << clusters[i] << '\n';
        }
    }
};

#endif // IO_H
