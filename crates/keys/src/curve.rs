/// Signature algorithm family used by a chain.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Curve {
    /// Bitcoin, EVM, and TRON. BIP-32 / BIP-44.
    Secp256k1,
    /// Solana and Sui. SLIP-0010 ed25519.
    Ed25519,
}
