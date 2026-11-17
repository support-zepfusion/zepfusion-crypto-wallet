use core::fmt;
use core::str::FromStr;

use crate::curve::Curve;
use crate::KeyError;

const HARDENED_BIT: u32 = 1 << 31;

/// One BIP-32 index. Hardened indexes are stored without the high bit set;
/// [`PathSegment::hardened`] carries that flag instead.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PathSegment {
    pub index: u32,
    pub hardened: bool,
}

impl PathSegment {
    pub fn new(index: u32, hardened: bool) -> Result<Self, KeyError> {
        if index >= HARDENED_BIT {
            return Err(KeyError::InvalidPath);
        }
        Ok(Self { index, hardened })
    }

    /// Index with the BIP-32 hardened bit applied, as HMAC input.
    pub fn to_wire(self) -> u32 {
        if self.hardened {
            self.index | HARDENED_BIT
        } else {
            self.index
        }
    }
}

/// A derivation path such as `m/44'/60'/0'/0/0`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DerivationPath {
    curve: Curve,
    segments: Vec<PathSegment>,
}

impl DerivationPath {
    pub fn new(curve: Curve, segments: Vec<PathSegment>) -> Result<Self, KeyError> {
        if curve == Curve::Ed25519 && segments.iter().any(|segment| !segment.hardened) {
            return Err(KeyError::Ed25519HardenedOnly);
        }
        Ok(Self { curve, segments })
    }

    /// BIP-44 path.
    ///
    /// secp256k1: `m/44'/coin_type'/account'/change/address_index`
    /// ed25519: the same shape with every segment hardened
    /// (`m/44'/coin_type'/account'/change'/address_index'`).
    pub fn bip44(
        curve: Curve,
        coin_type: u32,
        account: u32,
        change: u32,
        address_index: u32,
    ) -> Result<Self, KeyError> {
        let tail_hardened = curve == Curve::Ed25519;
        Self::new(
            curve,
            vec![
                PathSegment::new(44, true)?,
                PathSegment::new(coin_type, true)?,
                PathSegment::new(account, true)?,
                PathSegment::new(change, tail_hardened)?,
                PathSegment::new(address_index, tail_hardened)?,
            ],
        )
    }

    /// Solana's common account path: `m/44'/501'/account'/0'`.
    pub fn solana_account(account: u32) -> Result<Self, KeyError> {
        Self::new(
            Curve::Ed25519,
            vec![
                PathSegment::new(44, true)?,
                PathSegment::new(501, true)?,
                PathSegment::new(account, true)?,
                PathSegment::new(0, true)?,
            ],
        )
    }

    pub fn curve(&self) -> Curve {
        self.curve
    }

    pub fn segments(&self) -> &[PathSegment] {
        &self.segments
    }
}

impl fmt::Display for DerivationPath {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "m")?;
        for segment in &self.segments {
            write!(f, "/{}", segment.index)?;
            if segment.hardened {
                write!(f, "'")?;
            }
        }
        Ok(())
    }
}

impl FromStr for DerivationPath {
    type Err = KeyError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        let mut parts = value.split('/');
        if parts.next() != Some("m") {
            return Err(KeyError::InvalidPath);
        }
        let mut segments = Vec::new();
        for part in parts {
            if part.is_empty() {
                return Err(KeyError::InvalidPath);
            }
            let (number, hardened) = if let Some(stripped) = part
                .strip_suffix('\'')
                .or_else(|| part.strip_suffix('h'))
                .or_else(|| part.strip_suffix('H'))
            {
                (stripped, true)
            } else {
                (part, false)
            };
            let index: u32 = number.parse().map_err(|_| KeyError::InvalidPath)?;
            segments.push(PathSegment::new(index, hardened)?);
        }
        if segments.is_empty() {
            return Err(KeyError::InvalidPath);
        }
        // Curve is not encoded in the path text. Callers that need ed25519
        // construct the path with [`DerivationPath::new`] or [`Self::bip44`].
        Self::new(Curve::Secp256k1, segments)
    }
}
