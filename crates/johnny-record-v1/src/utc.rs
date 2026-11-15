//! UTC calendar time from a Unix timestamp (no leap seconds, like gmtime).

/// `(year, month, day, hour, minute, second)` for `secs` since the epoch.
pub fn civil_from_unix(secs: i64) -> (i64, u32, u32, u32, u32, u32) {
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400) as u32;
    // Days to civil date: Howard Hinnant, "chrono-Compatible Low-Level Date
    // Algorithms", http://howardhinnant.github.io/date_algorithms.html
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let year = yoe + era * 400 + i64::from(month <= 2);
    (year, month, day, rem / 3_600, rem % 3_600 / 60, rem % 60)
}

/// `%Y%m%dT%H%M%SZ`, the stamp in a run file name.
pub fn compact(secs: i64) -> String {
    let (y, mo, d, h, mi, s) = civil_from_unix(secs);
    format!("{y:04}{mo:02}{d:02}T{h:02}{mi:02}{s:02}Z")
}

/// `%Y-%m-%d %H:%M:%SZ`, the stamp in a summary HEADER line.
pub fn spaced(secs: i64) -> String {
    let (y, mo, d, h, mi, s) = civil_from_unix(secs);
    format!("{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02}Z")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_dates() {
        assert_eq!(compact(0), "19700101T000000Z");
        assert_eq!(compact(951_782_400), "20000229T000000Z");
        assert_eq!(compact(1_794_698_471), "20261114T232111Z");
        assert_eq!(spaced(1_794_698_471), "2026-11-14 23:21:11Z");
        assert_eq!(compact(4_107_542_399), "21000228T235959Z");
        assert_eq!(compact(4_107_542_400), "21000301T000000Z");
        assert_eq!(compact(-1), "19691231T235959Z");
    }
}
