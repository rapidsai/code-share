/** GMetis -*- C++ -*-
 * @file
 * @section License
 *
 * Galois, a framework to exploit amorphous data-parallelism in irregular
 * programs.
 *
 * Copyright (C) 2013, The University of Texas at Austin. All rights reserved.
 * UNIVERSITY EXPRESSLY DISCLAIMS ANY AND ALL WARRANTIES CONCERNING THIS
 * SOFTWARE AND DOCUMENTATION, INCLUDING ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR ANY PARTICULAR PURPOSE, NON-INFRINGEMENT AND WARRANTIES OF
 * PERFORMANCE, AND ANY WARRANTY THAT MIGHT OTHERWISE ARISE FROM COURSE OF
 * DEALING OR USAGE OF TRADE.  NO WARRANTY IS EITHER EXPRESS OR IMPLIED WITH
 * RESPECT TO THE USE OF THE SOFTWARE OR DOCUMENTATION. Under no circumstances
 * shall University be liable for incidental, special, indirect, direct or
 * consequential damages or loss of profits, interruption of business, or
 * related expenses which may arise from use of Software or Documentation,
 * including but not limited to those resulting from defects in Software and/or
 * Documentation, or loss or inaccuracy of data of any kind.
 *
 * @author Xin Sui <xinsui@cs.utexas.edu>
 * @author Andrew Lenharth <andrew@lenharth.org>
 */

#include "Metis.h"

#include <iomanip>
#include <iostream>
#include <numeric>

struct onlineStat {
  unsigned num;
  unsigned val;
  double valSQ;
  unsigned mmin;
  unsigned mmax;

  onlineStat() :num(0), val(0), valSQ(0), mmin(std::numeric_limits<unsigned>::max()), mmax(0) {}

  void add(unsigned v) {
    ++num;
    val += v;
    valSQ += (double)v*(double)v;
    mmin = std::min(v, mmin);
    mmax = std::max(v, mmax);
  }

  double mean() {
    return (double)val / (double)num;
  }

  double variance() {
    double t = valSQ / (double)num;
    double m = mean();
    return t - m*m;
  }

  unsigned count() { return num; }
  unsigned total() { return val; }
  unsigned min() { return mmin; }
  unsigned max() { return mmax; }
};
    

unsigned  graphStat(GGraph* graph) {
  onlineStat e;
  for (auto ii = graph->begin(), ee = graph->end(); ii != ee; ++ii) {
    unsigned val = std::distance(graph->edge_begin(*ii), graph->edge_end(*ii));
    e.add(val);
  }
  std::cout << "Nodes " << e.count()
            << " Edges(total, var, min, max) " 
            << e.total() << " "
            << e.variance() << " "
            << e.min() << " "
            << e.max();
  return e.count();
}

std::vector<unsigned> edgeCut(GGraph& g, unsigned nparts) {
  std::vector<unsigned> cuts(nparts);

 //find boundary nodes with positive gain
  for (auto nn = g.begin(), en = g.end(); nn != en; ++nn) {
    unsigned gPart = g.getData(*nn).getPart();
    for (auto ii = g.edge_begin(*nn), ee = g.edge_end(*nn); ii != ee; ++ii) {
      auto& m = g.getData(g.getEdgeDst(ii));
      if (m.getPart() != gPart) {
        cuts.at(gPart) += g.getEdgeData(ii);
      }
    }
  }
  return cuts;
}

unsigned computeCut(GGraph& g) {
  unsigned cuts=0;
  for (auto nn = g.begin(), en = g.end(); nn != en; ++nn) {
    unsigned gPart = g.getData(*nn).getPart();
    for (auto ii = g.edge_begin(*nn), ee = g.edge_end(*nn); ii != ee; ++ii) {
      auto& m = g.getData(g.getEdgeDst(ii));
      if (m.getPart() != gPart) 
        cuts += g.getEdgeData(ii);
    }
  }
  return cuts/2;
}


void printPartStats(std::vector<partInfo>& parts) {
  onlineStat e;
  for (unsigned x = 0; x < parts.size(); ++x) {
    e.add(parts[x].partWeight);
  }
  std::cout << "target " << e.total() / e.count() << " var " << e.variance() << " min " << e.min() << " max " << e.max();
}

std::ostream& operator<<(std::ostream& os, const partInfo& p) {
  os << "Num " << std::setw(3) << p.partNum << "\tmask " << std::setw(5) << std::hex << p.partMask << std::dec << "\tweight " << p.partWeight;
  return os;
}

void printCuts(const char* str, MetisGraph* g, unsigned numPartitions) {
  std::vector<unsigned> ec = edgeCut(*g->getGraph(), numPartitions);
  std::cout << str << " Edge Cuts:\n";
  for (unsigned x = 0; x < ec.size(); ++x)
    std::cout << (x == 0 ? "" : " " ) << ec[x];
  std::cout << "\n";
  std::cout << str << " Average Edge Cut: " << (std::accumulate(ec.begin(), ec.end(), 0) / ec.size()) << "\n";
  std::cout << str << " Minimum Edge Cut: " << *std::min_element(ec.begin(), ec.end()) << "\n";
}
