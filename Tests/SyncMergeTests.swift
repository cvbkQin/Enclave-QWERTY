import XCTest

/// iCloud 同步的合并规则（App/Sync/SyncMerge.swift，方案 specs/icloud-sync/iCloud同步方案.md 1.5–1.8）。
final class SyncMergeTests: XCTestCase {
    private typealias Entry = SyncMerge.Entry<String>
    private let t0 = SyncMerge.initialTime
    private let t1 = Date(timeIntervalSince1970: 1_000)
    private let t2 = Date(timeIntervalSince1970: 2_000)
    private let t3 = Date(timeIntervalSince1970: 3_000)

    private func items(_ pairs: [(String, String)]) -> [(key: String, value: String)] {
        pairs.map { (key: $0.0, value: $0.1) }
    }

    private func keys(_ list: [(key: String, value: String)]) -> [String] { list.map { $0.key } }

    // MARK: - 本机改动

    func testFirstObservationUsesInitialTime() {
        let table = SyncMerge.observe(current: items([("a", "1"), ("b", "2")]), previous: nil, now: t2)
        XCTAssertEqual(table["a"], Entry(value: "1", time: t0))
        XCTAssertEqual(table["b"], Entry(value: "2", time: t0))
    }

    func testObserveAddsChangesAndDeletes() {
        let previous: SyncMerge.Table<String> = [
            "same": Entry(value: "x", time: t1),
            "edited": Entry(value: "old", time: t1),
            "gone": Entry(value: "y", time: t1),
            "deleted": Entry(value: nil, time: t1),
        ]
        let table = SyncMerge.observe(current: items([("same", "x"), ("edited", "new"), ("added", "z")]), previous: previous, now: t2)
        XCTAssertEqual(table["same"], Entry(value: "x", time: t1), "没变的时间不动")
        XCTAssertEqual(table["edited"], Entry(value: "new", time: t2))
        XCTAssertEqual(table["added"], Entry(value: "z", time: t2))
        XCTAssertEqual(table["gone"], Entry(value: nil, time: t2), "不见了的记成删除")
        XCTAssertEqual(table["deleted"], Entry(value: nil, time: t1), "早就删了的不动")
    }

    func testObserveReAddAfterDelete() {
        let previous: SyncMerge.Table<String> = ["w": Entry(value: nil, time: t1)]
        let table = SyncMerge.observe(current: items([("w", "again")]), previous: previous, now: t2)
        XCTAssertEqual(table["w"], Entry(value: "again", time: t2))
    }

    func testObserveKeepsFirstOfDuplicateKeys() {
        let table = SyncMerge.observe(current: items([("a", "1"), ("a", "2")]), previous: [:], now: t2)
        XCTAssertEqual(table["a"]?.value, "1")
    }

    // MARK: - 合并

    func testMergeTakesLatest() {
        let a: SyncMerge.Table<String> = ["w": Entry(value: "a", time: t1), "x": Entry(value: nil, time: t3)]
        let b: SyncMerge.Table<String> = ["w": Entry(value: "b", time: t2), "x": Entry(value: "keep?", time: t2)]
        let merged = SyncMerge.merge([a, b])
        XCTAssertEqual(merged["w"], Entry(value: "b", time: t2))
        XCTAssertEqual(merged["x"], Entry(value: nil, time: t3), "后删的赢")
    }

    func testMergeTiePrefersPresent() {
        let deleted: SyncMerge.Table<String> = ["w": Entry(value: nil, time: t2)]
        let present: SyncMerge.Table<String> = ["w": Entry(value: "v", time: t2)]
        XCTAssertEqual(SyncMerge.merge([deleted, present])["w"]?.value, "v")
        XCTAssertEqual(SyncMerge.merge([present, deleted])["w"]?.value, "v")
    }

    func testMergeIsIdempotent() {
        let a: SyncMerge.Table<String> = ["w": Entry(value: "a", time: t1), "y": Entry(value: nil, time: t2)]
        let b: SyncMerge.Table<String> = ["w": Entry(value: "b", time: t3)]
        let once = SyncMerge.merge([a, b])
        XCTAssertEqual(SyncMerge.merge([once, a, b]), once)
        XCTAssertEqual(SyncMerge.merge([once, once]), once)
    }

