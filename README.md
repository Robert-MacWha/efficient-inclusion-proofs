# skew-mmr

skew-MMR is a merkle tree construction that enables efficient membership proofs with very cheap insertion. 

- [rust](./crates/skew-mmr/): Native implementation and arkworks verifier gadget
- [js](./packages/): Native implementation
- [circom](./circuits/): Circom verifier gadget
- [solidity](./contracts/): Solidity accumulator and frontier verifier

## Benchmarks

Comparison with zk-kit's leanIMT and IMT: [bench/](bench/README.md).

## Overview

Example of a skew-MMR:

```mermaid
flowchart TD
    h1 --> a1
    h1 --> a2
    h1 --> a3
    h2 --> a4
    h2 --> a5
    h2 --> a6
    h3 --> h1
    h3 --> h2
    h1 ~~~ a7
    h3 --> a7
```

### Insertion

Insertion assures that only the two rightmost nodes may have the same depth. Because merging involves three nodes, this means that each insertion requires exactly one hash.

#### Case 1: The two rightmost nodes are not the same depth

The new node is `hash(new, 0, 0)` and appended to the list.

When inserting `a5`:

```mermaid
---
title: before
---
flowchart TD
    h1 --> a1
    h1 --> a2
    h1 --> a3
    h1 ~~~ a4
```

```mermaid
---
title: after
---
flowchart TD
    h1 --> a1
    h1 --> a2
    h1 --> a3
    h1 ~~~ a4
    h1 ~~~ a5
    classDef changed stroke:#f66,stroke-width:2px
    class a5 changed
```

#### Case 2: The two rightmost nodes are the same depth

The two rightmost nodes are popped from the list, hashed with the new node as `hash(new, rightmost, second rightmost)`, and the result is pushed to the list.

When inserting `a6` and `a7`:

```mermaid
---
title: before
---
flowchart TD
    h1 --> a1
    h1 --> a2
    h1 --> a3
    h1 ~~~ a4
    h1 ~~~ a5
```

```mermaid
---
title: after a6
---
flowchart TD
    h1 --> a1
    h1 --> a2
    h1 --> a3
    h2 --> a4
    h2 --> a5
    h2 --> a6
    classDef changed stroke:#f66,stroke-width:2px
    class a6,h2 changed
```

```mermaid
---
title: after a7
---
flowchart TD
    h1 --> a1
    h1 --> a2
    h1 --> a3
    h2 --> a4
    h2 --> a5
    h2 --> a6
    h3 --> h1
    h3 --> h2
    h3 --> a7
    h2 ~~~ a7
    classDef changed stroke:#f66,stroke-width:2px
    class a7,h3 changed
```
