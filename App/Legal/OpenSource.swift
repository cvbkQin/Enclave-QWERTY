import Foundation

/// 开源组件、版权声明和许可全文（P09），以及万象拼音的署名文字（P08）。
enum OpenSource {
    struct Component: Identifiable {
        let name: String
        let copyright: String
        let license: License
        let url: String
        var id: String { name }
    }

    enum License {
        case bsd3, bsd2, mit, boost, apache2, unicode3

        var name: String {
            switch self {
            case .bsd3: return "BSD 3-Clause"
            case .bsd2: return "BSD 2-Clause"
            case .mit: return "MIT"
            case .boost: return "Boost 1.0"
            case .apache2: return "Apache 2.0"
            case .unicode3: return "Unicode License v3"
            }
        }

        func text(copyright: String) -> String {
            switch self {
            case .bsd3: return copyright + "\n\n" + Self.bsd3Text
            case .bsd2: return copyright + "\n\n" + Self.bsd2Text
            case .mit: return copyright + "\n\n" + Self.mitText
            case .boost: return Self.boostText
            case .apache2: return copyright + "\n\n" + Self.apacheText
            case .unicode3: return copyright + "\n\n" + Self.unicodeText
            }
        }

        private static let bsd2Text = """
        Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

        1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

        2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """

        private static let bsd3Text = """
        Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

        1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

        2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

        3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """

        private static let unicodeText = """
        NOTICE TO USER: Carefully read the following legal agreement. BY DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

        Permission is hereby granted, free of charge, to any person obtaining a copy of data files and any associated documentation (the "Data Files") or software and any associated documentation (the "Software") to deal in the Data Files or Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, and/or sell copies of the Data Files or Software, and to permit persons to whom the Data Files or Software are furnished to do so, provided that either (a) this copyright and permission notice appear with all copies of the Data Files or Software, or (b) this copyright and permission notice appear in associated Documentation.

        THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF THIRD PARTY RIGHTS.

        IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA FILES OR SOFTWARE.

        Except as contained in this notice, the name of a copyright holder shall not be used in advertising or otherwise to promote the sale, use or other dealings in these Data Files or Software without prior written authorization of the copyright holder.

        SPDX-License-Identifier: Unicode-3.0
        """

        private static let mitText = """
        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """

        private static let boostText = """
        Boost Software License - Version 1.0 - August 17th, 2003

        Permission is hereby granted, free of charge, to any person or organization obtaining a copy of the software and accompanying documentation covered by this license (the "Software") to use, reproduce, display, distribute, execute, and transmit the Software, and to prepare derivative works of the Software, and to permit third-parties to whom the Software is furnished to do so, all subject to the following:

        The copyright notices in the Software and this entire statement, including the above license grant, this restriction and the following disclaimer, must be included in all copies of the Software, in whole or in part, and all derivative works of the Software, unless such copies or derivative works are solely in the form of machine-executable object code generated by a source language processor.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """

        private static let apacheText = """
        Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

            http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

        Apache License, Version 2.0, January 2004

        TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

        1. Definitions. "License" shall mean the terms and conditions for use, reproduction, and distribution as defined by Sections 1 through 9 of this document. "Licensor" shall mean the copyright owner or entity authorized by the copyright owner that is granting the License. "Legal Entity" shall mean the union of the acting entity and all other entities that control, are controlled by, or are under common control with that entity. "You" (or "Your") shall mean an individual or Legal Entity exercising permissions granted by this License. "Source" form shall mean the preferred form for making modifications. "Object" form shall mean any form resulting from mechanical transformation or translation of a Source form. "Work" shall mean the work of authorship made available under the License. "Derivative Works" shall mean any work that is based on (or derived from) the Work. "Contribution" shall mean any work of authorship intentionally submitted to Licensor for inclusion in the Work. "Contributor" shall mean Licensor and any individual or Legal Entity on behalf of whom a Contribution has been received by Licensor and subsequently incorporated within the Work.

        2. Grant of Copyright License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare Derivative Works of, publicly display, publicly perform, sublicense, and distribute the Work and such Derivative Works in Source or Object form.

        3. Grant of Patent License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable (except as stated in this section) patent license to make, have made, use, offer to sell, sell, import, and otherwise transfer the Work, where such license applies only to those patent claims licensable by such Contributor that are necessarily infringed by their Contribution(s) alone or by combination of their Contribution(s) with the Work to which such Contribution(s) was submitted. If You institute patent litigation against any entity alleging that the Work or a Contribution incorporated within the Work constitutes direct or contributory patent infringement, then any patent licenses granted to You under this License for that Work shall terminate as of the date such litigation is filed.

        4. Redistribution. You may reproduce and distribute copies of the Work or Derivative Works thereof in any medium, with or without modifications, and in Source or Object form, provided that You meet the following conditions: (a) You must give any other recipients of the Work or Derivative Works a copy of this License; and (b) You must cause any modified files to carry prominent notices stating that You changed the files; and (c) You must retain, in the Source form of any Derivative Works that You distribute, all copyright, patent, trademark, and attribution notices from the Source form of the Work; and (d) If the Work includes a "NOTICE" text file as part of its distribution, then any Derivative Works that You distribute must include a readable copy of the attribution notices contained within such NOTICE file.

        5. Submission of Contributions. Unless You explicitly state otherwise, any Contribution intentionally submitted for inclusion in the Work by You to the Licensor shall be under the terms and conditions of this License, without any additional terms or conditions.

        6. Trademarks. This License does not grant permission to use the trade names, trademarks, service marks, or product names of the Licensor, except as required for reasonable and customary use in describing the origin of the Work and reproducing the content of the NOTICE file.

        7. Disclaimer of Warranty. Unless required by applicable law or agreed to in writing, Licensor provides the Work (and each Contributor provides its Contributions) on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, including, without limitation, any warranties or conditions of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE.

        8. Limitation of Liability. In no event and under no legal theory, whether in tort (including negligence), contract, or otherwise, unless required by applicable law (such as deliberate and grossly negligent acts) or agreed to in writing, shall any Contributor be liable to You for damages, including any direct, indirect, special, incidental, or consequential damages of any character arising as a result of this License or out of the use or inability to use the Work.

        9. Accepting Warranty or Additional Liability. While redistributing the Work or Derivative Works thereof, You may choose to offer, and charge a fee for, acceptance of support, warranty, indemnity, or other liability obligations and/or rights consistent with this License. However, in accepting such obligations, You may act only on Your own behalf and on Your sole responsibility, not on behalf of any other Contributor, and only if You agree to indemnify, defend, and hold each Contributor harmless for any liability incurred by, or claims asserted against, such Contributor by reason of your accepting any such warranty or additional liability.

        END OF TERMS AND CONDITIONS
        """
    }

