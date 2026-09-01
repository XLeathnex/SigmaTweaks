//! One error type for the whole backend.
//!
//! Every failure ends up in front of the user as a line in the activity log,
//! so the type is a message plus enough `From` impls that `?` works against
//! the standard library and the crates we call into.

use std::fmt;

#[derive(Debug, Clone, serde::Serialize)]
pub struct Error(pub String);

pub type Result<T> = std::result::Result<T, Error>;

impl Error {
    pub fn new(message: impl Into<String>) -> Self {
        Error(message.into())
    }

    /// Prefix an error with what was being attempted.
    pub fn context(self, what: &str) -> Self {
        Error(format!("{what}: {}", self.0))
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(value: std::io::Error) -> Self {
        Error(value.to_string())
    }
}

impl From<serde_json::Error> for Error {
    fn from(value: serde_json::Error) -> Self {
        Error(value.to_string())
    }
}

impl From<String> for Error {
    fn from(value: String) -> Self {
        Error(value)
    }
}

impl From<&str> for Error {
    fn from(value: &str) -> Self {
        Error(value.to_string())
    }
}

/// Attach context to a `Result` without pulling in anyhow.
pub trait Context<T> {
    fn context(self, what: &str) -> Result<T>;
}

impl<T, E: Into<Error>> Context<T> for std::result::Result<T, E> {
    fn context(self, what: &str) -> Result<T> {
        self.map_err(|e| e.into().context(what))
    }
}
