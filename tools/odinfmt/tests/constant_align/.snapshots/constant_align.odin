package odinfmt_test

// Basic constant alignment
SCREEN_WIDTH  :: 800
SCREEN_HEIGHT :: 450

// Separate group after blank line
PLAYER_POS_X :: 10
PLAYER_POS_Y :: 100

// Mixed: mutable and constant should not be grouped
x := 10
Y :: 20
z := 30

// Single constant (no alignment needed)
LONELY :: 42

// Constants with varying name lengths
A                       :: 1
VERY_LONG_CONSTANT_NAME :: 2
B                       :: 3

// Type-annotated constants should be aligned with each other
TYPED_CONST  : int : 100
ANOTHER_TYPED: int : 200

// Mixed: typed and non-typed should not be aligned together
X :: 10
Y: int : 20
Z :: 30

// Type-annotated constants with varying name lengths
SHORT         : int : 1
VERY_LONG_NAME: int : 2
MEDIUM        : int : 3
