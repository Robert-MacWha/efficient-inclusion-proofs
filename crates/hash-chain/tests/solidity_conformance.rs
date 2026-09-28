use std::error::Error;

use alloy::primitives::{FixedBytes, keccak256};
use alloy::providers::ProviderBuilder;
use alloy::sol;
use hash_chain::HashChain;
use hash_chain::hasher::Hasher;

sol!(
    #[sol(rpc)]
    Contract,
    "../../contracts/out/HashChainVerifier.sol/HashChainVerifier.json"
);

type Chain = HashChain<32, 5, [u8; 32], KeccakHasher>;

/// Matches `_chain` in `HashChain.sol`.
struct KeccakHasher;

impl Hasher<[u8; 32]> for KeccakHasher {
    fn iv() -> [u8; 32] {
        [0u8; 32]
    }

    fn hash(chain: &[u8; 32], element: &[u8; 32]) -> [u8; 32] {
        let mut state: [u8; 64] = [0u8; 64];
        state[0..32].copy_from_slice(chain);
        state[32..64].copy_from_slice(element);
        *keccak256(state)
    }
}

#[tokio::test]
async fn rust_and_solidity_agree_after_every_append() -> Result<(), Box<dyn Error>> {
    let provider = ProviderBuilder::new().connect_anvil_with_wallet();
    let contract = Contract::deploy(&provider).await?;
    let mut chain = Chain::new();

    for i in 0..80 {
        let element = element(i);
        contract
            .append(element.into())
            .send()
            .await?
            .watch()
            .await?;
        chain.append(element);

        let n = i + 1;
        assert_eq!(
            contract.count().call().await?.to::<usize>(),
            chain.len(),
            "count after {n} appends"
        );

        let accumulators = contract.accumulators().call().await?;
        for (level, accumulator) in chain.accumulators().iter().enumerate() {
            assert_eq!(
                accumulators[level].0, *accumulator,
                "accumulator {level} after {n} appends"
            );
        }

        let open: Vec<FixedBytes<32>> = accumulators.to_vec();
        contract
            .verifyAccumulators(contract.count().call().await?, open)
            .call()
            .await
            .map_err(|e| format!("accumulators rejected after {n} appends: {e}"))?;
    }

    Ok(())
}

fn element(i: u64) -> [u8; 32] {
    let mut element = [0u8; 32];
    element[24..].copy_from_slice(&(i + 1).to_be_bytes());
    element
}
