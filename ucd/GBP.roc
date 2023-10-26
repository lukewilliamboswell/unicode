app "gen"
    packages { 
        pf: "https://github.com/roc-lang/basic-cli/releases/download/0.5.0/Cufzl36_SnJ4QbOoEmiJ5dIpUxBvdB3NEySvuH82Wio.tar.br",
        # parser: "https://github.com/lukewilliamboswell/roc-parser/releases/download/0.1.0/vPU-UZbWGIXsAfcJvAnmU3t3SWlHoG_GauZpqzJiBKA.tar.br",
    }
    imports [
        pf.Stdout, 
        pf.Stderr, 
        pf.Task.{ Task },
        pf.Path.{Path },
        pf.Arg,
        pf.File,
        "GraphemeBreakProperty-15.1.0.txt" as gbpFile : Str,
        # "InternalGBP.roc" as template : Str,
    ]
    provides [main] to pf

CodePoint : U32
GraphemeBreakProperty : [
    CR,
    LF, 
    Control,
    Extend,
    ZWJ,
    RI,
    Prepend,
    SpacingMark,
    RegionalIndicator,
    L,
    V,
    T,
    LV,
    LVT,
    Other,
]

main : Task {} I32
main =
    getFilePath 
    |> Task.await writeToFile 
    |> Task.onErr \err -> Stderr.line "\(err)"

# TASKS

getFilePath : Task Path Str
getFilePath = 
    args <- Arg.list |> Task.await

    when args |> List.get 1 is 
        Ok arg -> Task.ok (Path.fromStr "\(removeTrailingSlash arg)/InternalGBP.roc")
        Err _ -> Task.err "USAGE: roc run InternalGBP.roc -- path/to/package/"

writeToFile : Path -> Task {} Str 
writeToFile = \path ->
    File.writeUtf8 path lines
    |> Task.mapErr \_ -> "ERROR: unable to write to \(Path.display path)"
    |> Task.await \_ -> Stdout.line "\nSucessfully wrote to \(Path.display path)\n"

# PROCESS FILE

lines = 
    gbpFile
    |> Str.split  "\n"
    |> List.keepOks startsWithHex
    |> List.map \l -> 
        when Str.split l ";" is 
            [hexPart, propPart] -> 
                when (parseHexPart hexPart, parsePropPart propPart) is 
                    (Ok cp, Ok prop) -> (cp, prop)
                    _ -> crash "Error parsing line -- \(l)"
            _ -> crash "Error unexpected ';' on line -- \(l)"
    |> List.map \(cp, _) -> 
        when cp is 
            Single _ -> "got single"
            Range _ _ -> "got double"
    |> Str.joinWith "\n"

parseHexPart : Str -> Result [Single CodePoint, Range CodePoint CodePoint] [ParsingError]
parseHexPart = \hexPart ->
    when hexPart |> Str.trim |> Str.split ".." is 
        [single] -> 
            when codePointParser single is 
                Ok a -> Ok (Single a )
                Err _ -> Err ParsingError
        [start, end] -> 
            when (codePointParser start, codePointParser end) is 
                (Ok a, Ok b) -> Ok (Range a b)
                _ -> Err ParsingError
        _ -> Err ParsingError

expect parseHexPart "0890..0891    " == Ok (Range 2192 2193)
expect parseHexPart "08E2          " == Ok (Single 2274)

parsePropPart : Str -> Result GraphemeBreakProperty [ParsingError]
parsePropPart = \str -> 
    when Str.split str "#" is 
        [propStr, ..] -> graphemePropertyParser (Str.trim propStr)
        _ -> Err ParsingError 
        
expect parsePropPart " Prepend # Cf   [6] ARABIC NUMBER SIGN..ARABIC NUMBER MARK ABOVE" == Ok Prepend
expect parsePropPart " CR # Cc       <control-000D>" == Ok CR
expect parsePropPart " Regional_Indicator # So  [26] REGIONAL INDICATOR SYMBOL LETTER A..REGIONAL INDICATOR SYMBOL LETTER Z" == Ok RegionalIndicator

# HELPERS

startsWithHex : Str -> Result Str [NonHex]
startsWithHex = \str ->
    when Str.toUtf8 str is 
        [a, ..] if isHex a -> Ok str
        _ -> Err NonHex

expect startsWithHex "# ===" == Err NonHex
expect startsWithHex "0000.." == Ok "0000.."

removeTrailingSlash : Str -> Str
removeTrailingSlash = \str ->
    trimmed = str |> Str.trim
    reversed = trimmed |> Str.toUtf8 |> List.reverse
    
    when reversed is 
        [a, ..] if a == '/' -> 
            reversed 
            |> List.drop 1 
            |> List.reverse 
            |> Str.fromUtf8 
            |> Result.withDefault "" 
        _ -> trimmed

expect removeTrailingSlash "abc  " == "abc"
expect removeTrailingSlash "  abc/package/  " == "abc/package"

