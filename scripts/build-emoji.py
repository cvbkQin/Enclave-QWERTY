#!/usr/bin/env python3
"""打字出 emoji 候选（0.95 A5）用的词表：从 Unicode CLDR 的中文 emoji 注释生成 Keyboard/Emoji/zh_emoji.tsv。
每行「词<Tab>emoji 空格分开」，最像的在前。CLDR 数据用 Unicode License v3（可商用，需保留版权声明，见 Licenses/LICENSE-cldr，App 的开源许可页里也有）。
用法：python3 scripts/build-emoji.py cldr/common/annotations/zh.xml cldr/common/annotationsDerived/zh.xml emoji-test.txt Keyboard/Emoji/zh_emoji.tsv
annotationsDerived 里有国旗（「旗: 日本」→ 打「日本」出 🇯🇵）和组合 emoji 的注释；emoji-test.txt（同 build-emoji-panel.py）
用来把每个 emoji 换成系统键盘上屏的标准写法（⚽ 不加 FE0F、🕸️ 要加），只收 iOS 键盘里有的。
不收 🇹🇼（中国大陆上架合规，同表情面板）。系统版本显示不出来的，键盘里按 emoji_panel.tsv 藏掉（见 EmojiTable）。
"""
import re, sys, xml.etree.ElementTree as ET
from collections import defaultdict

# 一个词对上太多 emoji（脸、手、肤色、符号）说明太泛，不出。
MAX_PER_WORD = 6
KEEP = 3
# CLDR 里没有或排得不顺的常用词，手工补在最前（来源同样是 CLDR 里这些 emoji 的含义）。
EXTRA = {
    '开心': '😄 😊', '爱心': '❤️', '心': '❤️', '红心': '❤️', '爱你': '❤️ 😘', '点赞': '👍', '赞': '👍', '笑': '😄', '哈哈': '😄 😂', '哈哈哈': '😂 🤣',
    '钱': '💰', '发财': '💰 🧧', '红包': '🧧', '中国': '🇨🇳', '生日': '🎂 🥳', '生日快乐': '🎂 🥳', '晚安': '🌙 😴', '早安': '☀️',
    '加油': '💪 ⛽', '好的': '👌', '可以': '👌', '没问题': '👌', '鼓掌': '👏', '庆祝': '🎉', '恭喜': '🎉 👏', '干杯': '🍻 🥂',
    # CLDR 里「问题」只对上 ❔（白色问号），在候选里像个没显示出来的灰色占位（bug #16）；跟系统键盘一样给 🙋。
    '问题': '🙋 ❓',
}


TONES = set(range(0x1F3FB, 0x1F400))
EXCLUDE = {'\U0001F1F9\U0001F1FC'}  # 🇹🇼
# 国旗的名字太长或带后缀的，补个短的。
FLAG_ALIAS = {'中国香港特别行政区': '香港', '中国澳门特别行政区': '澳门'}


def strip(cp):
    return cp.replace('\ufe0f', '')


def load_qualified(path):
    """emoji-test.txt 里 fully-qualified 的：去掉 FE0F 后 → 标准写法。不收带肤色的（候选里给原色，同系统键盘）。"""
    result = {}
    for line in open(path, encoding='utf-8'):
        m = re.match(r'^([0-9A-F ]+?)\s*;\s*fully-qualified\s', line)
        if not m:
            continue
        cp = ''.join(chr(int(h, 16)) for h in m.group(1).split())
        if any(ord(c) in TONES for c in cp) or cp in EXCLUDE:
            continue
        result[strip(cp)] = cp
    return result


def cjk(word):
    return 1 <= len(word) <= 4 and all('一' <= c <= '鿿' for c in word)


def is_flag_name(word):
    return 2 <= len(word) <= 10 and all('一' <= c <= '鿿' for c in word)


def main(src, derived, emoji_test, dst):
    qualified = load_qualified(emoji_test)
    names, keywords, order = {}, defaultdict(list), []
    flags = defaultdict(list)
    for path in (src, derived):
        for node in ET.parse(path).getroot().iter('annotation'):
            cp = qualified.get(strip(node.get('cp')))
            if cp is None:
                continue
            if cp not in order:
                order.append(cp)
            words = [w.strip() for w in (node.text or '').split('|')]
            if node.get('type') == 'tts':
                names.setdefault(cp, words[0])
                # 「旗: 日本」：国家和地区名对上国旗。
                if words[0].startswith('旗: '):
                    country = words[0][3:]
                    for w in (country, FLAG_ALIAS.get(country)):
                        if w and is_flag_name(w):
                            flags[w].append(cp)
                            flags[w + '国旗'].append(cp)
            elif path == src:
                # 派生注释的关键词（发型、组合的各个部分）太泛，会把「浪漫」「金发」这类词挤成对上太多个而不出，只用它的名字。
                keywords[cp] += words
    table = defaultdict(list)
    for cp in order:
        name = names.get(cp, '')
        if cjk(name):
            table[name].append((0, 0, order.index(cp), cp))
        # 关键词少的 emoji 意思更专一，排前面；单字的词只认 emoji 的名字（「好」「是」这类太常见）。
        for w in keywords[cp]:
            if cjk(w) and w != name and len(w) > 1:
                table[w].append((1, len(keywords[cp]), order.index(cp), cp))
    for word, cps in flags.items():
        for cp in cps:
            table[word].append((0, 0, order.index(cp), cp))
    lines = []
    for word in sorted(table):
        hits = sorted(set(table[word]))
        if len(hits) > MAX_PER_WORD and not any(h[0] == 0 for h in hits):
            continue
        seen = [qualified.get(strip(e), e) for e in EXTRA.get(word, '').split()]
        for *_, cp in hits:
            if cp not in seen:
                seen.append(cp)
        lines.append(f"{word}\t{' '.join(seen[:KEEP])}")
    for word in sorted(set(EXTRA) - set(table)):
        lines.append(f"{word}\t{EXTRA[word]}")
    lines.sort()
    with open(dst, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print(f'{len(lines)} 个词 → {dst}')


if __name__ == '__main__':
    main(*sys.argv[1:5])
