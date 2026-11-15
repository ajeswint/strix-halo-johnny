//! A `STOP-<token>`: the daemon exits 1 and prints this token on stderr.

use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stop(pub String);

impl fmt::Display for Stop {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "STOP-{}", self.0)
    }
}

#[macro_export]
macro_rules! stop {
    ($($arg:tt)*) => {
        $crate::stop::Stop(format!($($arg)*))
    };
}
