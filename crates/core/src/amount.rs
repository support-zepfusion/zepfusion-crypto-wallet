/// Format an integer base-unit amount with a decimal point.
///
/// `amount` is a decimal string. No floating point is used.
pub fn format_base_units(amount: &str, decimals: u8) -> Option<String> {
    if amount.is_empty() || !amount.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let digits = amount.trim_start_matches('0');
    if digits.is_empty() {
        return Some("0".to_string());
    }
    let places = usize::from(decimals);
    if places == 0 {
        return Some(digits.to_string());
    }
    let mut rendered = if digits.len() <= places {
        let mut value = String::from("0.");
        value.extend(std::iter::repeat_n('0', places - digits.len()));
        value.push_str(digits);
        value
    } else {
        let split = digits.len() - places;
        let mut value = String::new();
        value.push_str(&digits[..split]);
        value.push('.');
        value.push_str(&digits[split..]);
        value
    };
    if rendered.contains('.') {
        while rendered.ends_with('0') {
            rendered.pop();
        }
        if rendered.ends_with('.') {
            rendered.pop();
        }
    }
    Some(rendered)
}

/// Parse a non-negative integer. Rejects hex, signs, and decimal points.
pub fn parse_base_units(amount: &str) -> Option<u128> {
    if amount.is_empty() || !amount.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    amount.parse().ok()
}

/// Convert a JSON-RPC hex quantity (`0x` optional) into a decimal string.
///
/// Accepts up to 32 bytes so a `uint256` balance does not overflow.
pub fn hex_quantity_to_dec(value: &str) -> Option<String> {
    let hex = value.strip_prefix("0x").unwrap_or(value);
    if hex.is_empty() {
        return Some("0".to_string());
    }
    if !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) || hex.len() > 64 {
        return None;
    }
    let padded = if hex.len() % 2 == 1 {
        format!("0{hex}")
    } else {
        hex.to_string()
    };
    let bytes = hex::decode(padded).ok()?;
    Some(be_bytes_to_dec(&bytes))
}

fn be_bytes_to_dec(bytes: &[u8]) -> String {
    if bytes.iter().all(|byte| *byte == 0) {
        return "0".to_string();
    }
    let mut digits: Vec<u8> = Vec::new();
    for &byte in bytes {
        let mut carry = u32::from(byte);
        for digit in &mut digits {
            let value = u32::from(*digit) * 256 + carry;
            *digit = (value % 10) as u8;
            carry = value / 10;
        }
        while carry > 0 {
            digits.push((carry % 10) as u8);
            carry /= 10;
        }
    }
    digits
        .iter()
        .rev()
        .map(|digit| char::from(b'0' + digit))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{format_base_units, hex_quantity_to_dec};

    #[test]
    fn formats_eth_units_without_floats() {
        assert_eq!(format_base_units("0", 18).unwrap(), "0");
        assert_eq!(format_base_units("1", 18).unwrap(), "0.000000000000000001");
        assert_eq!(format_base_units("1000000000000000000", 18).unwrap(), "1");
        assert_eq!(format_base_units("1500000000000000000", 18).unwrap(), "1.5");
    }

    #[test]
    fn parses_sepolia_chain_id_and_zero() {
        assert_eq!(hex_quantity_to_dec("0xaa36a7").unwrap(), "11155111");
        assert_eq!(hex_quantity_to_dec("0x0").unwrap(), "0");
        assert_eq!(hex_quantity_to_dec("0x").unwrap(), "0");
        assert!(hex_quantity_to_dec("0x1g").is_none());
    }
}
