#!/usr/bin/env bash
# 编出带插件的 librime（iOS XCFramework），打包成 Frameworks.tgz，给 scripts/fetch-rime.sh 下载用。
# 基于 LibrimeKit-iOS v0.2.2 的构建脚本（librime 1.16.1 + librime-lua），再加两个插件：
#   librime-octagram：语言模型，整句首选更准（配万象 gram 模型）
#   librime-predict：上屏后的联想
# 两个插件都是 BSD 许可。只能在 macOS 上跑，冷启动大约 1 小时（Boost 最慢），平时由 .github/workflows/librime.yml 在 GitHub 上跑。
# 用法：bash scripts/build-librime.sh [输出目录]，默认 build/librime，产物是 <输出目录>/Frameworks.tgz。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/librime}"

KIT_REF="5611777f19afa9a431eea8909dde9e88e1d72d0d"      # LibrimeKit-iOS v0.2.2
OCTAGRAM_REF="57d18b9f58e5284bd891d559f6bdd16cf60341e9"
PREDICT_REF="920bd41ebf6f9bf6855d14fbe80212e54e749791"

KIT="$OUT/LibrimeKit-iOS"
rm -rf "$KIT"
mkdir -p "$OUT"
git init -q "$KIT"
git -C "$KIT" fetch -q --depth 1 https://github.com/thomfang/LibrimeKit-iOS.git "$KIT_REF"
git -C "$KIT" -c advice.detachedHead=false checkout -q FETCH_HEAD
git -C "$KIT" submodule update --init --recursive deps/librime deps/boost-iosx

PLUGINS="$KIT/deps/librime/plugins"
add_plugin() {
  local name="$1" url="$2" ref="$3"
  git init -q "$PLUGINS/$name"
  git -C "$PLUGINS/$name" fetch -q --depth 1 "$url" "$ref"
  git -C "$PLUGINS/$name" -c advice.detachedHead=false checkout -q FETCH_HEAD
  # 插件自带的命令行工具交叉编译到 iOS 用不上，关掉。
  sed -i '' 's/option(BUILD_TOOLS "Build tools" ON)/option(BUILD_TOOLS "Build tools" OFF)/' "$PLUGINS/$name/CMakeLists.txt"
}
add_plugin octagram https://github.com/lotem/librime-octagram.git "$OCTAGRAM_REF"
add_plugin predict https://github.com/rime/librime-predict.git "$PREDICT_REF"

# 静态库里插件模块的构造函数没人引用会被链接器丢掉（LibrimeKit 对 lua 也是这么处理的）：
# 在 rime_declare_module_dependencies() 里显式引用这两个模块。
RIME_API="$KIT/deps/librime/src/rime_api.cc"
awk '
  /^  rime_require_module_levers\(\);[[:space:]]*$/ {
    print
    print "  // Enclave: force-link octagram, predict"
    print "  extern void rime_require_module_octagram();"
    print "  rime_require_module_octagram();"
    print "  extern void rime_require_module_predict();"
    print "  rime_require_module_predict();"
    next
  }
  { print }
' "$RIME_API" > "$RIME_API.tmp" && mv "$RIME_API.tmp" "$RIME_API"
grep -q "rime_require_module_octagram();" "$RIME_API"

make -C "$KIT" build
(cd "$KIT/Frameworks" && tar -czf "$OUT/Frameworks.tgz" *.xcframework)
shasum -a 256 "$OUT/Frameworks.tgz"
