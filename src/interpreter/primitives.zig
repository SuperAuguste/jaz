pub const @"null" = void;

pub const byte = i8;
pub const short = i16;
pub const int = i32;
pub const long = i64;
pub const char = u16;
pub const boolean = bool;

pub const float = f32;
pub const double = f64;

pub const reference = usize;
pub const returnAddress = usize;

pub const PrimitiveValue = union(enum) {
    @"null": @"null",
    @"void": void,
    
    byte: byte,
    short: short,
    int: int,
    long: long,
    char: char,
    boolean: boolean, // NOTE: All boolean operations are mapped to int when operated on (0, 1)

    float: float,
    double: double,

    reference: reference,
    returnAddress: returnAddress
};