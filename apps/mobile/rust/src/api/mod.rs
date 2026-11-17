//! Flutter-facing functions. The mnemonic crosses this boundary only so the
//! screen can show it once. These functions do not log it. `CreatedWallet`'s
//! `Debug` impl redacts the phrase.

pub mod vault;
pub mod wallet;

pub use vault::{open_mnemonic, open_with_wrapping_key, seal_mnemonic, wrapping_key};
pub use wallet::{
    create_test_wallet, import_test_wallet, quote_sepolia_transfer, send_sepolia_eth,
    sepolia_balance, BalanceView, CreatedWallet, FeeQuote, ImportedWallet, SendReceipt,
};
