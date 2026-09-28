use std::error::Error;

use alloy::primitives::{FixedBytes, U256, keccak256};
use alloy::providers::ProviderBuilder;
use alloy::sol;
use skew_mmr::SkewMmr;
use skew_mmr::hasher::Hasher;

sol!(
    #[sol(rpc)]
    Contract,
    "../../contracts/out/SkewMmrVerifier.sol/SkewMmrVerifier.json"
);

type Mmr = SkewMmr<26, [u8; 32], KeccakHasher>;

/// Matches `keccak256(abi.encode(element, left, right))` in `SkewMmr.sol`.
struct KeccakHasher;

impl Hasher<[u8; 32]> for KeccakHasher {
    fn hash(element: &[u8; 32], left: &[u8; 32], right: &[u8; 32]) -> [u8; 32] {
        let mut state: [u8; 96] = [0u8; 96];
        state[0..32].copy_from_slice(element);
        state[32..64].copy_from_slice(left);
        state[64..96].copy_from_slice(right);
        *keccak256(state)
    }
}

#[tokio::test]
async fn rust_and_solidity_agree_after_every_append() -> Result<(), Box<dyn Error>> {
    let provider = ProviderBuilder::new().connect_anvil_with_wallet();
    let contract = Contract::deploy(&provider).await?;
    let mut mmr = Mmr::new();

    for i in 0..80 {
        let element = element(i);
        contract
            .append(element.into())
            .send()
            .await?
            .watch()
            .await?;
        mmr.append(element);

        let n = i + 1;
        let depth: usize = contract.depth().call().await?.to();
        assert_eq!(depth, mmr.depth(), "depth after {n} appends");
        assert_eq!(
            contract.count().call().await?.to::<usize>(),
            mmr.len(),
            "count after {n} appends"
        );

        let roots = mmr.roots();
        let ranks = mmr.ranks();
        for tree in 0..depth {
            let root = contract.roots(U256::from(tree)).call().await?;
            let rank = contract.ranks(U256::from(tree)).call().await?;
            assert_eq!(root.0, roots[tree], "root {tree} after {n} appends");
            assert_eq!(
                u32::from(rank),
                ranks[tree],
                "rank {tree} after {n} appends"
            );
        }

        let frontier: Vec<FixedBytes<32>> = roots.iter().map(|root| (*root).into()).collect();
        contract
            .verifyFrontier(contract.state().call().await?, frontier)
            .call()
            .await
            .map_err(|e| format!("frontier rejected after {n} appends: {e}"))?;
    }

    Ok(())
}

fn element(i: u64) -> [u8; 32] {
    let mut element = [0u8; 32];
    element[24..].copy_from_slice(&(i + 1).to_be_bytes());
    element
}
