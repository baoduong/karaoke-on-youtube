import Testing
@testable import Karaoke

@Suite("SourceReference Parsing")
struct SourceReferenceTests {

    // MARK: - Full watch URLs

    @Test("Full watch URL with www")
    func fullWatchURLWithWWW() throws {
        let ref = try SourceReference.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    @Test("Full watch URL without www")
    func fullWatchURLWithoutWWW() throws {
        let ref = try SourceReference.parse("https://youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    @Test("Mobile watch URL")
    func mobileWatchURL() throws {
        let ref = try SourceReference.parse("https://m.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    @Test("Watch URL with extra query parameters")
    func watchURLWithExtraParams() throws {
        let ref = try SourceReference.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42&list=PLxxx")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    // MARK: - Short URLs

    @Test("Short youtu.be URL")
    func shortYouTuBeURL() throws {
        let ref = try SourceReference.parse("https://youtu.be/dQw4w9WgXcQ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    @Test("Short youtu.be URL with query params")
    func shortYouTuBeURLWithParams() throws {
        let ref = try SourceReference.parse("https://youtu.be/dQw4w9WgXcQ?t=30")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    // MARK: - Shorts and embed URLs

    @Test("YouTube Shorts URL")
    func shortsURL() throws {
        let ref = try SourceReference.parse("https://www.youtube.com/shorts/dQw4w9WgXcQ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    @Test("Embed URL")
    func embedURL() throws {
        let ref = try SourceReference.parse("https://www.youtube.com/embed/dQw4w9WgXcQ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    // MARK: - Bare identifiers

    @Test("Bare 11-char alphanumeric ID")
    func bareAlphanumericID() throws {
        let ref = try SourceReference.parse("dQw4w9WgXcQ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    @Test("Bare ID with underscores and hyphens")
    func bareIDWithSpecialChars() throws {
        let ref = try SourceReference.parse("abc_def-ghij")
        #expect(ref.songID == "abc_def-ghij")
    }

    @Test("Bare ID with leading/trailing whitespace is trimmed")
    func bareIDWithWhitespace() throws {
        let ref = try SourceReference.parse("  dQw4w9WgXcQ  ")
        #expect(ref.songID == "dQw4w9WgXcQ")
    }

    // MARK: - Malformed input — must return malformedReference with NO network call

    @Test("Empty string yields malformedReference")
    func emptyString() {
        #expect(throws: SourceError.malformedReference("")) {
            try SourceReference.parse("")
        }
    }

    @Test("Whitespace-only string yields malformedReference")
    func whitespaceOnly() {
        #expect(throws: SourceError.malformedReference("   ")) {
            try SourceReference.parse("   ")
        }
    }

    @Test("ID too short yields malformedReference")
    func idTooShort() {
        #expect {
            try SourceReference.parse("short")
        } throws: { error in
            if case SourceError.malformedReference = error { return true }
            return false
        }
    }

    @Test("ID too long yields malformedReference")
    func idTooLong() {
        #expect {
            try SourceReference.parse("dQw4w9WgXcQextra")
        } throws: { error in
            if case SourceError.malformedReference = error { return true }
            return false
        }
    }

    @Test("ID with invalid characters yields malformedReference")
    func idWithInvalidChars() {
        #expect {
            try SourceReference.parse("dQw4w9WgX!!")
        } throws: { error in
            if case SourceError.malformedReference = error { return true }
            return false
        }
    }

    @Test("Non-YouTube URL yields malformedReference")
    func nonYouTubeURL() {
        #expect {
            try SourceReference.parse("https://vimeo.com/123456789")
        } throws: { error in
            if case SourceError.malformedReference = error { return true }
            return false
        }
    }

    @Test("YouTube URL without v parameter yields malformedReference")
    func youTubeURLWithoutVParam() {
        #expect {
            try SourceReference.parse("https://www.youtube.com/channel/UCxxx")
        } throws: { error in
            if case SourceError.malformedReference = error { return true }
            return false
        }
    }

    @Test("YouTube URL with malformed video ID yields malformedReference")
    func youTubeURLWithMalformedID() {
        #expect {
            try SourceReference.parse("https://www.youtube.com/watch?v=tooshort")
        } throws: { error in
            if case SourceError.malformedReference = error { return true }
            return false
        }
    }

    // MARK: - ID validation helper

    @Test("isValidYouTubeID accepts valid IDs")
    func validYouTubeIDs() {
        #expect(SourceReference.isValidYouTubeID("dQw4w9WgXcQ"))
        #expect(SourceReference.isValidYouTubeID("AAAAAAAAAAA"))
        #expect(SourceReference.isValidYouTubeID("00000000000"))
        #expect(SourceReference.isValidYouTubeID("abc_def-ghi"))
    }

    @Test("isValidYouTubeID rejects invalid IDs")
    func invalidYouTubeIDs() {
        #expect(!SourceReference.isValidYouTubeID(""))
        #expect(!SourceReference.isValidYouTubeID("short"))
        #expect(!SourceReference.isValidYouTubeID("toolongstring12"))
        #expect(!SourceReference.isValidYouTubeID("dQw4w9WgX!!"))
        #expect(!SourceReference.isValidYouTubeID("dQw4w9WgX  "))
    }
}
