//! Wall-clock time of `SkewMmr::prove_element`, which finds an element by value.

use std::hint::black_box;

use criterion::{BenchmarkId, Criterion, criterion_group, criterion_main};
use skew_mmr::{SkewMmr, hasher::Hasher};

const SIZES: [usize; 4] = [1 << 8, 1 << 12, 1 << 16, 1 << 20];

/// A cheap stand-in for a real hash, so the lookup dominates the timings.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CheapHasher;

impl Hasher<u64> for CheapHasher {
    fn hash(element: &u64, left: &u64, right: &u64) -> u64 {
        element.wrapping_mul(31).wrapping_add(left.rotate_left(17)) ^ right
    }
}

type Mmr = SkewMmr<26, u64, CheapHasher>;

/// Proves the oldest element, which has the longest path, and the newest, which a scan from the
/// oldest would reach last.
fn prove_element(c: &mut Criterion) {
    let mut group = c.benchmark_group("prove_element");
    group.sample_size(10);

    for n in SIZES {
        let mut mmr = Mmr::new();
        for i in 0..n as u64 {
            mmr.append(i);
        }

        for (name, element) in [("oldest", 0), ("newest", n as u64 - 1)] {
            group.bench_with_input(BenchmarkId::new(name, n), &element, |b, &element| {
                b.iter(|| mmr.prove_element(black_box(element)));
            });
        }
    }
}

criterion_group!(benches, prove_element);
criterion_main!(benches);
