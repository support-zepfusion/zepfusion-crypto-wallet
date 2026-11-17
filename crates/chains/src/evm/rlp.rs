//! Minimal RLP for EIP-1559 transactions.
//!
//! Integer encoding strips leading zeros. Zero is the empty byte string.

use cofinex_core::ChainError;

pub fn rlp_bytes(bytes: &[u8]) -> Vec<u8> {
    if bytes.len() == 1 && bytes[0] < 0x80 {
        return bytes.to_vec();
    }
    let mut out = length_prefix(0x80, bytes.len());
    out.extend_from_slice(bytes);
    out
}

pub fn rlp_uint(value: u128) -> Vec<u8> {
    if value == 0 {
        return vec![0x80];
    }
    let width = (value.ilog2() as usize / 8) + 1;
    let bytes = value.to_be_bytes();
    rlp_bytes(&bytes[bytes.len() - width..])
}

pub fn rlp_list(items: &[Vec<u8>]) -> Vec<u8> {
    let payload = items.iter().flatten().copied().collect::<Vec<_>>();
    let mut out = length_prefix(0xc0, payload.len());
    out.extend_from_slice(&payload);
    out
}

fn length_prefix(short_base: u8, len: usize) -> Vec<u8> {
    if len < 56 {
        vec![short_base + len as u8]
    } else {
        let len_bytes = usize_be(len);
        let mut out = vec![short_base + 55 + len_bytes.len() as u8];
        out.extend_from_slice(&len_bytes);
        out
    }
}

fn usize_be(value: usize) -> Vec<u8> {
    let bytes = value.to_be_bytes();
    let start = bytes
        .iter()
        .position(|byte| *byte != 0)
        .unwrap_or(bytes.len() - 1);
    bytes[start..].to_vec()
}

pub struct Eip1559 {
    pub chain_id: u64,
    pub nonce: u64,
    pub max_priority_fee_per_gas: u128,
    pub max_fee_per_gas: u128,
    pub gas_limit: u64,
    pub to: [u8; 20],
    pub value: u128,
    pub data: Vec<u8>,
}

impl Eip1559 {
    fn fields(&self) -> Vec<Vec<u8>> {
        vec![
            rlp_uint(u128::from(self.chain_id)),
            rlp_uint(u128::from(self.nonce)),
            rlp_uint(self.max_priority_fee_per_gas),
            rlp_uint(self.max_fee_per_gas),
            rlp_uint(u128::from(self.gas_limit)),
            rlp_bytes(&self.to),
            rlp_uint(self.value),
            rlp_bytes(&self.data),
            rlp_list(&[]),
        ]
    }

    /// `0x02 || rlp([...])`, the bytes whose keccak is the signing digest.
    pub fn signing_preimage(&self) -> Vec<u8> {
        let mut out = vec![0x02];
        out.extend(rlp_list(&self.fields()));
        out
    }

    pub fn signed_raw(&self, y_parity: u8, r: &[u8], s: &[u8]) -> Result<Vec<u8>, ChainError> {
        if y_parity > 1 || r.len() != 32 || s.len() != 32 {
            return Err(ChainError::InvalidSignature);
        }
        let mut fields = self.fields();
        fields.push(rlp_uint(u128::from(y_parity)));
        fields.push(rlp_bytes(&strip_leading_zeros(r)));
        fields.push(rlp_bytes(&strip_leading_zeros(s)));
        let mut out = vec![0x02];
        out.extend(rlp_list(&fields));
        Ok(out)
    }
}

fn strip_leading_zeros(bytes: &[u8]) -> Vec<u8> {
    let start = bytes
        .iter()
        .position(|byte| *byte != 0)
        .unwrap_or(bytes.len());
    if start == bytes.len() {
        Vec::new()
    } else {
        bytes[start..].to_vec()
    }
}

/// Read the chain id out of a type-2 transaction, signed or unsigned.
pub fn eip1559_chain_id(raw: &[u8]) -> Result<u64, ChainError> {
    if raw.first().copied() != Some(0x02) {
        return Err(ChainError::InvalidTransaction);
    }
    let (payload, rest) = read_list(&raw[1..]).map_err(|_| ChainError::InvalidTransaction)?;
    if !rest.is_empty() {
        return Err(ChainError::InvalidTransaction);
    }
    let (chain_bytes, _) = read_string(payload).map_err(|_| ChainError::InvalidTransaction)?;
    bytes_to_u64(chain_bytes).map_err(|_| ChainError::InvalidTransaction)
}

