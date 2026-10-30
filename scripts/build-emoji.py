#!/usr/bin/env python3
"""打字出 emoji 候选（0.95 A5）用的词表：从 Unicode CLDR 的中文 emoji 注释生成 Keyboard/Emoji/zh_emoji.tsv。
每行「词<Tab>emoji 空格分开」，最像的在前。CLDR 数据用 Unicode License v3（可商用，需保留版权声明，见 Licenses/LICENSE-cldr，App 的开源许可页里也有）。
用法：python3 scripts/build-emoji.py cldr/common/annotations/zh.xml Keyboard/Emoji/zh_emoji.tsv
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
}


def is_emoji(cp):
    if any(0x1F3FB <= ord(c) <= 0x1F3FF for c in cp) and len(cp) == 1:
        return False
    for c in cp:
        o = ord(c)
        if 0x1F300 <= o <= 0x1FAFF or 0x2600 <= o <= 0x27BF or o in (0x2B50, 0x2B55, 0x2764, 0x231A, 0x231B, 0x23F0, 0x23F3):
            return True
    return False


def emoji_style(cp):
    """☀、✈ 这类默认按文字样式显示的，补上 U+FE0F 让它显示成彩色 emoji。"""
    out = ''
    for i, c in enumerate(cp):
        out += c
        if 0x2600 <= ord(c) <= 0x27BF and cp[i + 1:i + 2] != '\ufe0f':
            out += '\ufe0f'
    return out


def cjk(word):
    return 1 <= len(word) <= 4 and all('一' <= c <= '鿿' for c in word)


def main(src, dst):
    names, keywords, order = {}, defaultdict(list), []
    for node in ET.parse(src).getroot().iter('annotation'):
        cp = node.get('cp')
        if not is_emoji(cp):
            continue
        if cp not in order:
            order.append(cp)
        words = [w.strip() for w in (node.text or '').split('|')]
        if node.get('type') == 'tts':
            names[cp] = words[0]
        else:
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
    lines = []
    for word in sorted(table):
        hits = sorted(set(table[word]))
        if len(hits) > MAX_PER_WORD and not any(h[0] == 0 for h in hits):
            continue
        seen = [emoji_style(e) for e in EXTRA.get(word, '').split()]
        for *_, cp in hits:
            cp = emoji_style(cp)
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
    main(*sys.argv[1:3])
