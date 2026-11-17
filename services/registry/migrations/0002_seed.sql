-- Seed data. Contract addresses below are copied from Circle's published USDC
-- list, retrieved 2026-11-17:
-- https://developers.circle.com/stablecoins/usdc-contract-addresses
-- No other contract or mint address is inserted. Native gas tokens have no
-- contract. Testnet USDC is a separate asset and is excluded from the
-- unified view: Circle documents those tokens as having no financial value.
--
-- Decimals for Circle USDC on these networks are 6.
-- Native decimals and SLIP-44 coin types:
--   BTC 8, coin type 0 (BIP-44)
--   ETH 18, coin type 60; chain ids 1 and 11155111 (EIP-155, ethereum-lists/chains)
--   TRX 6, coin type 195
--   SOL 9 (lamports), coin type 501
--   SUI 9 (mist), coin type 784
--   BNB 18, chain id 56; POL 18, chain id 137
-- Solana CAIP-2 genesis hashes follow the solana namespace in CAIP-2.

INSERT INTO chains (
    id, family, name, caip2, slip44_coin_type, curve, is_testnet, native_symbol, native_decimals
) VALUES
    ('bitcoin', 'bitcoin', 'Bitcoin', 'bip122:000000000019d6689c085ae165831e93', 0, 'secp256k1', FALSE, 'BTC', 8),
    ('ethereum', 'evm', 'Ethereum', 'eip155:1', 60, 'secp256k1', FALSE, 'ETH', 18),
    ('ethereum-sepolia', 'evm', 'Ethereum Sepolia', 'eip155:11155111', 60, 'secp256k1', TRUE, 'ETH', 18),
    ('tron', 'tron', 'TRON', NULL, 195, 'secp256k1', FALSE, 'TRX', 6),
    ('solana', 'solana', 'Solana', 'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp', 501, 'ed25519', FALSE, 'SOL', 9),
    ('solana-devnet', 'solana', 'Solana Devnet', 'solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1', 501, 'ed25519', TRUE, 'SOL', 9),
    ('sui', 'sui', 'Sui', NULL, 784, 'ed25519', FALSE, 'SUI', 9),
    ('sui-testnet', 'sui', 'Sui Testnet', NULL, 784, 'ed25519', TRUE, 'SUI', 9),
    ('bsc', 'evm', 'BNB Smart Chain', 'eip155:56', 60, 'secp256k1', FALSE, 'BNB', 18),
    ('polygon', 'evm', 'Polygon PoS', 'eip155:137', 60, 'secp256k1', FALSE, 'POL', 18)
ON CONFLICT (id) DO NOTHING;

INSERT INTO assets (id, symbol, name, issuer, parent_asset_id) VALUES
    ('bitcoin:btc', 'BTC', 'Bitcoin', NULL, NULL),
    ('ethereum:eth', 'ETH', 'Ether', NULL, NULL),
    ('ethereum:sepolia-eth', 'ETH', 'Sepolia Ether', NULL, 'ethereum:eth'),
    ('tron:trx', 'TRX', 'TRON', NULL, NULL),
    ('solana:sol', 'SOL', 'Solana', NULL, NULL),
    ('solana:devnet-sol', 'SOL', 'Solana Devnet', NULL, 'solana:sol'),
    ('sui:sui', 'SUI', 'Sui', NULL, NULL),
    ('sui:testnet-sui', 'SUI', 'Sui Testnet', NULL, 'sui:sui'),
    ('bsc:bnb', 'BNB', 'BNB', NULL, NULL),
    ('polygon:pol', 'POL', 'Polygon Ecosystem Token', NULL, NULL),
    ('circle:usdc', 'USDC', 'USD Coin', 'Circle', NULL),
    ('circle:usdc-testnet', 'USDC', 'USD Coin (testnet)', 'Circle', 'circle:usdc')
ON CONFLICT (id) DO NOTHING;