fn read_string(input: &[u8]) -> Result<(&[u8], &[u8]), ()> {
    let prefix = *input.first().ok_or(())?;
    if prefix <= 0x7f {
        Ok((&input[..1], &input[1..]))
    } else if prefix <= 0xb7 {
        let len = (prefix - 0x80) as usize;
        let end = 1 + len;
        if input.len() < end {
            return Err(());
        }
        Ok((&input[1..end], &input[end..]))
    } else if prefix <= 0xbf {
        let len_of_len = (prefix - 0xb7) as usize;
        if input.len() < 1 + len_of_len {
            return Err(());
        }
        let len = be_to_usize(&input[1..1 + len_of_len])?;
        let start = 1 + len_of_len;
        let end = start + len;
        if input.len() < end {
            return Err(());
        }
        Ok((&input[start..end], &input[end..]))
    } else {
        Err(())
    }
}

fn read_list(input: &[u8]) -> Result<(&[u8], &[u8]), ()> {
    let prefix = *input.first().ok_or(())?;
    if (0xc0..=0xf7).contains(&prefix) {
        let len = (prefix - 0xc0) as usize;
        let end = 1 + len;
        if input.len() < end {
            return Err(());
        }
        Ok((&input[1..end], &input[end..]))
    } else if prefix >= 0xf8 {
        let len_of_len = (prefix - 0xf7) as usize;
        if input.len() < 1 + len_of_len {
            return Err(());
        }
        let len = be_to_usize(&input[1..1 + len_of_len])?;
        let start = 1 + len_of_len;
        let end = start + len;
        if input.len() < end {
            return Err(());
        }
        Ok((&input[start..end], &input[end..]))
    } else {
        Err(())
    }
}

fn be_to_usize(bytes: &[u8]) -> Result<usize, ()> {
    if bytes.len() > core::mem::size_of::<usize>() {
        return Err(());
    }
    let mut value = 0usize;
    for byte in bytes {
        value = value
            .checked_shl(8)
            .ok_or(())?
            .checked_add(usize::from(*byte))
            .ok_or(())?;
    }
    Ok(value)
}

fn bytes_to_u64(bytes: &[u8]) -> Result<u64, ()> {
    if bytes.len() > 8 {
        return Err(());
    }
    let mut value = 0u64;
    for byte in bytes {
        value = value
            .checked_shl(8)
            .ok_or(())?
            .checked_add(u64::from(*byte))
            .ok_or(())?;
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::{eip1559_chain_id, rlp_bytes, rlp_list, rlp_uint, Eip1559};

    #[test]
    fn matches_ethereum_wiki_vectors() {
        assert_eq!(hex::encode(rlp_bytes(b"dog")), "83646f67");
        assert_eq!(
            hex::encode(rlp_list(&[rlp_bytes(b"cat"), rlp_bytes(b"dog")])),
            "c88363617483646f67"
        );
        assert_eq!(hex::encode(rlp_bytes(b"")), "80");
        assert_eq!(hex::encode(rlp_list(&[])), "c0");
        assert_eq!(hex::encode(rlp_uint(0)), "80");
        assert_eq!(hex::encode(rlp_uint(15)), "0f");
        assert_eq!(hex::encode(rlp_uint(1024)), "820400");
    }

    #[test]
    fn eip1559_preimage_matches_an_independent_encoder() {
        let tx = Eip1559 {
            chain_id: 11155111,
            nonce: 0,
            max_priority_fee_per_gas: 1_000_000_000,
            max_fee_per_gas: 2_000_000_000,
            gas_limit: 21_000,
            to: hex::decode("9858EfFD232B4033E47d90003D41EC34EcaEda94")
                .unwrap()
                .try_into()
                .unwrap(),
            value: 1,
            data: Vec::new(),
        };
        let preimage = tx.signing_preimage();
        assert_eq!(
            hex::encode(&preimage),
            "02ea83aa36a780843b9aca008477359400825208949858effd232b4033e47d90003d41ec34ecaeda940180c0"
        );
        assert_eq!(eip1559_chain_id(&preimage).unwrap(), 11155111);
    }
}
