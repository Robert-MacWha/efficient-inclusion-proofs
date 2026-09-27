use criterion::Throughput;
use criterion::measurement::{Measurement, ValueFormatter};

use crate::counting::CountingHasher;

/// Criterion counter that measures the number of hashes performed during a
/// benchmark. Relies on [`CountingHasher`].
pub struct HashCount;

struct HashFormatter;

impl Measurement for HashCount {
    type Intermediate = usize;
    type Value = usize;

    fn start(&self) -> usize {
        CountingHasher::count()
    }

    fn end(&self, start: usize) -> usize {
        CountingHasher::count() - start
    }

    fn add(&self, a: &usize, b: &usize) -> usize {
        a + b
    }

    fn zero(&self) -> usize {
        0
    }

    fn to_f64(&self, value: &usize) -> f64 {
        *value as f64
    }

    fn formatter(&self) -> &dyn ValueFormatter {
        &HashFormatter
    }
}

impl ValueFormatter for HashFormatter {
    fn scale_values(&self, _typical: f64, _values: &mut [f64]) -> &'static str {
        "hashes"
    }

    fn scale_throughputs(
        &self,
        _typical: f64,
        throughput: &Throughput,
        values: &mut [f64],
    ) -> &'static str {
        let Throughput::Elements(elements) = throughput else {
            return "hashes";
        };
        for value in values {
            *value /= *elements as f64;
        }
        "hashes/append"
    }

    fn scale_for_machines(&self, _values: &mut [f64]) -> &'static str {
        "hashes"
    }
}
