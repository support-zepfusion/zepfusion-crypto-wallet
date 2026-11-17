-- USDT as one canonical asset. Addresses and the decision to omit a chain
-- come from Tether's published list, retrieved 2026-11-17:
-- https://tether.to/supported-protocols/
-- (Gatsby page data for that URL; the HTML shell is client-rendered.)
-- Decimals are not printed on that page. Each row's decimals were read from
-- the chain itself and cross-checked against the explorer named below.
-- No testnet USD₮ deployment is published on that page, so none is inserted.
-- A testnet row would also be excluded from unified_asset_deployments.
--
-- Omitted rather than invented:
-- * BNB Smart Chain. The page lists the chain, but the only contract in that
--   section is XAU₮ (https://bscscan.com/token/0x21cAef8A43163Eea865baeE23b9C2E327696A3bf),
--   not USD₮. The BEP-20 token named USDT is Binance-Peg. An eth_call against
--   0x55d398326f99059fF775485246999027B3197955 on chain id 56 (0x38) returned
--   name "Tether USD", symbol "USDT", decimals 18. That address is not on
--   Tether's USD₮ list, so it is not inserted.
-- * Polygon. The page does not list Polygon. An eth_call against
--   0xc2132D05D31c914a87C6611C10748AEb04B58e8F on chain id 137 (0x89) returned
--   name "USDT0", symbol "USDT0", decimals 6. Not inserted.
-- * Ethereum Sepolia, BSC testnet, Polygon Amoy, TRON Nile/Shasta, and Solana
--   devnet. No official testnet contract is on the Tether page.

INSERT INTO assets (id, symbol, name, issuer, parent_asset_id) VALUES
    ('tether:usdt', 'USDT', 'Tether USD', 'Tether', NULL)
ON CONFLICT (id) DO NOTHING;

-- Ethereum ERC-20 USD₮. 6 decimals from decimals() via eth_call on chain id 1,
-- and the Etherscan token page titles it Tether USD (USDT).
-- https://tether.to/supported-protocols/
-- https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7
INSERT INTO token_deployments (
    asset_id, chain_id, standard, contract_address, address_key, decimals,
    classification, verification_status, deployment_status, verification_source,
    include_in_unified_balance
) VALUES (
    'tether:usdt', 'ethereum', 'erc20',
    '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    '0xdac17f958d2ee523a2206206994597c13d831ec7',
    6, 'issuer-native', 'approved', 'active',
    'https://tether.to/supported-protocols/ ; https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7',
    TRUE
)
ON CONFLICT (chain_id, address_key) WHERE address_key IS NOT NULL DO NOTHING;

-- TRON TRC-20 USD₮. 6 decimals from decimals() on TronGrid and from Tronscan
-- (name "Tether USD", symbol "USDT", precision 6, contract matches).
-- https://tether.to/supported-protocols/
-- https://tronscan.org/#/token20/TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
INSERT INTO token_deployments (
    asset_id, chain_id, standard, contract_address, address_key, decimals,
    classification, verification_status, deployment_status, verification_source,
    include_in_unified_balance
) VALUES (
    'tether:usdt', 'tron', 'trc20',
    'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    6, 'issuer-native', 'approved', 'active',
    'https://tether.to/supported-protocols/ ; https://tronscan.org/#/token20/TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    TRUE
)
ON CONFLICT (chain_id, address_key) WHERE address_key IS NOT NULL DO NOTHING;

-- Solana SPL USD₮. Tether publishes the mint. The Solana RPC getAccountInfo
-- (jsonParsed) reports decimals 6 and the SPL Token program as owner.
-- getAsset metadata on the same RPC is name "USDT", symbol "USDT".
-- solscan (https://solscan.io/token/Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB)
-- returned HTTP 403 from the environment that checked these addresses, so the
-- chain RPC plus Tether's explorer link is the cross-check that landed.
-- https://tether.to/supported-protocols/
-- https://explorer.solana.com/address/Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB
INSERT INTO token_deployments (
    asset_id, chain_id, standard, contract_address, address_key, decimals,
    classification, verification_status, deployment_status, verification_source,
    include_in_unified_balance
) VALUES (
    'tether:usdt', 'solana', 'spl',
    'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
    'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
    6, 'issuer-native', 'approved', 'active',
    'https://tether.to/supported-protocols/ ; https://explorer.solana.com/address/Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
    TRUE
)
ON CONFLICT (chain_id, address_key) WHERE address_key IS NOT NULL DO NOTHING;
