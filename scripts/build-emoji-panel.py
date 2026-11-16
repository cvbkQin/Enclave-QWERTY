#!/usr/bin/env python3
"""表情面板用的完整 emoji 表：从 Unicode 的 emoji-test.txt 生成 Keyboard/Emoji/emoji_panel.tsv。
分类和顺序对齐 iOS 系统键盘：笑脸与人物、动物与自然、食物与饮料、活动、旅行与地点、物品、符号、旗帜。
只取 fully-qualified 的（❤️ 带 FE0F、国旗、#️⃣ 键帽、👨‍👩‍👧 这类组合都有）；肤色变体不单独占格，
挂在不带肤色的那个后面，留给长按选肤色用（两人组合的两人不同肤色也挂上，如 🫱🏻‍🫲🏼 挂在 🤝 后面）。

输出格式：
  # 分类名            一个分类开始
  emoji<Tab>版本<Tab>肤色变体（空格分开，每个写成 emoji/版本/肤色，没有就空）
肤色是 1–5（浅到深），两人组合写两位，第一位是左边那个人（🫱🏻‍🫲🏼 是 12）；两人同色的也写两位（💏🏻 是 11）。
版本是 Unicode emoji 版本（如 15.1），键盘按系统版本藏掉显示不出来的（见 EmojiCatalog.minimumOS）。

合规：中国大陆上架，旗帜里不放 🇹🇼（同 iOS 系统键盘在中国大陆地区的做法）。

emoji-test.txt 的使用条款见 https://www.unicode.org/terms_of_use.html（Unicode License v3，同 CLDR，见 Licenses/LICENSE-cldr）。
用法：python3 scripts/build-emoji-panel.py emoji-test.txt Keyboard/Emoji/emoji_panel.tsv
下载：https://raw.githubusercontent.com/unicode-org/unicodetools/main/unicodetools/data/emoji/17.0/emoji-test.txt
"""
import re, sys

# Unicode 的大类 → iOS 键盘的分类（iOS 把活动排在旅行前面，笑脸和人物合成一类）。
GROUPS = {
    'Smileys & Emotion': '笑脸与人物',
    'People & Body': '笑脸与人物',
    'Animals & Nature': '动物与自然',
    'Food & Drink': '食物与饮料',
    'Activities': '活动',
    'Travel & Places': '旅行与地点',
    'Objects': '物品',
    'Symbols': '符号',
    'Flags': '旗帜',
}
ORDER = ['笑脸与人物', '动物与自然', '食物与饮料', '活动', '旅行与地点', '物品', '符号', '旗帜']

# 中国大陆合规不放的。
EXCLUDE = {'\U0001F1F9\U0001F1FC'}  # 🇹🇼

TONES = set(range(0x1F3FB, 0x1F400))
LINE = re.compile(r'^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E(\d+\.\d+)\s+(.+)$')
TONE_NAME = re.compile(r'^(light|medium-light|medium|medium-dark|dark) skin tone$')


def base_name(name):
    """去掉名字里的肤色，用来把肤色变体对回原来那个：「handshake: light skin tone, medium skin tone」→「handshake」，
    「kiss: woman, man, light skin tone, dark skin tone」→「kiss: woman, man」，「man: light skin tone, red hair」→「man: red hair」。"""
    head, _, rest = name.partition(': ')
    parts = [p for p in rest.split(', ') if p and not TONE_NAME.match(p)]
    return f'{head}: {", ".join(parts)}' if parts else head


def tone_code(seq):
    return ''.join(str(ord(c) - 0x1F3FA) for c in seq if ord(c) in TONES)


def main(src, dst):
    group = None
    cats = {name: [] for name in ORDER}
    base = {}      # 名字 -> 那一项
    toned = []     # (原来那个的名字, seq, ver)
    for raw in open(src, encoding='utf-8'):
        if raw.startswith('# group:'):
            group = GROUPS.get(raw.split(':', 1)[1].strip())
            continue
        m = LINE.match(raw)
        if not m or group is None:
            continue
        seq = ''.join(chr(int(h, 16)) for h in m.group(1).split())
        ver, name = m.group(2), m.group(3).strip()
        if seq in EXCLUDE:
            continue
        if any(ord(c) in TONES for c in seq):
            toned.append((base_name(name), seq, ver))
            continue
        item = [seq, ver, []]
        cats[group].append(item)
        base[name] = item
    orphan = []
    for k, seq, ver in toned:
        # 「kiss: person, person, …」没有对应的原型，归到「kiss」（💏）。
        k = k if k in base else k.partition(': ')[0]
        if k in base:
            base[k][2].append((seq, ver, tone_code(seq)))
        else:
            orphan.append(seq)
    for items in cats.values():
        for item in items:
            tones = item[2]
            if any(len(code) == 2 for _, _, code in tones):
                # 两人组合：同色的只带一个肤色（💏🏻），补成两位；按 11 12 … 55 排好。
                tones[:] = sorted(((s, v, c * 2 if len(c) == 1 else c) for s, v, c in tones), key=lambda t: t[2])
                codes = [c for _, _, c in tones]
                assert len(set(codes)) == len(codes), item[0]
            item[2] = [f'{s}/{v}/{c}' for s, v, c in tones]
    with open(dst, 'w', encoding='utf-8') as out:
        for name in ORDER:
            out.write(f'# {name}\n')
            for seq, ver, tones in cats[name]:
                out.write(f'{seq}\t{ver}\t{" ".join(tones)}\n')
    total = sum(len(v) for v in cats.values())
    print(f'{total} 个，{sum(len(i[2]) for v in cats.values() for i in v)} 个肤色变体，{len(orphan)} 个没对上原型 {"".join(orphan)}', file=sys.stderr)
    for name in ORDER:
        print(f'  {name} {len(cats[name])}', file=sys.stderr)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
