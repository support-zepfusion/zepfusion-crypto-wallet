use cofinex_keys::{
    generate_mnemonic, public_key, sign_with_seed, DerivationPath, PublicKey, Seed, Signature,
};

use crate::{SignRequest, Signer, SignerError};

/// BIP-39 seed held on the device. This is the power-user custody tier from
/// ADR-001. Retail default will be [`crate::MpcSigner`], which implements the
/// same [`Signer`] trait.
pub struct LocalSigner {
    seed: Seed,
}

impl LocalSigner {
    pub fn from_mnemonic(phrase: &str, passphrase: &str) -> Result<Self, SignerError> {
        Ok(Self {
            seed: Seed::from_mnemonic(phrase, passphrase)?,
        })
    }

    /// Generate a new English mnemonic. The phrase is returned once.
    pub fn generate(word_count: usize) -> Result<(Self, String), SignerError> {
        let (phrase, seed) = generate_mnemonic(word_count)?;
        Ok((Self { seed }, phrase))
    }
}

impl core::fmt::Debug for LocalSigner {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("LocalSigner([redacted])")
    }
}

impl Signer for LocalSigner {
    fn backend_name(&self) -> &'static str {
        "local"
    }

    fn public_key(&self, path: &DerivationPath) -> Result<PublicKey, SignerError> {
        Ok(public_key(&self.seed, path)?)
    }

    fn sign(&self, request: &SignRequest<'_>) -> Result<Signature, SignerError> {
        Ok(sign_with_seed(
            &self.seed,
            request.path,
            request.message,
            request.prehashed,
        )?)
    }
}
