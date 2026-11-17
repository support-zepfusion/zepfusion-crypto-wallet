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

/// Move a base-unit integer from `from_decimals` to `to_decimals`.
///
/// Scaling up appends zeros. Scaling down succeeds only when the dropped
/// digits are all zero, so a unified total never truncates. Leading zeros
/// are stripped. No floating point is used.
pub fn scale_base_units(amount: &str, from_decimals: u8, to_decimals: u8) -> Option<String> {
    let digits = normalize_digits(amount)?;
    if to_decimals == from_decimals || digits == "0" {
        return Some(digits);
    }
    if to_decimals > from_decimals {
        let extra = usize::from(to_decimals - from_decimals);
        let mut scaled = digits;
        scaled.extend(std::iter::repeat_n('0', extra));
        return Some(scaled);
    }
    let drop = usize::from(from_decimals - to_decimals);
    if digits.len() <= drop
        || !digits.as_bytes()[digits.len() - drop..]
            .iter()
            .all(|byte| *byte == b'0')
    {
        return None;
    }
    normalize_digits(&digits[..digits.len() - drop])
}

/// Add two non-negative integer strings. The inputs may be longer than `u128`.
pub fn add_base_units(left: &str, right: &str) -> Option<String> {
    let left_digits = normalize_digits(left)?;
    let right_digits = normalize_digits(right)?;
    if left_digits == "0" {
        return Some(right_digits);
    }
    if right_digits == "0" {
        return Some(left_digits);
    }
    let left_bytes = left_digits.as_bytes();
    let right_bytes = right_digits.as_bytes();
    let width = left_bytes.len().max(right_bytes.len());
    let mut out = vec![0u8; width];
    let mut carry = 0u8;
    for offset in 0..width {
        let left_digit = digit_at(left_bytes, offset);
        let right_digit = digit_at(right_bytes, offset);
        let sum = left_digit + right_digit + carry;
        out[width - 1 - offset] = b'0' + (sum % 10);
        carry = sum / 10;
    }
    let mut result = String::new();
    if carry > 0 {
        result.push(char::from(b'0' + carry));
    }
    result.push_str(std::str::from_utf8(&out).ok()?);
    Some(result)
}

fn normalize_digits(amount: &str) -> Option<String> {
    if amount.is_empty() || !amount.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let trimmed = amount.trim_start_matches('0');
    if trimmed.is_empty() {
        Some("0".to_string())
    } else {
        Some(trimmed.to_string())
    }
}

fn digit_at(bytes: &[u8], offset_from_end: usize) -> u8 {
    if offset_from_end >= bytes.len() {
        0
    } else {
        bytes[bytes.len() - 1 - offset_from_end] - b'0'
    }
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
    use super::{add_base_units, format_base_units, hex_quantity_to_dec, scale_base_units};

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

    #[test]
    fn scales_and_adds_without_truncation_or_floats() {
        assert_eq!(
            scale_base_units("1500000", 6, 18).unwrap(),
            "1500000000000000000"
        );
        assert_eq!(scale_base_units("1000", 6, 3).unwrap(), "1");
        assert_eq!(scale_base_units("1500000", 6, 3).unwrap(), "1500");
        assert!(scale_base_units("1500001", 6, 3).is_none());
        assert_eq!(add_base_units("999", "1").unwrap(), "1000");
        let wide = "9".repeat(70);
        let sum = add_base_units(&wide, "1").unwrap();
        assert_eq!(sum.len(), 71);
        assert!(sum.starts_with('1'));
        assert!(add_base_units("1.5", "1").is_none());
    }
}