props : List {bytes : List U8, property : GraphemeBreakProperty}
props =
    # NOTE ordering matters here, e.g. L after LV and LVT
    # to match on longest first
    [
        { bytes: Str.toUtf8 "CR", property: CR},
        { bytes: Str.toUtf8 "Control", property: Control},
        { bytes: Str.toUtf8 "Extend", property: Extend},
        { bytes: Str.toUtf8 "ZWJ", property: ZWJ},
        { bytes: Str.toUtf8 "RI", property: RI},
        { bytes: Str.toUtf8 "Prepend", property: Prepend},
        { bytes: Str.toUtf8 "SpacingMark", property: SpacingMark},
        { bytes: Str.toUtf8 "V", property: V},
        { bytes: Str.toUtf8 "T", property: T},
        { bytes: Str.toUtf8 "LF", property: LF}, 
        { bytes: Str.toUtf8 "LVT", property: LVT},
        { bytes: Str.toUtf8 "LV", property: LV},
        { bytes: Str.toUtf8 "L", property: L},
        { bytes: Str.toUtf8 "Other", property: Other},
        { bytes: Str.toUtf8 "Regional_Indicator", property: RegionalIndicator},
    ]

graphemePropertyParser : Str -> Result GraphemeBreakProperty [ParsingError]
graphemePropertyParser = \input ->

    startsWithProp : { bytes : List U8, property : GraphemeBreakProperty} -> Result GraphemeBreakProperty [NonGBP]
    startsWithProp = \prop -> 
        if input |> Str.toUtf8 |> List.startsWith prop.bytes then 
            Ok prop.property 
        else 
            Err NonGBP

    # see which properties match 
    matches : List GraphemeBreakProperty
    matches = props |> List.keepOks startsWithProp

    when matches is # take the longest match
        [a, ..] -> Ok a 
        _ -> Err ParsingError

expect graphemePropertyParser "L" == Ok L
expect graphemePropertyParser "LF" == Ok LF
expect graphemePropertyParser "LV" == Ok LV
expect graphemePropertyParser "LVT" == Ok LVT
expect graphemePropertyParser "Other" == Ok Other
expect graphemePropertyParser "# ===" == Err ParsingError

codePointParser : Str -> Result CodePoint [ParsingError]
codePointParser = \input ->

    { val: hexBytes } = takeHexBytes {val: [], rest: Str.toUtf8 input}

    when hexBytes is
        [] -> Err ParsingError
        _ -> Ok (hexBytesToU32 hexBytes)

expect codePointParser "0000" == Ok 0
expect codePointParser "16FF1" == Ok 94193
expect codePointParser "# ===" == Err ParsingError

hexBytesToU32 : List U8 -> CodePoint
hexBytesToU32 = \bytes ->
    bytes 
    |> List.reverse 
    |> List.walkWithIndex 0 \accum, byte, i -> accum + (Num.powInt 16 (Num.toU32 i))*(hexToDec byte)
    |> Num.toU32

expect hexBytesToU32 ['0', '0', '0', '0'] == 0
expect hexBytesToU32 ['0', '0', '0', '1'] == 1
expect hexBytesToU32 ['0', '0', '0', 'F'] == 15
expect hexBytesToU32 ['0', '0', '1', '0'] == 16
expect hexBytesToU32 ['0', '0', 'F', 'F'] == 255
expect hexBytesToU32 ['0', '1', '0', '0'] == 256
expect hexBytesToU32 ['0', 'F', 'F', 'F'] == 4095
expect hexBytesToU32 ['1', '0', '0', '0'] == 4096
expect hexBytesToU32 ['1', '6', 'F', 'F', '1'] == 94193

takeHexBytes : { val : List U8, rest : List U8} -> { val : List U8, rest : List U8}
takeHexBytes = \input ->
    when input.rest is 
        [] -> input 
        [first, ..] -> 
            if first |> isHex then 
                # take the first hex byte and continue 
                takeHexBytes { 
                    val :  input.val |> List.append first, 
                    rest : input.rest |> List.drop 1,
                }
            else 
                input

expect 
    bytes = [35, 32, 61, 61, 61] # "# ==="
    takeHexBytes {val: [], rest: bytes} == {val: [], rest: bytes} 

expect 
    bytes = [68, 54, 69, 49, 46, 46, 68, 54, 70, 66, 32, 32] # "D6E1..D6FB  "
    takeHexBytes {val: [], rest: bytes} == {val: [68, 54, 69, 49], rest: [46, 46, 68, 54, 70, 66, 32, 32]}

isHex : U8 -> Bool
isHex = \u8 ->
    u8 == '0' ||
    u8 == '1' ||
    u8 == '2' ||
    u8 == '3' ||
    u8 == '4' ||
    u8 == '5' ||
    u8 == '6' ||
    u8 == '7' ||
    u8 == '8' ||
    u8 == '9' ||
    u8 == 'A' ||
    u8 == 'B' ||
    u8 == 'C' ||
    u8 == 'D' ||
    u8 == 'E' ||
    u8 == 'F'

expect isHex '0'
expect isHex 'A'
expect isHex 'F'
expect !(isHex ';')
expect !(isHex '#')

hexToDec : U8 -> U32
hexToDec = \byte ->
    when byte is
        '0' -> 0
        '1' -> 1
        '2' -> 2
        '3' -> 3
        '4' -> 4
        '5' -> 5
        '6' -> 6
        '7' -> 7
        '8' -> 8
        '9' -> 9
        'A' -> 10
        'B' -> 11
        'C' -> 12
        'D' -> 13
        'E' -> 14
        'F' -> 15
        _ -> 0

expect hexToDec '0' == 0
expect hexToDec 'F' == 15