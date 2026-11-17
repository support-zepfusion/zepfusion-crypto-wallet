//! Flutter-facing functions. The mnemonic crosses this boundary only so the
//! screen can show it once. These functions do not log it. `CreatedWallet`'s
//! `Debug` impl redacts the phrase.

pub mod wallet;

pub use wallet::{
    create_test_wallet, import_test_wallet, sepolia_balance, BalanceView, CreatedWallet,
    ImportedWallet,
};
