import Testing
@testable import Karaoke

@Suite("Rendition Selection")
struct RenditionSelectionTests {

    // MARK: - Helpers

    private func makeRendition(
        itag: Int,
        codec: Codec = .aac,
        container: Container = .m4a,
        bitrate: Int? = 128_000,
        channelCount: Int? = 2,
        isDecodable: Bool = true
    ) -> AudioRendition {
        AudioRendition(
            itag: itag,
            container: container,
            codec: codec,
            averageBitrateBps: bitrate,
            sampleRateHz: 44100,
            channelCount: channelCount,
            approximateByteSize: nil,
            isDecodableOnDevice: isDecodable
        )
    }

    // MARK: - Basic selection

    @Test("Selects highest bitrate rendition")
    func selectsHighestBitrate() throws {
        let renditions = [
            makeRendition(itag: 139, bitrate: 48_000),
            makeRendition(itag: 140, bitrate: 128_000),
            makeRendition(itag: 141, bitrate: 256_000),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 141)
    }

    @Test("Breaks bitrate tie by codec preference — AAC before Opus")
    func breaksBitrateTieByCodec() throws {
        let renditions = [
            makeRendition(itag: 251, codec: .opus, container: .webm, bitrate: 128_000),
            makeRendition(itag: 140, codec: .aac, container: .m4a, bitrate: 128_000),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 140, "AAC should be preferred over Opus at equal bitrate (research.md R1)")
    }

    @Test("Breaks codec tie by channel count descending")
    func breaksCodecTieByChannelCount() throws {
        let renditions = [
            makeRendition(itag: 140, codec: .aac, bitrate: 128_000, channelCount: 1),
            makeRendition(itag: 141, codec: .aac, bitrate: 128_000, channelCount: 2),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 141, "More channels should be preferred")
    }

    @Test("Breaks remaining ties by itag ascending for determinism")
    func breaksRemainingTiesByItagAscending() throws {
        let renditions = [
            makeRendition(itag: 200, codec: .aac, bitrate: 128_000, channelCount: 2),
            makeRendition(itag: 140, codec: .aac, bitrate: 128_000, channelCount: 2),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 140, "Lower itag should win for determinism")
    }

    // MARK: - Decodability filtering

    @Test("Discards undecodable renditions")
    func discardsUndecodable() throws {
        let renditions = [
            makeRendition(itag: 251, codec: .opus, container: .webm, bitrate: 160_000, isDecodable: false),
            makeRendition(itag: 140, codec: .aac, container: .m4a, bitrate: 128_000, isDecodable: true),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 140, "Undecodable rendition should be discarded")
    }

    @Test("All undecodable → noAudioRenditions, NOT notFound")
    func allUndecodableThrowsNoAudioRenditions() {
        let renditions = [
            makeRendition(itag: 251, codec: .opus, container: .webm, bitrate: 160_000, isDecodable: false),
            makeRendition(itag: 249, codec: .opus, container: .webm, bitrate: 50_000, isDecodable: false),
        ]
        #expect {
            try RenditionSelection.select(from: renditions, songID: "testSongID11")
        } throws: { error in
            if case SourceError.noAudioRenditions(let id) = error {
                return id == "testSongID11"
            }
            return false
        }
    }

    @Test("Empty rendition set → noAudioRenditions")
    func emptySetThrowsNoAudioRenditions() {
        #expect {
            try RenditionSelection.select(from: [], songID: "testSongID11")
        } throws: { error in
            if case SourceError.noAudioRenditions = error { return true }
            return false
        }
    }

    // MARK: - Absent bitrate

    @Test("Absent bitrate falls back to codec preference")
    func absentBitrateUsesCodecPreference() throws {
        let renditions = [
            makeRendition(itag: 251, codec: .opus, container: .webm, bitrate: nil),
            makeRendition(itag: 140, codec: .aac, container: .m4a, bitrate: nil),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 140, "With no bitrate, AAC should be preferred over Opus")
    }

    @Test("Known bitrate beats absent bitrate")
    func knownBitrateBeatsAbsent() throws {
        let renditions = [
            makeRendition(itag: 140, codec: .aac, bitrate: 128_000),
            makeRendition(itag: 141, codec: .aac, bitrate: nil),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 140, "Known bitrate (128k) should beat absent bitrate (treated as 0)")
    }

    // MARK: - Unknown codec

    /// Codec preference is a tie-breaker, not an override of bitrate
    /// (data-model.md Selection Rule steps 2 and 3). At equal bitrate a known
    /// codec wins; a higher bitrate still wins outright.
    @Test("Unknown codec ranks last at equal bitrate")
    func unknownCodecRanksLastAtEqualBitrate() throws {
        let renditions = [
            makeRendition(itag: 999, codec: .other("ec-3"), bitrate: 128_000),
            makeRendition(itag: 140, codec: .aac, bitrate: 128_000),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 140, "At equal bitrate, a known codec beats an unknown one")
    }

    @Test("Higher bitrate wins even with an unknown codec")
    func bitrateDominatesCodecPreference() throws {
        let renditions = [
            makeRendition(itag: 999, codec: .other("ec-3"), bitrate: 160_000),
            makeRendition(itag: 140, codec: .aac, bitrate: 64_000),
        ]
        let selected = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(selected.itag == 999, "Bitrate is ranked before codec preference; it is not overridden by it")
    }

    // MARK: - Duplicate itag detection

    @Test("Duplicate itag is detected by firstDuplicateItag")
    func duplicateItagDetected() {
        let renditions = [
            makeRendition(itag: 140),
            makeRendition(itag: 251, codec: .opus, container: .webm),
            makeRendition(itag: 140),
        ]
        let duplicate = RenditionSelection.firstDuplicateItag(in: renditions)
        #expect(duplicate == 140)
    }

    @Test("No duplicates returns nil")
    func noDuplicatesReturnsNil() {
        let renditions = [
            makeRendition(itag: 139),
            makeRendition(itag: 140),
            makeRendition(itag: 141),
        ]
        let duplicate = RenditionSelection.firstDuplicateItag(in: renditions)
        #expect(duplicate == nil)
    }

    // MARK: - Pure function property

    @Test("Same input always produces same output")
    func pureFunction() throws {
        let renditions = [
            makeRendition(itag: 139, bitrate: 48_000),
            makeRendition(itag: 140, bitrate: 128_000),
            makeRendition(itag: 251, codec: .opus, container: .webm, bitrate: 160_000, isDecodable: false),
        ]
        let first = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        let second = try RenditionSelection.select(from: renditions, songID: "testSongID11")
        #expect(first.itag == second.itag, "Selection must be deterministic")
    }

    // MARK: - rank() helper

    @Test("rank() returns only decodable renditions in order")
    func rankReturnsDecodableInOrder() {
        let renditions = [
            makeRendition(itag: 139, bitrate: 48_000),
            makeRendition(itag: 251, codec: .opus, container: .webm, bitrate: 160_000, isDecodable: false),
            makeRendition(itag: 140, bitrate: 128_000),
        ]
        let ranked = RenditionSelection.rank(renditions: renditions)
        #expect(ranked.count == 2)
        #expect(ranked[0].itag == 140)
        #expect(ranked[1].itag == 139)
    }
}
