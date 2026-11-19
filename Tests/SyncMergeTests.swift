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

    func testStampNeverGoesBack() {
        XCTAssertEqual(SyncMerge.stamp(now: t2, after: nil), t2)
        XCTAssertEqual(SyncMerge.stamp(now: t2, after: t1), t2)
        XCTAssertEqual(SyncMerge.stamp(now: t2, after: t3), t3.addingTimeInterval(0.001), "上次的时间比现在还晚：取它加 1 毫秒")
    }

    /// 别的设备时钟快：它改的那条时间比本机的现在还晚，本机接着改也要赢（04 审查 #75 第 8 条）。
    func testLocalEditBeatsPeerWithFastClock() {
        let peer: SyncMerge.Table<String> = ["w": Entry(value: "peer", time: t3)]
        let previous = SyncMerge.merge([peer])
        let mine = SyncMerge.observe(current: items([("w", "mine"), ("x", "new")]), previous: previous, now: t2)
        XCTAssertGreaterThan(mine["w"]!.time, t3)
        XCTAssertEqual(mine["x"], Entry(value: "new", time: t2), "以前没有的条目照常记 now")
        XCTAssertEqual(SyncMerge.merge([peer, mine])["w"]?.value, "mine")
        let deleted = SyncMerge.observe(current: [], previous: previous, now: t2)
        XCTAssertNil(SyncMerge.merge([peer, deleted])["w"]?.value, "删除也一样")
    }

    func testObserveValueAfterFastClock() {
        let previous = Entry(value: "peer", time: t3)
        XCTAssertGreaterThan(SyncMerge.observeValue("mine", previous: previous, now: t2).time, t3)
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

    /// 手动加了两条同字的常用词：第一条按合并结果改，第二条留着，不在第一次同步时丢掉（04 审查 #75 第 9 条）。
    func testApplyKeepsDuplicateLocalItems() {
        let local = items([("a", "1"), ("b", "B"), ("a", "2")])
        let merged = SyncMerge.observe(current: local, previous: nil, now: t2)
        let same = SyncMerge.apply(merged, to: local)
        XCTAssertEqual(keys(same), ["a", "b", "a"])
        XCTAssertEqual(same.map { $0.value }, ["1", "B", "2"])

        let edited = SyncMerge.apply(["a": Entry(value: "x", time: t2)], to: local)
        XCTAssertEqual(edited.map { $0.value }, ["x", "B", "2"], "后面那条原样留着，也不再接到末尾")

        let deleted = SyncMerge.apply(["a": Entry(value: nil, time: t2)], to: local)
        XCTAssertEqual(keys(deleted), ["b"], "删了就两条一起去掉")
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

    /// 新设备（本机没有上次同步的记录）加入：别的设备已经设好了，本机的默认值不参加，直接用那份。
    func testResolveJoiningAdoptsPeers() {
        let peer = Entry(value: "peer", time: t1)
        let joined = SyncMerge.resolve(local: "default", previous: nil, peers: ["B": peer], myID: "A", now: t3)
        XCTAssertEqual(joined.record, peer)
        XCTAssertEqual(joined.apply, "peer")

        let alone = SyncMerge.resolve(local: "mine", previous: nil, peers: [:], myID: "A", now: t3)
        XCTAssertEqual(alone.record, Entry(value: "mine", time: t0), "只有自己：第一次记成 initialTime")
        XCTAssertNil(alone.apply)
    }

    /// 打开同步时选了「用这台的」：本机的记成比别的设备都晚，别的设备下次同步换成这台的。
    func testResolvePrefersLocal() {
        let peer = Entry(value: "peer", time: t3)
        let result = SyncMerge.resolve(local: "mine", previous: nil, peers: ["B": peer], myID: "A", now: t2, prefersLocal: true)
        XCTAssertEqual(result.record?.value, "mine")
        XCTAssertGreaterThan(result.record?.time ?? t0, t3)
        XCTAssertNil(result.apply)
        let onB = SyncMerge.resolve(local: "peer", previous: peer, peers: ["A": result.record!], myID: "B", now: t3)
        XCTAssertEqual(onB.apply, "mine")
    }

    func testResolveLocalChangeWins() {
        let result = SyncMerge.resolve(local: "new", previous: Entry(value: "old", time: t1),
                                       peers: ["B": Entry(value: "peer", time: t1)], myID: "A", now: t2)
        XCTAssertEqual(result.record, Entry(value: "new", time: t2))
        XCTAssertNil(result.apply)
    }

    func testResolvePeerChangeApplies() {
        let peer = Entry(value: "peer", time: t2)
        let result = SyncMerge.resolve(local: "x", previous: Entry(value: "x", time: t1), peers: ["B": peer], myID: "A", now: t3)
        XCTAssertEqual(result.record, peer)
        XCTAssertEqual(result.apply, "peer")
    }

    /// 时间一样：两台设备都按设备编号取编号小的那台，算出来一样，不会各自留自己的。
    func testResolveTieUsesDeviceOrder() {
        let a = Entry(value: "a", time: t1)
        let b = Entry(value: "b", time: t1)
        let onA = SyncMerge.resolve(local: "a", previous: a, peers: ["B": b], myID: "A", now: t2)
        let onB = SyncMerge.resolve(local: "b", previous: b, peers: ["A": a], myID: "B", now: t2)
        XCTAssertEqual(onA.record, a)
        XCTAssertNil(onA.apply)
        XCTAssertEqual(onB.record, a)
        XCTAssertEqual(onB.apply, "a")
    }

    /// 别的设备的接口配的 Key 还没同步过来：本机先不改、记本机原来的，下次再试。
    func testResolveRejectedKeepsMine() {
        let mine = Entry(value: "x", time: t1)
        let result = SyncMerge.resolve(local: "x", previous: mine, peers: ["B": Entry(value: "y", time: t2)], myID: "A", now: t3,
                                       accept: { _ in false })
        XCTAssertEqual(result.record, mine)
        XCTAssertNil(result.apply)

        let joining = SyncMerge.resolve(local: "x", previous: nil, peers: ["B": Entry(value: "y", time: t2)], myID: "A", now: t3,
                                        accept: { _ in false })
        XCTAssertNil(joining.record, "还没加入：这次不参加，下次还当第一次")
        XCTAssertNil(joining.apply)
    }

    func testAcceptingKeepsMineForRejected() {
        let mine: SyncMerge.Table<String> = ["a": Entry(value: "mine", time: t1), "same": Entry(value: "s", time: t1)]
        let merged: SyncMerge.Table<String> = [
            "a": Entry(value: "peer", time: t2),
            "same": Entry(value: "s", time: t1),
            "new": Entry(value: "n", time: t2),
            "ok": Entry(value: "fine", time: t2),
        ]
        let result = SyncMerge.accepting(merged, mine: mine) { $0.value == "fine" }
        XCTAssertEqual(result["a"], mine["a"], "不能用的记本机原来的")
        XCTAssertEqual(result["same"], mine["same"])
        XCTAssertNil(result["new"], "本机原来没有的：不记")
        XCTAssertEqual(result["ok"], merged["ok"])
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

    func testWordsKeepIDsForDuplicateTexts() {
        let first = CommonWord(text: "飞地", pinyin: "fei di")
        let second = CommonWord(text: "飞地", pinyin: "fei di", shortcut: "fd")
        let items = SyncMerge.wordItems([first, second])
        XCTAssertEqual(items.count, 2)
        let words = SyncMerge.words(items, current: [first, second])
        XCTAssertEqual(words.map { $0.id }, [first.id, second.id], "同字的两条各用各的 id")
    }

    func testStyleProfileOnlyTouchesStyleFields() {
        var settings = EnclaveSettings()
        settings.polishEnabled = false
        settings.styles = Array(StylePreset.defaults.prefix(1))
        settings.helpPinned = true
        settings.baseURL = "https://a.example/v1"
        let profile = SyncMerge.StyleProfile(settings: settings)

        var other = EnclaveSettings()
        other.baseURL = "https://b.example/v1"
        other.keyboardLayout = .nineKey
        let fuzzy = Set(FuzzyPinyin.allCases.prefix(1))
        other.fuzzyPinyin = fuzzy
        profile.apply(to: &other)
        XCTAssertFalse(other.polishEnabled)
        XCTAssertEqual(other.styles, settings.styles)
        XCTAssertTrue(other.helpPinned)
        XCTAssertEqual(other.baseURL, "https://b.example/v1", "接口不跟着风格同步")
        XCTAssertEqual(other.keyboardLayout, .nineKey, "键盘布局不跟着同步")
        XCTAssertEqual(other.fuzzyPinyin, fuzzy, "模糊音不跟着同步")
    }

    func testEndpointProfileOnlyTouchesEndpointFields() {
        var settings = EnclaveSettings()
        settings.baseURL = "https://a.example/v1"
        settings.model = "m1"
        settings.separateAnswer = true
        settings.answerModel = "m2"
        settings.answerMaxTokens = 2048
        settings.helpPinned = true
        let profile = SyncMerge.EndpointProfile(settings: settings, keys: ["apiKey": "f1"])

        var other = EnclaveSettings()
        other.keyboardLayout = .nineKey
        let scheme = DoublePinyin.allCases.first
        other.doublePinyin = scheme
        XCTAssertFalse(other.sameEndpoint(as: settings))
        profile.apply(to: &other)
        XCTAssertTrue(other.sameEndpoint(as: settings))
        XCTAssertFalse(other.helpPinned, "风格不跟着接口同步")
        XCTAssertEqual(other.keyboardLayout, .nineKey)
        XCTAssertEqual(other.doublePinyin, scheme, "双拼不跟着同步")
    }

    /// 键盘发请求前用的：只换接口那几项。
    func testAdoptEndpoint() {
        var stored = EnclaveSettings()
        stored.baseURL = "https://a.example/v1"
        stored.answerTemperature = 0.9
        var keyboard = EnclaveSettings()
        keyboard.helpPinned = true
        keyboard.keyboardLayout = .nineKey
        keyboard.adoptEndpoint(from: stored)
        XCTAssertTrue(keyboard.sameEndpoint(as: stored))
        XCTAssertTrue(keyboard.helpPinned)
        XCTAssertEqual(keyboard.keyboardLayout, .nineKey)
    }

    func testAPIItemsAndKeysMatch() {
        let api = SavedAPI(name: "A", baseURL: "https://a.example/v1", model: "m")
        let account = SyncMerge.SyncedAPI.account(api.id.uuidString)
        XCTAssertEqual(account, "apiKey.saved.\(api.id.uuidString)")
        let items = SyncMerge.apiItems([api]) { $0 == account ? "f1" : "" }
        XCTAssertEqual(items.first?.key, api.id.uuidString)
        XCTAssertEqual(items.first?.value, SyncMerge.SyncedAPI(api: api, key: "f1"))

        let keys = ["apiKey": "f1", "apiKey.answer": ""]
        XCTAssertTrue(SyncMerge.keysMatch(keys) { ["apiKey": "f1"][$0] ?? "" })
        XCTAssertFalse(SyncMerge.keysMatch(keys) { _ in "" }, "Key 还没同步过来")
        XCTAssertFalse(SyncMerge.keysMatch(keys) { ["apiKey": "f2"][$0] ?? "" }, "本机是另一个 Key")
    }

    func testKeyFingerprint() {
        XCTAssertEqual(Keychain.fingerprint(nil), "")
        XCTAssertEqual(Keychain.fingerprint(""), "")
        let one = Keychain.fingerprint("sk-one")
        XCTAssertEqual(one.count, 16)
        XCTAssertEqual(one, Keychain.fingerprint("sk-one"))
        XCTAssertNotEqual(one, Keychain.fingerprint("sk-two"))
    }

    private func samplePayload() -> SyncMerge.DevicePayload {
        let api = SavedAPI(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "A",
                           baseURL: "https://a.example/v1", model: "m", savedAt: t1)
        return SyncMerge.DevicePayload(
            format: SyncMerge.DevicePayload.currentFormat, deviceName: "我的 iPhone", deviceModel: "iPhone", appVersion: "0.97_1", updatedAt: t2,
            generation: 2,
            words: ["飞地": SyncMerge.Entry(value: SyncMerge.Word(CommonWord(text: "飞地", pinyin: "fei di")), time: t1)],
            phrases: ["地址": SyncMerge.Entry(value: nil, time: t2)],
            styles: SyncMerge.Entry(value: SyncMerge.StyleProfile(settings: EnclaveSettings()), time: t1),
            endpoint: SyncMerge.Entry(value: SyncMerge.EndpointProfile(settings: EnclaveSettings(), keys: ["apiKey": "f1"]), time: t1),
            apis: [api.id.uuidString: SyncMerge.Entry(value: SyncMerge.SyncedAPI(api: api, key: "f1"), time: t1)],
            snapshotChunks: 2, snapshotHash: "abc")
    }

    func testPayloadRoundTrip() throws {
        let payload = samplePayload()
        let data = try JSONEncoder().encode(payload)
        XCTAssertEqual(try JSONDecoder().decode(SyncMerge.DevicePayload.self, from: data), payload)

        var bare = payload
        bare.deviceModel = nil
        bare.styles = nil
        bare.endpoint = nil
        bare.apis = nil
        let bareData = try JSONEncoder().encode(bare)
        XCTAssertEqual(try JSONDecoder().decode(SyncMerge.DevicePayload.self, from: bareData), bare, "带内置 Key 的包不带这三项")
    }

    /// 内容没变就不重传（04 审查 #75 第 3 条）：上传时间不算内容。
    func testContentDigestIgnoresUpdatedAt() throws {
        let payload = samplePayload()
        var later = payload
        later.updatedAt = t3
        XCTAssertEqual(payload.contentDigest, later.contentDigest)
        XCTAssertEqual(payload.contentDigest, samplePayload().contentDigest, "每次算出来一样")
        let decoded = try JSONDecoder().decode(SyncMerge.DevicePayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(decoded.contentDigest, payload.contentDigest, "下载回来再算也一样（字典顺序不影响）")
        var cleared = payload
        cleared.generation += 1
        XCTAssertNotEqual(payload.contentDigest, cleared.contentDigest)
        var edited = payload
        edited.phrases["地址"] = SyncMerge.Entry(value: KeyboardPhrase(text: "地址"), time: t3)
        XCTAssertNotEqual(payload.contentDigest, edited.contentDigest)
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
