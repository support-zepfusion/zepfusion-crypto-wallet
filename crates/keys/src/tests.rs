use crate::derive::{secp_private_hex, secp_xprv};
use crate::slip10::Slip10Node;
use crate::{generate_mnemonic, public_key, sign_with_seed, Curve, DerivationPath, Seed};

const ABANDON: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

#[test]
fn bip39_abandon_seed_matches_the_spec() {
    let seed = Seed::from_mnemonic(ABANDON, "").unwrap();
    assert_eq!(
        hex::encode(seed.as_bytes()),
        "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1\
         9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"
    );
    let debug = format!("{seed:?}");
    assert_eq!(debug, "Seed([redacted])");
    assert!(!debug.contains("abandon"));
    assert!(!debug.contains("5eb00b"));
}

#[test]
fn bip39_passphrase_trezor_matches_the_spec() {
    let seed = Seed::from_mnemonic(ABANDON, "TREZOR").unwrap();
    assert_eq!(
        hex::encode(seed.as_bytes()),
        "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553\
         1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
    );
}

#[test]
fn invalid_mnemonic_error_does_not_echo_the_phrase() {
    let phrase = "this is not a valid mnemonic phrase at all";
    let error = Seed::from_mnemonic(phrase, "").unwrap_err();
    let text = error.to_string();
    assert_eq!(text, "invalid mnemonic");
    assert!(!text.contains("mnemonic phrase"));
    assert!(!text.contains("this is not"));
}

#[test]
fn bip32_vector_1_master_and_first_hardened_child() {
    let seed = hex::decode("000102030405060708090a0b0c0d0e0f").unwrap();
    let master = secp_xprv(&seed, "m").unwrap();
    assert_eq!(
        master.as_str(),
        "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvN\
         KmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"
    );
    let child = secp_xprv(&seed, "m/0'").unwrap();
    assert_eq!(
        child.as_str(),
        "xprv9uHRZZhk6KAJC1avXpDAp4MDc3sQKNxDiPvvkX8Br5ngLNv1TxvUxt4cV1rGL5\
         hj6KCesnDYUhd7oWgT11eZG7XnxHrnYeSvkzY7d2bhkJ7"
    );
}

#[test]
fn bip44_ethereum_address_from_abandon_mnemonic() {
    let seed = Seed::from_mnemonic(ABANDON, "").unwrap();
    let path = DerivationPath::bip44(Curve::Secp256k1, 60, 0, 0, 0).unwrap();
    assert_eq!(path.to_string(), "m/44'/60'/0'/0/0");
    let private_hex = secp_private_hex(&seed, &path).unwrap();
    assert_eq!(
        private_hex,
        "1ab42cc412b618bdea3a599e3c9bae199ebf030895b039e9db1e30dafb12b727"
    );
    let public = public_key(&seed, &path).unwrap();
    assert_eq!(public.curve(), Curve::Secp256k1);
    assert_eq!(public.as_bytes().len(), 65);
    assert_eq!(public.as_bytes()[0], 0x04);
    // Address check lives next to the EVM adapter. The uncompressed key is
    // hashed here only to lock the encoding the adapter consumes.
    let hash = {
        use sha3::{Digest, Keccak256};
        Keccak256::digest(&public.as_bytes()[1..])
    };
    let address = hex::encode(&hash[12..]);
    assert_eq!(address, "9858effd232b4033e47d90003d41ec34ecaeda94");
}

#[test]
fn slip10_ed25519_vector_1() {
    let seed = hex::decode("000102030405060708090a0b0c0d0e0f").unwrap();
    let master = Slip10Node::master(&seed);
    assert_eq!(
        hex::encode(master.key),
        "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7"
    );
    let child = master
        .derive_child(crate::PathSegment::new(0, true).unwrap())
        .unwrap();
    assert_eq!(
        hex::encode(child.key),
        "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3"
    );

    // SLIP-0010 prefixes the 32-byte Edwards point with 0x00 in its vectors.
    let signing = ed25519_dalek::SigningKey::from_bytes(&master.key);
    let public = signing.verifying_key().to_bytes();
    assert_eq!(
        hex::encode(public),
        "a4b2856bfec510abab89753fac1ac0e1112364e7d250545963f135f2a33188ed"
    );
}

#[test]
fn slip10_rejects_a_non_hardened_segment() {
    let error = DerivationPath::bip44(Curve::Ed25519, 501, 0, 0, 0);
    // bip44 hardens the tail for ed25519, so this one succeeds.
    assert!(error.is_ok());
    let mut segments = error.unwrap().segments().to_vec();
    segments[4].hardened = false;
    let error = DerivationPath::new(Curve::Ed25519, segments).unwrap_err();
    assert_eq!(error, crate::KeyError::Ed25519HardenedOnly);
}

#[test]
fn ed25519_signs_the_raw_message_and_secp_requires_a_digest() {
    let seed = Seed::from_mnemonic(ABANDON, "").unwrap();
    let ed_path = DerivationPath::solana_account(0).unwrap();
    let signature = sign_with_seed(&seed, &ed_path, b"cofinex", false).unwrap();
    assert_eq!(signature.as_bytes().len(), 64);
    assert!(sign_with_seed(&seed, &ed_path, &[0u8; 32], true).is_err());

    let secp_path = DerivationPath::bip44(Curve::Secp256k1, 60, 0, 0, 0).unwrap();
    let signature = sign_with_seed(&seed, &secp_path, &[0x11; 32], true).unwrap();
    assert_eq!(signature.as_bytes().len(), 65);
    assert!(signature.as_bytes()[64] <= 1);
    assert!(sign_with_seed(&seed, &secp_path, b"not a digest", false).is_err());
}

#[test]
fn generated_mnemonic_has_twelve_words_and_is_not_in_debug() {
    let (phrase, seed) = generate_mnemonic(12).unwrap();
    assert_eq!(phrase.split_whitespace().count(), 12);
    let debug = format!("{seed:?}");
    assert!(!debug.contains(&phrase));
    assert!(Seed::from_mnemonic(&phrase, "").is_ok());
    assert!(generate_mnemonic(13).is_err());
}
