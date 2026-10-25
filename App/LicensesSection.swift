import SwiftUI

/// 「关于」页里的开源组件和数据，以及它们的许可证。
struct LicensesSection: View {
    private struct Component: Identifiable {
        let name: String
        let license: String
        let note: String?
        let url: String
        var id: String { name }
    }

    private let components = [
        Component(name: "万象拼音", license: "CC BY 4.0",
                  note: L("拼音词库和英文词表。Enclave 去掉了拼音声调，并按词频删减了部分词条。", "Pinyin dictionary and English word list. Enclave removed tone marks and trimmed entries by frequency.", "ピンイン辞書と英単語リスト。Enclave では声調を除き、頻度に応じて一部の語を削っています。"),
                  url: "https://github.com/amzxyz/rime_wanxiang"),
        Component(name: "librime", license: "BSD 3-Clause", note: L("拼音输入引擎", "Pinyin input engine", "ピンイン入力エンジン"), url: "https://github.com/rime/librime"),
        Component(name: "librime-lua", license: "BSD 3-Clause", note: nil, url: "https://github.com/hchunhui/librime-lua"),
        Component(name: "Lua", license: "MIT", note: nil, url: "https://www.lua.org"),
        Component(name: "OpenCC", license: "Apache 2.0", note: nil, url: "https://github.com/BYVoid/OpenCC"),
        Component(name: "Boost", license: "Boost Software License 1.0", note: nil, url: "https://www.boost.org"),
        Component(name: "glog", license: "BSD 3-Clause", note: nil, url: "https://github.com/google/glog"),
        Component(name: "LevelDB", license: "BSD 3-Clause", note: nil, url: "https://github.com/google/leveldb"),
        Component(name: "marisa-trie", license: "BSD 2-Clause", note: nil, url: "https://github.com/s-yata/marisa-trie"),
        Component(name: "yaml-cpp", license: "MIT", note: nil, url: "https://github.com/jbeder/yaml-cpp"),
    ]

    var body: some View {
        Section(L("开源组件", "Open source", "オープンソース")) {
            ForEach(components) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(item.license).foregroundStyle(.secondary)
                    }
                    if let note = item.note {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let url = URL(string: item.url) {
                        Link(item.url, destination: url).font(.footnote)
                    }
                }
            }
        }
    }
}
