use cofinex_core::{Address, ChainError, ChainId, PublicKey};
use cofinex_keys::Curve;
use sha3::{Digest, Keccak256};

pub fn address_from_public_key(public_key: &PublicKey) -> Result<Address, ChainError> {
    if public_key.curve() != Curve::Secp256k1 {
        return Err(ChainError::InvalidPublicKey);
    }
    let bytes = public_key.as_bytes();
    let raw = if bytes.len() == 65 && bytes[0] == 0x04 {
        &bytes[1..]
    } else if bytes.len() == 64 {
        bytes
    } else {
        return Err(ChainError::InvalidPublicKey);
    };
    let hash = Keccak256::digest(raw);
    let mut address = [0u8; 20];
    address.copy_from_slice(&hash[12..]);
    Ok(Address::new(
        ChainId::EthereumSepolia,
        format_eip55(&address),
    ))
}

pub fn parse_evm_address(text: &str) -> Result<[u8; 20], ChainError> {
    let hex_body = text
        .strip_prefix("0x")
        .or_else(|| text.strip_prefix("0X"))
        .ok_or(ChainError::InvalidAddress)?;
    if hex_body.len() != 40 || !hex_body.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(ChainError::InvalidAddress);
    }
    let mut bytes = [0u8; 20];
    hex::decode_to_slice(hex_body, &mut bytes).map_err(|_| ChainError::InvalidAddress)?;
    if has_mixed_case(hex_body) {
        let checksummed = format_eip55(&bytes);
        let expected = checksummed
            .strip_prefix("0x")
            .ok_or(ChainError::InvalidAddress)?;
        if hex_body != expected {
            return Err(ChainError::InvalidAddress);
        }
    }
    Ok(bytes)
}

pub fn format_eip55(address: &[u8; 20]) -> String {
    let lowercase = hex::encode(address);
    let hash = Keccak256::digest(lowercase.as_bytes());
    let mut out = String::with_capacity(42);
    out.push_str("0x");
    for (index, character) in lowercase.chars().enumerate() {
        let nibble = if index % 2 == 0 {
            hash[index / 2] >> 4
        } else {
            hash[index / 2] & 0x0f
        };
        if character.is_ascii_alphabetic() && nibble >= 8 {
            out.push(character.to_ascii_uppercase());
        } else {
            out.push(character);
        }
    }
    out
}

fn has_mixed_case(hex_body: &str) -> bool {
    let has_lower = hex_body.bytes().any(|byte| byte.is_ascii_lowercase());
    let has_upper = hex_body.bytes().any(|byte| byte.is_ascii_uppercase());
    has_lower && has_upper
}

#[cfg(test)]
mod tests {
    use super::format_eip55;

    #[test]
    fn eip55_checksum_of_the_bip44_vector() {
        let bytes = hex::decode("9858effd232b4033e47d90003d41ec34ecaeda94").unwrap();
        let mut address = [0u8; 20];
        address.copy_from_slice(&bytes);
        assert_eq!(
            format_eip55(&address),
            "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
        );
    }
}