INSERT INTO token_deployments (
    asset_id, chain_id, standard, contract_address, address_key, decimals,
    classification, verification_status, deployment_status, verification_source,
    include_in_unified_balance
) VALUES
    ('bitcoin:btc', 'bitcoin', 'native', NULL, NULL, 8, 'native', 'approved', 'active',
        'Native protocol asset. No contract. BIP-44 coin type 0; 8 decimal places.', TRUE),
    ('ethereum:eth', 'ethereum', 'native', NULL, NULL, 18, 'native', 'approved', 'active',
        'Native protocol asset. No contract. EIP-155 chain id 1; 18 decimal places.', TRUE),
    ('ethereum:sepolia-eth', 'ethereum-sepolia', 'native', NULL, NULL, 18, 'native', 'approved', 'active',
        'Native testnet asset. No contract. EIP-155 chain id 11155111. Not redeemable for mainnet ETH.', FALSE),
    ('tron:trx', 'tron', 'native', NULL, NULL, 6, 'native', 'approved', 'active',
        'Native protocol asset. No contract. SLIP-44 coin type 195; 6 decimal places.', TRUE),
    ('solana:sol', 'solana', 'native', NULL, NULL, 9, 'native', 'approved', 'active',
        'Native protocol asset. No mint. SLIP-44 coin type 501; 9 decimal places (lamports).', TRUE),
    ('solana:devnet-sol', 'solana-devnet', 'native', NULL, NULL, 9, 'native', 'approved', 'active',
        'Native testnet asset. No mint. Not the same asset as mainnet SOL.', FALSE),
    ('sui:sui', 'sui', 'native', NULL, NULL, 9, 'native', 'approved', 'active',
        'Native protocol asset. No coin type address. SLIP-44 coin type 784; 9 decimal places (mist).', TRUE),
    ('sui:testnet-sui', 'sui-testnet', 'native', NULL, NULL, 9, 'native', 'approved', 'active',
        'Native testnet asset. Not the same asset as mainnet SUI.', FALSE),
    ('bsc:bnb', 'bsc', 'native', NULL, NULL, 18, 'native', 'approved', 'active',
        'Native protocol asset. No contract. EIP-155 chain id 56; 18 decimal places.', TRUE),
    ('polygon:pol', 'polygon', 'native', NULL, NULL, 18, 'native', 'approved', 'active',
        'Native protocol asset. No contract. EIP-155 chain id 137; 18 decimal places. Symbol POL.', TRUE)
ON CONFLICT (chain_id) WHERE standard = 'native' DO NOTHING;

-- Circle-issued USDC. Addresses are the checksummed or base58 form from
-- https://developers.circle.com/stablecoins/usdc-contract-addresses
-- address_key is lowercase for EVM and exact for Solana and Sui.
INSERT INTO token_deployments (
    asset_id, chain_id, standard, contract_address, address_key, decimals,
    classification, verification_status, deployment_status, verification_source,
    include_in_unified_balance
) VALUES
    (
        'circle:usdc', 'ethereum', 'erc20',
        '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
        6, 'issuer-native', 'approved', 'active',
        'https://developers.circle.com/stablecoins/usdc-contract-addresses',
        TRUE
    ),
    (
        'circle:usdc', 'polygon', 'erc20',
        '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
        '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359',
        6, 'issuer-native', 'approved', 'active',
        'https://developers.circle.com/stablecoins/usdc-contract-addresses',
        TRUE
    ),
    (
        'circle:usdc', 'solana', 'spl',
        'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
        'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
        6, 'issuer-native', 'approved', 'active',
        'https://developers.circle.com/stablecoins/usdc-contract-addresses',
        TRUE
    ),
    (
        'circle:usdc', 'sui', 'sui_coin',
        '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC',
        '0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC',
        6, 'issuer-native', 'approved', 'active',
        'https://developers.circle.com/stablecoins/usdc-contract-addresses',
        TRUE
    ),
    (
        'circle:usdc-testnet', 'ethereum-sepolia', 'erc20',
        '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
        '0x1c7d4b196cb0c7b01d743fbc6116a902379c7238',
        6, 'issuer-native', 'approved', 'active',
        'https://developers.circle.com/stablecoins/usdc-contract-addresses',
        FALSE
    ),
    (
        'circle:usdc-testnet', 'solana-devnet', 'spl',
        '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
        '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
        6, 'issuer-native', 'approved', 'active',
        'https://developers.circle.com/stablecoins/usdc-contract-addresses',
        FALSE
    ),
    (
        'circle:usdc-testnet', 'sui-testnet', 'sui_coin',
        '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC',
        '0xa1ec7fc00a6f40db9693ad1415d0c193ad3906494428cf252621037bd7117e29::usdc::USDC',
        6, 'issuer-native', 'approved', 'active',
        'https://developers.circle.com/stablecoins/usdc-contract-addresses',
        FALSE
    )
ON CONFLICT (chain_id, address_key) WHERE address_key IS NOT NULL DO NOTHING;