    static let components: [Component] = [
        Component(name: "librime", copyright: "Copyright (c) RIME Developers", license: .bsd3,
                  url: "https://github.com/rime/librime"),
        Component(name: "librime-lua", copyright: "Copyright (c) 2019, Chunhui He", license: .bsd3,
                  url: "https://github.com/hchunhui/librime-lua"),
        Component(name: "librime-octagram", copyright: "Copyright (c) 2014, RIME Developers", license: .bsd3,
                  url: "https://github.com/lotem/librime-octagram"),
        Component(name: "librime-predict", copyright: "Copyright (c) 2023, RIME Developers", license: .bsd3,
                  url: "https://github.com/rime/librime-predict"),
        Component(name: "Lua", copyright: "Copyright (c) 1994–2024 Lua.org, PUC-Rio.", license: .mit,
                  url: "https://www.lua.org"),
        Component(name: "OpenCC", copyright: "Copyright (c) 2010-2020 Carbo Kuo and contributors", license: .apache2,
                  url: "https://github.com/BYVoid/OpenCC"),
        // emoji 候选的中文关键词（scripts/build-emoji.py 生成 zh_emoji.tsv）。
        Component(name: "Unicode CLDR", copyright: "Copyright © 2004-2024 Unicode, Inc.", license: .unicode3,
                  url: "https://github.com/unicode-org/cldr"),
        Component(name: "Boost", copyright: "Copyright (c) Boost contributors", license: .boost,
                  url: "https://www.boost.org"),
        Component(name: "glog", copyright: "Copyright (c) 2008, Google Inc.", license: .bsd3,
                  url: "https://github.com/google/glog"),
        Component(name: "LevelDB", copyright: "Copyright (c) 2011 The LevelDB Authors. All rights reserved.", license: .bsd3,
                  url: "https://github.com/google/leveldb"),
        Component(name: "marisa-trie", copyright: "Copyright (c) 2010-2019, Susumu Yata", license: .bsd2,
                  url: "https://github.com/s-yata/marisa-trie"),
        Component(name: "yaml-cpp", copyright: "Copyright (c) 2008-2015 Jesse Beder.", license: .mit,
                  url: "https://github.com/jbeder/yaml-cpp"),
    ]

    /// 关于页「致谢」组下方的署名。
    static var wanxiangAttribution: String {
        L("拼音词库基于 amzxyz 的「万象拼音」（github.com/amzxyz/rime_wanxiang），按 CC BY 4.0 许可使用。飞地输入法去掉了拼音声调，并按词频删减了词条。可选下载的整句模型是 amzxyz 的「万象语法模型」（github.com/amzxyz/rime-wanxiang-data），按 CC BY 4.0 许可原样使用。英文单词补全用的是万象拼音的英文词库；英文下一个词联想来自 Tatoeba 英文例句（tatoeba.org）的相邻词统计，按 CC BY 2.0 FR 许可使用，只用了统计结果，没有收录例句原文。",
          "The pinyin dictionary is based on Wanxiang Pinyin by amzxyz (github.com/amzxyz/rime_wanxiang), used under CC BY 4.0. Enclave removed tone marks and trimmed entries by frequency. The optional sentence model is the Wanxiang grammar model by amzxyz (github.com/amzxyz/rime-wanxiang-data), used unmodified under CC BY 4.0. English word completion uses the Wanxiang Pinyin English word list. English next-word suggestions come from word-pair counts in Tatoeba English sentences (tatoeba.org), used under CC BY 2.0 FR; only the counts are included, not the sentences.",
          "ピンイン辞書は amzxyz 氏の「万象ピンイン」（github.com/amzxyz/rime_wanxiang）を CC BY 4.0 のもとで使用しています。Enclave では声調を除き、頻度に応じて語を削っています。オプションの文章モデルは amzxyz 氏の「万象文法モデル」（github.com/amzxyz/rime-wanxiang-data）を CC BY 4.0 のもとでそのまま使用しています。英単語の補完には万象ピンインの英語辞書を、英語の次の単語の予測には Tatoeba の英語例文（tatoeba.org）の隣接語の統計を CC BY 2.0 FR のもとで使用しています（統計のみで、例文そのものは含みません）。")
    }
}
