/*
 * Copyright (c) 2017-2018, NVIDIA CORPORATION.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#include "SingleHashGraph.cuh"
#include "SingleHashGraphOperators.cuh"
#include <iostream>
#include <fstream>
#include <vector>
#include <set>

#include <thrust/random.h>
#include <thrust/device_vector.h>
#include <thrust/transform.h>
#include <thrust/iterator/counting_iterator.h>

#include <cuda_profiler_api.h> //--profile-from-start off

// #include <moderngpu/memory.hxx>
// #include <moderngpu/kernel_sortedsearch.hxx>
// #include <moderngpu/kernel_mergesort.hxx>
// #include <moderngpu/kernel_merge.hxx>
// #include <moderngpu/kernel_scan.hxx>
// #include <moderngpu/kernel_segsort.hxx>

#include <cuda_runtime_api.h>
#include <cub/cub.cuh>

// #include "rmm/rmm.h"
// #include "rmm.h"

// using namespace mgpu;


using hkey_t = int64_t;
using index_t = int32_t;
using HashKey = uint32_t;

// Uncomment once we remove "using namespace hornets_nest"
// const int BLOCK_SIZE_OP2 = 256;

#define DISABLE_A
#define MULTI_GPU

// #define DEBUG
#define CORRECTNESS

int BLOCK_COUNT = -1;
int BLOCK_SIZE_OP2 = 256; // TODO: Double check this.

#define SEQ_KEYS

struct prg {
  hkey_t lo, hi;

  __host__ __device__ prg(hkey_t _lo=0, hkey_t _hi=0) : lo(_lo), hi(_hi) {};

  __host__ __device__ hkey_t operator()(unsigned long long index) const {
    thrust::default_random_engine rng(index);
    thrust::uniform_int_distribution<hkey_t> dist(lo, hi);
    rng.discard(index);
    return dist(rng);
  }
};

SingleHashGraph::SingleHashGraph(int64_t countSize, int64_t maxkey, // context_t &context, 
                                    int64_t tableSize)
                                      // : 
                                      //   d_hash(countSize, context, memory_space_device),
                                      //  d_edges(countSize, context, memory_space_device)
                                      {

  // d_vals = fill_random_64((hkey_t)0, maxkey, countSize, false, context);
  // d_vals = fill_sequence((hkey_t)0, maxkey, context);
  // d_counter = fill((index_t)0, (size_t)(tableSize + 1), context);
  // d_offset = fill((index_t)0, (size_t)(tableSize + 1), context);

  cudaMalloc(&d_vals, countSize * sizeof(hkey_t));
  cudaMalloc(&d_hash, countSize * sizeof(HashKey));
  cudaMalloc(&d_counter, (tableSize + 1) * sizeof(index_t));
  cudaMalloc(&d_offset, (tableSize + 1) * sizeof(index_t));
  cudaMalloc(&d_edges, countSize * sizeof(keyval));

  cudaMemset(d_counter, 0, (tableSize + 1) * sizeof(index_t));
  cudaMemset(d_offset, 0, (tableSize + 1) * sizeof(index_t));

#ifdef SEQ_KEYS
  HashKey *h_hash = new HashKey[countSize]();
  for (HashKey i = 0; i < countSize; i++) {
    h_hash[i] = i;
  }
  cudaMemcpy(d_hash, h_hash, countSize * sizeof(HashKey), cudaMemcpyHostToDevice);
#else
  thrust::counting_iterator<hkey_t> index_sequence_begin(seed);
  thrust::transform(thrust::device, index_sequence_begin, index_sequence_begin + countSize,
                      d_vals, prg(0, maxkey));
#endif

  BLOCK_COUNT = std::ceil(countSize / ((float) BLOCK_SIZE_OP2));

}

SingleHashGraph::~SingleHashGraph() {
}

// template<typename hkey_t, typename HashKey,  typename index_t, typename keyval>
// void buildTable(mem_t<hkey_t> &d_vals, mem_t<HashKey> &d_hash, mem_t<index_t> &d_counter, 
// 	            mem_t<index_t> &d_offSet, mem_t<keyval> &d_edges, index_t valCount, 
//                     index_t tableSize, context_t& context, int32_t valsOffset=0) {
void buildTable(hkey_t *d_vals, HashKey *d_hash, index_t *d_counter, 
	            index_t *d_offSet, keyval *d_edges, index_t valCount, 
                    index_t tableSize, int32_t valsOffset=0) {

  void*  _d_temp_storage     { nullptr };
  size_t _temp_storage_bytes { 0 };

  hashValuesD<<<BLOCK_COUNT, BLOCK_SIZE_OP2>>>(valCount, d_vals + valsOffset, 
                                                    d_hash, (HashKey) tableSize);

  countHashD<<<BLOCK_COUNT, BLOCK_SIZE_OP2>>>(valCount, d_hash, d_counter);

  cub::DeviceScan::ExclusiveSum(_d_temp_storage, _temp_storage_bytes, d_counter, 
                                    d_offSet, tableSize);
  cudaMalloc(&_d_temp_storage, _temp_storage_bytes);
  cub::DeviceScan::ExclusiveSum(_d_temp_storage, _temp_storage_bytes, d_counter, 
                                    d_offSet, tableSize);

  // d_counter = fill(0, (size_t)tableSize, context);
  cudaMemset(d_counter, 0, tableSize * sizeof(index_t));
  cudaMemcpy(d_offSet + tableSize, &valCount, sizeof(index_t), cudaMemcpyHostToDevice);
  cudaFree(_d_temp_storage);

  copyToGraphD<<<BLOCK_COUNT, BLOCK_SIZE_OP2>>>(valCount, d_vals + valsOffset, 
                                    d_hash, d_counter, d_offSet, 
                                    d_edges, tableSize);
}

// void SingleHashGraph::build(int64_t countSize, context_t &context, int64_t tableSize) {
void SingleHashGraph::build(int64_t countSize, int64_t tableSize) {

  buildTable(d_vals, d_hash, d_counter, d_offset, d_edges, (index_t)countSize, 
                (index_t) tableSize);
                // (index_t) tableSize, context);

}
