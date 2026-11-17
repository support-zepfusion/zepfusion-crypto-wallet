//! Password sealing for the self-custody recovery phrase.
//!
//! The phrase is encrypted with AES-256-GCM. The key is PBKDF2-HMAC-SHA256
//! with [`KDF_ITERATIONS`] iterations and a random 16-byte salt. The blob is
//! what Flutter stores in the Android Keystore via `flutter_secure_storage`.
//! These functions do not log the phrase, the password, or the wrapping key.

use aes_gcm::aead::Aead;
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use pbkdf2::pbkdf2_hmac;
use rand::rngs::OsRng;
use rand::RngCore;
use serde_json::json;
use sha2::Sha256;
use zeroize::Zeroize;

/// OWASP-recommended PBKDF2-HMAC-SHA256 iteration count (2023).
pub const KDF_ITERATIONS: u32 = 600_000;

const MIN_KDF_ITERATIONS: u32 = 100_000;
const MAX_KDF_ITERATIONS: u32 = 5_000_000;
const SALT_LEN: usize = 16;
const NONCE_LEN: usize = 12;
const KEY_LEN: usize = 32;

/// Encrypt `mnemonic` for storage. The returned JSON never contains the phrase.
pub fn seal_mnemonic(mut mnemonic: String, mut password: String) -> Result<String, String> {
    let result = seal_with(&mnemonic, &password);
    mnemonic.zeroize();
    password.zeroize();
    result
}

/// Decrypt a blob produced by [`seal_mnemonic`].
pub fn open_mnemonic(payload: String, mut password: String) -> Result<String, String> {
    let result = open_with_password(&payload, &password).map(|(phrase, mut key)| {
        key.zeroize();
        phrase
    });
    password.zeroize();
    result
}

/// Derive the AES key after the password successfully opens the blob.
///
/// The caller may store this in the Keystore so a later biometric gate can
/// decrypt without asking for the password again. Treat the return value as
/// a secret. It is base64, not the recovery phrase.
pub fn wrapping_key(payload: String, mut password: String) -> Result<String, String> {
    let result = open_with_password(&payload, &password).map(|(mut phrase, mut key)| {
        phrase.zeroize();
        let encoded = STANDARD.encode(key);
        key.zeroize();
        encoded
    });
    password.zeroize();
    result
}

/// Decrypt with a key previously returned by [`wrapping_key`].
pub fn open_with_wrapping_key(
    payload: String,
    mut wrapping_key_b64: String,
) -> Result<String, String> {
    let result = (|| {
        let mut key = decode_key(&wrapping_key_b64)?;
        let opened = open_with_key(&payload, &key);
        key.zeroize();
        opened
    })();
    wrapping_key_b64.zeroize();
    result
}

fn seal_with(mnemonic: &str, password: &str) -> Result<String, String> {
    if mnemonic.trim().is_empty() {
        return Err("mnemonic is empty".to_string());
    }
    require_password(password)?;
    let mut salt = [0u8; SALT_LEN];
    let mut nonce = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut salt);
    OsRng.fill_bytes(&mut nonce);
    let mut key = derive_key(password, &salt, KDF_ITERATIONS)?;
    let ciphertext = encrypt(&key, &nonce, mnemonic.as_bytes())?;
    key.zeroize();
    Ok(json!({
        "v": 1,
        "kdf": "pbkdf2-sha256",
        "iterations": KDF_ITERATIONS,
        "salt": STANDARD.encode(salt),
        "nonce": STANDARD.encode(nonce),
        "ciphertext": STANDARD.encode(ciphertext),
    })
    .to_string())
}

fn open_with_password(payload: &str, password: &str) -> Result<(String, [u8; KEY_LEN]), String> {
    require_password(password)?;
    let (salt, nonce, ciphertext, iterations) = parse_payload(payload)?;
    let key = derive_key(password, &salt, iterations)?;
    let phrase = decrypt(&key, &nonce, &ciphertext)?;
    Ok((phrase, key))
}

fn open_with_key(payload: &str, key: &[u8; KEY_LEN]) -> Result<String, String> {
    let (_salt, nonce, ciphertext, _iterations) = parse_payload(payload)?;
    decrypt(key, &nonce, &ciphertext)
}

fn require_password(password: &str) -> Result<(), String> {
    if password.is_empty() {
        return Err("password is required".to_string());
    }
    if password.len() > 1024 {
        return Err("password is too long".to_string());
    }
    Ok(())
}

