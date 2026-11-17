Pod::Spec.new do |s|
  s.name             = 'rust_lib_cofinex_wallet'
  s.version          = '0.0.1'
  s.summary          = 'Cofinex wallet Rust bridge.'
  s.description      = 'Builds libcofinex_wallet_bridge and links it into the iOS app.'
  s.homepage         = 'https://github.com/support-zepfusion/zepfusion-crypto-wallet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cofinex' => 'https://github.com/support-zepfusion/zepfusion-crypto-wallet' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust cofinex_wallet_bridge',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/libcofinex_wallet_bridge.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libcofinex_wallet_bridge.a',
  }
end