    /// 一台删了、另一台没动：删除传到另一台，不会被合并回来。
    func testDeleteOnOneDevicePropagates() {
        // 两台一开始都有 w（第一次同步记成 initialTime）。
        let base = SyncMerge.observe(current: items([("w", "v")]), previous: nil, now: t1)
        // A 删了 w。
        let tableA = SyncMerge.observe(current: [], previous: base, now: t2)
        // B 没动。
        let tableB = SyncMerge.observe(current: items([("w", "v")]), previous: base, now: t2)
        let merged = SyncMerge.merge([tableA, tableB])
        XCTAssertNil(merged["w"]?.value)
        XCTAssertEqual(keys(SyncMerge.apply(merged, to: items([("w", "v")]))), [])
    }

    /// 新设备第一次同步：本机现有的不会盖过旧设备后来删、改过的。
    func testNewDeviceDoesNotOverrideOlderChanges() {
        let old: SyncMerge.Table<String> = ["w": Entry(value: nil, time: t1), "s": Entry(value: "edited", time: t1)]
        let fresh = SyncMerge.observe(current: items([("w", "v"), ("s", "default")]), previous: nil, now: t3)
        let merged = SyncMerge.merge([fresh, old])
        XCTAssertNil(merged["w"]?.value)
        XCTAssertEqual(merged["s"]?.value, "edited")
    }

    // MARK: - 写回本机列表

    func testApplyKeepsLocalOrderAndAppendsNew() {
        let merged: SyncMerge.Table<String> = [
            "b": Entry(value: "B", time: t1),
            "a": Entry(value: "a2", time: t2),
            "gone": Entry(value: nil, time: t2),
            "new2": Entry(value: "n2", time: t3),
            "new1": Entry(value: "n1", time: t2),
        ]
        let result = SyncMerge.apply(merged, to: items([("b", "B"), ("gone", "x"), ("a", "a1")]))
        XCTAssertEqual(keys(result), ["b", "a", "new1", "new2"])
        XCTAssertEqual(result.map { $0.value }, ["B", "a2", "n1", "n2"])
    }

    func testApplyNeverDropsUnknownLocalItems() {
        let result = SyncMerge.apply([:], to: items([("a", "1")]))
        XCTAssertEqual(keys(result), ["a"])
    }

    func testPruneDropsOldDeletesOnly() {
        let now = Date(timeIntervalSince1970: 400 * 86400)
        let table: SyncMerge.Table<String> = [
            "oldDelete": Entry(value: nil, time: Date(timeIntervalSince1970: 1)),
            "recentDelete": Entry(value: nil, time: Date(timeIntervalSince1970: 399 * 86400)),
            "oldPresent": Entry(value: "v", time: Date(timeIntervalSince1970: 1)),
        ]
        let pruned = SyncMerge.pruned(table, now: now)
        XCTAssertNil(pruned["oldDelete"])
        XCTAssertNotNil(pruned["recentDelete"])
        XCTAssertNotNil(pruned["oldPresent"])
    }

    // MARK: - 整份以最后修改为准

    func testObserveValue() {
        XCTAssertEqual(SyncMerge.observeValue("x", previous: nil, now: t2), Entry(value: "x", time: t0))
        let previous = Entry(value: "x", time: t1)
        XCTAssertEqual(SyncMerge.observeValue("x", previous: previous, now: t2), previous)
        XCTAssertEqual(SyncMerge.observeValue("y", previous: previous, now: t2), Entry(value: "y", time: t2))
    }

    func testLatestPrefersFirstOnTie() {
        let mine = Entry(value: "mine", time: t2)
        XCTAssertEqual(SyncMerge.latest([mine, Entry(value: "peer", time: t2)]), mine)
        XCTAssertEqual(SyncMerge.latest([mine, Entry(value: "peer", time: t3)])?.value, "peer")
        XCTAssertEqual(SyncMerge.latest([Entry(value: nil, time: t3), mine]), mine)
    }

    // MARK: - 同步的内容

