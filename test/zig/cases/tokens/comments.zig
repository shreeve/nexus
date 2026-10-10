// a plain comment
//
// a comment with a / and a // inside
/// a doc comment
///
///a doc comment without a space
//// four slashes: a plain comment
/////
//! a container doc comment
//!
//!! two bangs
//!/ bang slash
/// Ã© â€¨ UTF-8 in a doc comment
// ÿ€ any bytes from 0x80 in a comment
x // trailing comment
y /// trailing doc comment
z //! trailing container doc comment
a / b /= c
// at the end of input