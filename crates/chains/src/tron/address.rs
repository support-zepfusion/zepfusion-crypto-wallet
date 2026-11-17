//! TRON base58check addresses.
//!
//! The 20-byte account id is keccak256 of the uncompressed secp256k1 key, the
//! same bytes as an EVM address. TRON prepends `0x41` and encodes base58check
//! (double SHA-256, 4-byte checksum). Path is BIP-44 coin type 195:
//! `m/44'/195'/0'/0/0`.

use cofinex_core::{Address, ChainError, ChainId, PublicKey};
use cofinex_keys::Curve;
use sha2::{Digest, Sha256};
use sha3::Keccak256;

const ADDRESS_PREFIX: u8 = 0x41;
const ALPHABET: &[u8] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

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
    let mut payload = [0u8; 21];
    payload[0] = ADDRESS_PREFIX;
    payload[1..].copy_from_slice(&hash[12..]);
    Ok(Address::new(ChainId::Tron, encode_payload(&payload)))
}

pub fn parse_tron_address(text: &str) -> Result<[u8; 21], ChainError> {
    let decoded = base58_decode(text).ok_or(ChainError::InvalidAddress)?;
    if decoded.len() != 25 || decoded[0] != ADDRESS_PREFIX {
        return Err(ChainError::InvalidAddress);
    }
    let (payload, checksum) = decoded.split_at(21);
    if checksum != &sha256d(payload)[..4] {
        return Err(ChainError::InvalidAddress);
    }
    let mut out = [0u8; 21];
    out.copy_from_slice(payload);
    Ok(out)
}

pub fn account_bytes(payload: &[u8; 21]) -> [u8; 20] {
    let mut account = [0u8; 20];
    account.copy_from_slice(&payload[1..]);
    account
}

fn encode_payload(payload: &[u8; 21]) -> String {
    let checksum = sha256d(payload);
    let mut full = [0u8; 25];
    full[..21].copy_from_slice(payload);
    full[21..].copy_from_slice(&checksum[..4]);
    base58_encode(&full)
}

fn sha256d(bytes: &[u8]) -> [u8; 32] {
    let first = Sha256::digest(bytes);
    let second = Sha256::digest(first);
    let mut out = [0u8; 32];
    out.copy_from_slice(&second);
    out
}

fn base58_encode(bytes: &[u8]) -> String {
    let zeros = bytes.iter().take_while(|byte| **byte == 0).count();
    let mut digits: Vec<u8> = Vec::new();
    for &byte in bytes {
        let mut carry = u32::from(byte);
        for digit in &mut digits {
            carry += u32::from(*digit) * 256;
            *digit = (carry % 58) as u8;
            carry /= 58;
        }
        while carry > 0 {
            digits.push((carry % 58) as u8);
            carry /= 58;
        }
    }
    let mut out = String::new();
    out.extend(std::iter::repeat_n('1', zeros));
    for digit in digits.iter().rev() {
        out.push(ALPHABET[*digit as usize] as char);
    }
    out
}

fn base58_decode(text: &str) -> Option<Vec<u8>> {
    if text.is_empty() {
        return Some(Vec::new());
    }
    let zeros = text
        .chars()
        .take_while(|character| *character == '1')
        .count();
    let mut bytes: Vec<u8> = Vec::new();
    for character in text.chars() {
        let value = ALPHABET
            .iter()
            .position(|symbol| *symbol as char == character)? as u32;
        let mut carry = value;
        for byte in &mut bytes {
            carry += u32::from(*byte) * 58;
            *byte = (carry % 256) as u8;
            carry /= 256;
        }
        while carry > 0 {
            bytes.push((carry % 256) as u8);
            carry /= 256;
        }
    }
    let mut out = vec![0u8; zeros];
    out.extend(bytes.iter().rev());
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::{base58_decode, base58_encode, parse_tron_address};

    #[test]
    fn base58_matches_the_published_vectors() {
        assert_eq!(base58_encode(b"hello"), "Cn8eVZg");
        assert_eq!(base58_encode(b"Hello World"), "JxF12TrwUP45BMd");
        assert_eq!(base58_encode(&[0, 0]), "11");
        assert_eq!(base58_decode("Cn8eVZg").unwrap(), b"hello");
    }

    #[test]
    fn official_usdt_contract_roundtrips() {
        let text = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t";
        let payload = parse_tron_address(text).unwrap();
        assert_eq!(payload[0], 0x41);
        let encoded = {
            let checksum_payload = payload;
            super::encode_payload(&checksum_payload)
        };
        assert_eq!(encoded, text);
        assert!(parse_tron_address("TInvalid").is_err());
    }
}