    func testWordsKeepLocalIDsAndSkipSystemWords() {
        let mine = CommonWord(text: "飞地", pinyin: "fei di")
        let system = CommonWord(text: "张三", pinyin: "zhang san", source: .contact)
        let items = SyncMerge.wordItems([mine, system])
        XCTAssertEqual(items.map { $0.key }, ["飞地"])
        var incoming = SyncMerge.Word(CommonWord(text: "飞地", pinyin: "fei di", shortcut: "fd"))
        incoming.shortcut = "fd"
        let words = SyncMerge.words([(key: "飞地", value: incoming), (key: "新词", value: SyncMerge.Word(CommonWord(text: "新词", pinyin: "xin ci")))],
                                    current: [mine])
        XCTAssertEqual(words.first?.id, mine.id, "本机已有的词沿用原来的 id")
        XCTAssertEqual(words.first?.shortcut, "fd")
        XCTAssertEqual(words.last?.text, "新词")
    }

    func testAIProfileOnlyTouchesAIFields() {
        var settings = EnclaveSettings()
        settings.baseURL = "https://a.example/v1"
        settings.keyboardLayout = .nineKey
        settings.doublePinyin = nil
        let profile = SyncMerge.AIProfile(settings: settings, savedAPIs: [])

        var other = EnclaveSettings()
        other.keyboardLayout = .qwerty
        let fuzzy = Set(FuzzyPinyin.allCases.prefix(1))
        other.fuzzyPinyin = fuzzy
        let scheme = DoublePinyin.allCases.first
        other.doublePinyin = scheme
        profile.apply(to: &other)
        XCTAssertEqual(other.baseURL, "https://a.example/v1")
        XCTAssertEqual(other.keyboardLayout, .qwerty, "键盘布局不跟着同步")
        XCTAssertEqual(other.fuzzyPinyin, fuzzy, "模糊音不跟着同步")
        XCTAssertEqual(other.doublePinyin, scheme, "双拼不跟着同步")
    }

    func testPayloadRoundTrip() throws {
        let payload = SyncMerge.DevicePayload(
            format: SyncMerge.DevicePayload.currentFormat, deviceName: "iPhone", appVersion: "0.97_1", updatedAt: t2,
            generation: 2,
            words: ["飞地": SyncMerge.Entry(value: SyncMerge.Word(CommonWord(text: "飞地", pinyin: "fei di")), time: t1)],
            phrases: ["地址": SyncMerge.Entry(value: nil, time: t2)],
            ai: SyncMerge.Entry(value: SyncMerge.AIProfile(settings: EnclaveSettings(), savedAPIs: []), time: t1),
            snapshotChunks: 2, snapshotHash: "abc")
        let data = try JSONEncoder().encode(payload)
        XCTAssertEqual(try JSONDecoder().decode(SyncMerge.DevicePayload.self, from: data), payload)
    }

    // MARK: - 拼音快照

    func testGeneration() {
        XCTAssertEqual(SyncMerge.generation(local: 1, peers: []), 1)
        XCTAssertEqual(SyncMerge.generation(local: 1, peers: [0, 3, 2]), 3)
    }

    func testSnapshotPackRoundTrip() throws {
        let text = (0..<5000).map { "ni hao\t你好\tc=\($0) d=1.0 t=\($0)" }.joined(separator: "\n")
        let packed = try SyncMerge.packSnapshot(text, chunkSize: 1000)
        XCTAssertGreaterThan(packed.chunks.count, 1)
        XCTAssertTrue(packed.chunks.allSatisfy { $0.count <= 1000 })
        XCTAssertEqual(SyncMerge.unpackSnapshot(packed.chunks, hash: packed.hash), text)
        // 少一块、校验不对：不拼。
        XCTAssertNil(SyncMerge.unpackSnapshot(Array(packed.chunks.dropLast()), hash: packed.hash))
        XCTAssertNil(SyncMerge.unpackSnapshot(packed.chunks, hash: "0000"))
    }

    func testEmptySnapshot() throws {
        let packed = try SyncMerge.packSnapshot("", chunkSize: 1000)
        XCTAssertTrue(packed.chunks.isEmpty)
        XCTAssertEqual(packed.hash, "")
        XCTAssertEqual(SyncMerge.unpackSnapshot([], hash: ""), "")
        XCTAssertNil(SyncMerge.unpackSnapshot([], hash: "abc"))
    }
}
