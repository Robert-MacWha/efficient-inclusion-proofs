mod counting;
mod measurement;

use std::hint::black_box;

use criterion::{BenchmarkId, Criterion, Throughput, criterion_group, criterion_main};
use skew_mmr::SkewMmr;

use counting::CountingHasher;
use measurement::HashCount;

const SIZES: [usize; 4] = [1 << 8, 1 << 12, 1 << 16, 1 << 20];

type Mmr = SkewMmr<26, u64, CountingHasher>;

fn append(c: &mut Criterion<HashCount>) {
    let mut group = c.benchmark_group("append");
    group.sample_size(10);

    for n in SIZES {
        group.throughput(Throughput::Elements(n as u64));
        group.bench_function(BenchmarkId::from_parameter(n), |b| {
            b.iter(|| filled(black_box(n)));
        });
    }
}

/// The oldest element sits deepest in the tallest (first) tree, so this is the worst-case path.
fn verify(c: &mut Criterion<HashCount>) {
    let mut group = c.benchmark_group("verify");
    group.sample_size(10);

    for n in SIZES {
        let proof = filled(n).prove(0);
        group.bench_function(BenchmarkId::from_parameter(n), |b| {
            b.iter(|| black_box(&proof).verify());
        });
    }
}

fn filled(n: usize) -> Mmr {
    let mut mmr = Mmr::new();
    for i in 0..n as u64 {
        mmr.append(i);
    }
    mmr
}

criterion_group! {
    name = hashes;
    config = Criterion::default().with_measurement(HashCount);
    targets = append, verify
}
criterion_main!(hashes);
