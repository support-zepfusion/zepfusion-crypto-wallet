use bip39::{Language, Mnemonic};
use zeroize::Zeroizing;

use crate::KeyError;

/// 64-byte BIP-39 seed. The bytes are wiped when this value is dropped.
pub struct Seed {
    bytes: Zeroizing<[u8; 64]>,
}

impl Seed {
    /// Parse an English BIP-39 phrase. Whitespace is collapsed. The passphrase
    /// may be empty. Neither value is retained except as the derived seed.
    pub fn from_mnemonic(phrase: &str, passphrase: &str) -> Result<Self, KeyError> {
        let normalized = phrase.split_whitespace().collect::<Vec<_>>().join(" ");
        if normalized.is_empty() {
            return Err(KeyError::InvalidMnemonic);
        }
        let mnemonic = Mnemonic::parse_in(Language::English, &normalized)
            .map_err(|_| KeyError::InvalidMnemonic)?;
        // `[u8; 64]` is `Copy`, so wrap the seed and wipe the local copy.
        let mut raw = mnemonic.to_seed(passphrase);
        let seed = Self {
            bytes: Zeroizing::new(raw),
        };
        zeroize::Zeroize::zeroize(&mut raw);
        Ok(seed)
    }

    pub(crate) fn as_bytes(&self) -> &[u8; 64] {
        &self.bytes
    }
}

impl core::fmt::Debug for Seed {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("Seed([redacted])")
    }
}

/// Generate a fresh English mnemonic and its seed.
///
/// The phrase is returned once so the caller can show it to the user. This
/// function does not log it. The caller should wipe its copy when finished.
pub fn generate_mnemonic(word_count: usize) -> Result<(String, Seed), KeyError> {
    if !matches!(word_count, 12 | 15 | 18 | 21 | 24) {
        return Err(KeyError::BadWordCount);
    }
    let mnemonic =
        Mnemonic::generate_in(Language::English, word_count).map_err(|_| KeyError::BadWordCount)?;
    let phrase = mnemonic.words().collect::<Vec<_>>().join(" ");
    let seed = Seed::from_mnemonic(&phrase, "")?;
    Ok((phrase, seed))
}
