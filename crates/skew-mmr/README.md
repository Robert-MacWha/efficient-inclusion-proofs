# skew-mmr

The skew-MMR is a list of perfect Merkle trees, similar to a Merkle mountain range, with modified insertion rules that ensure each insertion requires at most one hash.

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

## Insertion

### Case 1: The two rightmost nodes are not the same depth

The new node is appended to the list without any hashes.

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
```

### Case 2: The two rightmost nodes are the same depth

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
```
