import 'package:cofinex_wallet/src/sepolia_rpc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed URL wins over the define, the environment, and the default', () {
    expect(
      resolveSepoliaRpcUrl(
        ' https://rpc.example/sepolia ',
        environmentUrl: 'https://from-env.example',
        defineUrl: 'https://from-define.example',
      ),
      'https://rpc.example/sepolia',
    );
  });

  test('dart-define wins over the desktop environment', () {
    expect(
      resolveSepoliaRpcUrl(
        ' ',
        environmentUrl: 'https://from-env.example',
        defineUrl: 'https://from-define.example',
      ),
      'https://from-define.example',
    );
  });

  test('desktop environment is used when the field and define are empty', () {
    expect(
      resolveSepoliaRpcUrl('  ', environmentUrl: ' https://from-env.example '),
      'https://from-env.example',
    );
  });

  test(
    'mobile ignores the process environment and uses the public endpoint',
    () {
      expect(
        resolveSepoliaRpcUrl(
          '',
          environmentUrl: 'https://from-env.example',
          allowEnvironment: false,
        ),
        defaultSepoliaRpcUrl,
      );
    },
  );
}