fn derive_key(password: &str, salt: &[u8], iterations: u32) -> Result<[u8; KEY_LEN], String> {
    if !(MIN_KDF_ITERATIONS..=MAX_KDF_ITERATIONS).contains(&iterations) {
        return Err("wallet data is invalid".to_string());
    }
    let mut key = [0u8; KEY_LEN];
    pbkdf2_hmac::<Sha256>(password.as_bytes(), salt, iterations, &mut key);
    Ok(key)
}

fn encrypt(
    key: &[u8; KEY_LEN],
    nonce: &[u8; NONCE_LEN],
    plaintext: &[u8],
) -> Result<Vec<u8>, String> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| "encryption failed".to_string())?;
    // aes-gcm 0.10 still builds nonces through generic-array 0.14's deprecated helper.
    #[allow(deprecated)]
    let nonce = Nonce::from_slice(nonce);
    cipher
        .encrypt(nonce, plaintext)
        .map_err(|_| "encryption failed".to_string())
}

fn decrypt(
    key: &[u8; KEY_LEN],
    nonce: &[u8; NONCE_LEN],
    ciphertext: &[u8],
) -> Result<String, String> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| "incorrect password".to_string())?;
    #[allow(deprecated)]
    let nonce = Nonce::from_slice(nonce);
    let plain = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| "incorrect password".to_string())?;
    String::from_utf8(plain).map_err(|_| "incorrect password".to_string())
}

type SealedParts = ([u8; SALT_LEN], [u8; NONCE_LEN], Vec<u8>, u32);

fn parse_payload(payload: &str) -> Result<SealedParts, String> {
    if payload.len() > 100_000 {
        return Err("wallet data is invalid".to_string());
    }
    let value: serde_json::Value =
        serde_json::from_str(payload).map_err(|_| "wallet data is invalid".to_string())?;
    if value.get("v").and_then(|v| v.as_u64()) != Some(1) {
        return Err("wallet data is invalid".to_string());
    }
    if value.get("kdf").and_then(|v| v.as_str()) != Some("pbkdf2-sha256") {
        return Err("wallet data is invalid".to_string());
    }
    let iterations = value
        .get("iterations")
        .and_then(|v| v.as_u64())
        .and_then(|v| u32::try_from(v).ok())
        .ok_or_else(|| "wallet data is invalid".to_string())?;
    let salt = decode_fixed::<SALT_LEN>(field(&value, "salt")?)?;
    let nonce = decode_fixed::<NONCE_LEN>(field(&value, "nonce")?)?;
    let ciphertext = STANDARD
        .decode(field(&value, "ciphertext")?)
        .map_err(|_| "wallet data is invalid".to_string())?;
    if ciphertext.is_empty() {
        return Err("wallet data is invalid".to_string());
    }
    Ok((salt, nonce, ciphertext, iterations))
}

fn field<'a>(value: &'a serde_json::Value, name: &str) -> Result<&'a str, String> {
    value
        .get(name)
        .and_then(|item| item.as_str())
        .ok_or_else(|| "wallet data is invalid".to_string())
}

fn decode_fixed<const N: usize>(text: &str) -> Result<[u8; N], String> {
    let bytes = STANDARD
        .decode(text)
        .map_err(|_| "wallet data is invalid".to_string())?;
    let array: [u8; N] = bytes
        .try_into()
        .map_err(|_| "wallet data is invalid".to_string())?;
    Ok(array)
}

fn decode_key(text: &str) -> Result<[u8; KEY_LEN], String> {
    decode_fixed::<KEY_LEN>(text).map_err(|_| "incorrect password".to_string())
}

#[cfg(test)]
mod tests {
    use super::{open_mnemonic, open_with_wrapping_key, seal_mnemonic, wrapping_key};

    const PHRASE: &str = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

    #[test]
    fn seal_round_trips_and_hides_the_phrase() {
        let sealed =
            seal_mnemonic(PHRASE.to_string(), "correct horse battery".to_string()).unwrap();
        assert!(!sealed.contains("abandon"));
        assert!(!sealed.contains("correct horse"));
        assert!(sealed.contains("pbkdf2-sha256"));
        let opened = open_mnemonic(sealed.clone(), "correct horse battery".to_string()).unwrap();
        assert_eq!(opened, PHRASE);
        let error = open_mnemonic(sealed.clone(), "nope".to_string()).unwrap_err();
        assert_eq!(error, "incorrect password");
        assert!(!error.contains("abandon"));

        let key = wrapping_key(sealed.clone(), "correct horse battery".to_string()).unwrap();
        assert!(!key.contains("abandon"));
        assert_eq!(open_with_wrapping_key(sealed, key).unwrap(), PHRASE);
        assert!(open_with_wrapping_key("{}".to_string(), "aaaa".to_string()).is_err());
        assert!(seal_mnemonic(PHRASE.to_string(), String::new()).is_err());
    }
}
