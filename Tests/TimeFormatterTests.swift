import Testing
@testable import Redact

// MARK: - formatTime

@Test func formatTime_zero() {
    #expect(formatTime(0) == "00:00")
}

@Test func formatTime_secondsOnly() {
    #expect(formatTime(45) == "00:45")
}

@Test func formatTime_minutesAndSeconds() {
    #expect(formatTime(125) == "02:05")
}

@Test func formatTime_largeValues() {
    #expect(formatTime(3661) == "61:01")
}

@Test func formatTime_truncatesFractional() {
    #expect(formatTime(1.7) == "00:01")
}

// MARK: - formatSrtTime

@Test func formatSrtTime_zero() {
    #expect(formatSrtTime(0) == "00:00:00,000")
}

@Test func formatSrtTime_hoursMinutesSecondsMs() {
    #expect(formatSrtTime(3661.5) == "01:01:01,500")
}

@Test func formatSrtTime_padsCorrectly() {
    #expect(formatSrtTime(61.5) == "00:01:01,500")
}

// MARK: - formatTimeFull

@Test func formatTimeFull_withoutHoursUnderOneHour() {
    #expect(formatTimeFull(65.123) == "01:05.123")
}

@Test func formatTimeFull_withHoursOverOneHour() {
    #expect(formatTimeFull(3665) == "1:01:05")
}
