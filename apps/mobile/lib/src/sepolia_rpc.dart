/// Public Sepolia endpoint used when nothing else is configured.
const defaultSepoliaRpcUrl = 'https://ethereum-sepolia-rpc.publicnode.com';

/// Value of `--dart-define=COFINEX_SEPOLIA_RPC_URL=...`. Empty when omitted.
const sepoliaRpcFromDefine = String.fromEnvironment('COFINEX_SEPOLIA_RPC_URL');

/// URL passed to the Rust Sepolia adapter.
///
/// The text field wins. Then the dart-define, then the desktop process
/// environment when [allowEnvironment] is true, then [defaultSepoliaRpcUrl].
/// Android and iOS leave [allowEnvironment] false because `Platform.environment`
/// is unavailable there.
String resolveSepoliaRpcUrl(
  String field, {
  String? environmentUrl,
  bool allowEnvironment = true,
  String defineUrl = sepoliaRpcFromDefine,
}) {
  final typed = field.trim();
  if (typed.isNotEmpty) {
    return typed;
  }
  final defined = defineUrl.trim();
  if (defined.isNotEmpty) {
    return defined;
  }
  if (allowEnvironment) {
    final fromEnv = environmentUrl?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
  }
  return defaultSepoliaRpcUrl;
}
