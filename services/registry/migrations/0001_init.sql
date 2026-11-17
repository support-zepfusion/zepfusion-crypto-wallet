-- Cofinex Token Registry schema.
-- ADR-001 section 2: PostgreSQL, one canonical asset, many chain deployments,
-- unique (chain, address). The HTTP API and Redis cache are not part of this
-- scaffold; see docs/ROADMAP.md.
--
-- Aggregation rule, enforced by the view at the bottom:
-- a unified balance may include a deployment only when the chain is not a
-- testnet, the deployment is approved and active, and
-- include_in_unified_balance is true. Testnet USDC uses its own asset id so
-- a join on asset_id cannot add it to mainnet USDC.

CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE chains (
    id TEXT PRIMARY KEY,
    family TEXT NOT NULL CHECK (family IN ('bitcoin', 'evm', 'tron', 'solana', 'sui')),
    name TEXT NOT NULL,
    -- CAIP-2 when the namespace is settled. Null when this scaffold does not
    -- want to invent an identifier (TRON, Sui).
    caip2 TEXT UNIQUE,
    slip44_coin_type INTEGER CHECK (slip44_coin_type IS NULL OR slip44_coin_type >= 0),
    curve TEXT NOT NULL CHECK (curve IN ('secp256k1', 'ed25519')),
    is_testnet BOOLEAN NOT NULL,
    native_symbol TEXT NOT NULL,
    native_decimals INTEGER NOT NULL CHECK (native_decimals >= 0 AND native_decimals <= 36),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE assets (
    id TEXT PRIMARY KEY,
    symbol TEXT NOT NULL,
    name TEXT NOT NULL,
    issuer TEXT,
    -- Points at the mainnet asset a testnet token corresponds to.
    -- Portfolio code must not sum balances across this link.
    parent_asset_id TEXT REFERENCES assets (id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (parent_asset_id IS NULL OR parent_asset_id <> id)
);

CREATE TABLE token_deployments (
    id BIGSERIAL PRIMARY KEY,
    asset_id TEXT NOT NULL REFERENCES assets (id),
    chain_id TEXT NOT NULL REFERENCES chains (id),
    standard TEXT NOT NULL CHECK (standard IN ('native', 'erc20', 'trc20', 'spl', 'sui_coin')),
    -- Display form as published by the issuer. Null only for native assets.
    contract_address TEXT,
    -- Uniqueness key. EVM: lowercase 0x address. Solana and Sui: the exact
    -- published string (those encodings are case-sensitive, so they are not
    -- lowercased). Null only for native assets.
    address_key TEXT,
    decimals INTEGER NOT NULL CHECK (decimals >= 0 AND decimals <= 36),
    classification TEXT NOT NULL CHECK (
        classification IN ('native', 'issuer-native', 'wrapped', 'bridged')
    ),
    verification_status TEXT NOT NULL CHECK (
        verification_status IN ('approved', 'pending', 'rejected')
    ),
    deployment_status TEXT NOT NULL CHECK (
        deployment_status IN ('active', 'deprecated', 'suspended')
    ),
    verification_source TEXT NOT NULL,
    include_in_unified_balance BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (
        (
            standard = 'native'
            AND contract_address IS NULL
            AND address_key IS NULL
            AND classification = 'native'
        )
        OR (
            standard <> 'native'
            AND contract_address IS NOT NULL
            AND address_key IS NOT NULL
            AND length(contract_address) > 0
            AND length(address_key) > 0
        )
    ),
    CHECK (verification_status <> 'approved' OR length(verification_source) > 0),
    CHECK (NOT include_in_unified_balance OR verification_status = 'approved'),
    CHECK (
        chain_id NOT IN ('ethereum', 'ethereum-sepolia', 'bsc', 'polygon')
        OR standard = 'native'
        OR contract_address ~ '^0x[0-9a-fA-F]{40}$'
    )
);

-- ADR-001: unique (chain, address). Native rows have a null address, and
-- Postgres treats nulls as distinct, so natives have their own index.
CREATE UNIQUE INDEX token_deployments_chain_address_uidx
    ON token_deployments (chain_id, address_key)
    WHERE address_key IS NOT NULL;

CREATE UNIQUE INDEX token_deployments_one_native_per_chain
    ON token_deployments (chain_id)
    WHERE standard = 'native';

CREATE INDEX token_deployments_asset_idx ON token_deployments (asset_id);

CREATE VIEW unified_asset_deployments AS
SELECT
    a.id AS asset_id,
    a.symbol,
    a.name,
    a.issuer,
    d.chain_id,
    c.name AS chain_name,
    c.caip2,
    d.standard,
    d.contract_address,
    d.decimals,
    d.classification,
    d.verification_source
FROM token_deployments AS d
JOIN assets AS a ON a.id = d.asset_id
JOIN chains AS c ON c.id = d.chain_id
WHERE d.verification_status = 'approved'
  AND d.deployment_status = 'active'
  AND d.include_in_unified_balance
  AND NOT c.is_testnet;
