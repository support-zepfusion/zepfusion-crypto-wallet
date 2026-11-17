-- Fails the session if the seed violates the aggregation rule or drops a
-- cited USDC deployment.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM unified_asset_deployments AS u
        JOIN chains AS c ON c.id = u.chain_id
        WHERE c.is_testnet
    ) THEN
        RAISE EXCEPTION 'testnet deployment leaked into unified_asset_deployments';
    END IF;

    IF (
        SELECT count(*) FROM unified_asset_deployments WHERE asset_id = 'circle:usdc'
    ) <> 4 THEN
        RAISE EXCEPTION 'circle:usdc should have 4 mainnet deployments';
    END IF;

    IF EXISTS (
        SELECT 1 FROM unified_asset_deployments WHERE asset_id = 'circle:usdc-testnet'
    ) THEN
        RAISE EXCEPTION 'testnet USDC must not be in the unified view';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM token_deployments
        WHERE chain_id = 'ethereum-sepolia'
          AND contract_address = '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238'
          AND include_in_unified_balance = FALSE
    ) THEN
        RAISE EXCEPTION 'missing cited Sepolia USDC deployment';
    END IF;
END $$;
