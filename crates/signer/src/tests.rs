use cofinex_keys::{Curve, DerivationPath};

use crate::{LocalSigner, MpcSigner, SignRequest, Signer};

const ABANDON: &str =
    "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

#[test]
fn local_signer_debug_redacts_the_mnemonic_and_the_ethereum_key() {
    let signer = LocalSigner::from_mnemonic(ABANDON, "").unwrap();
    let debug = format!("{signer:?}");
    assert_eq!(debug, "LocalSigner([redacted])");
    assert!(!debug.contains("abandon"));
    assert!(!debug.contains("1ab42cc4"));
}

#[test]
fn mpc_stub_refuses_to_sign_for_both_curves() {
    let signer = MpcSigner::two_of_three();
    assert_eq!(signer.threshold(), 2);
    assert_eq!(signer.parties(), 3);
    let secp = DerivationPath::bip44(Curve::Secp256k1, 60, 0, 0, 0).unwrap();
    let ed = DerivationPath::solana_account(0).unwrap();
    for path in [&secp, &ed] {
        let error = signer.public_key(path).unwrap_err();
        assert!(error.to_string().contains("does not implement public_key"));
        let error = signer
            .sign(&SignRequest {
                path,
                message: b"payload",
                prehashed: false,
            })
            .unwrap_err();
        assert!(error.to_string().contains("does not implement sign"));
    }
}

#[test]
fn both_backends_satisfy_the_same_trait() {
    fn backend<S: Signer>(signer: &S) -> &'static str {
        signer.backend_name()
    }
    let (local, phrase) = LocalSigner::generate(12).unwrap();
    assert_eq!(phrase.split_whitespace().count(), 12);
    assert_eq!(backend(&local), "local");
    assert_eq!(backend(&MpcSigner::two_of_three()), "mpc");
    let debug = format!("{local:?}");
    assert!(!debug.contains(&phrase));
}
