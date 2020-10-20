# Unfold
WIP modding tool for the [Defold game engine](https://defold.com/).

## Current Features
- Export assets

## Planned Features
- Import assets
- Decompile/recompile assets
  - Requires a [native extension](https://defold.com/manuals/extensions/) version of [lua-lz4](https://github.com/witchu/lua-lz4)
- Mod loading

## Installation
Grab a pre-built version from the [releases section](https://github.com/JustAPotota/Unfold/releases) or download the project and build it using Defold.

# Archive Format
Below is everything I know about Defold's archive format, for those who want to contribute or are just curious.

## game.arcd
Contains the actual data of the game files and not much else.


## game.arci
The archive index. It's a binary file with a header, a list of hashes of each file, and a list of data about each file.

### Header Format
| Offset | Size | Description |
|--------|------|-------------|
| 0x0    | 0x4  | Index version. It's 4 at the time of writing |
| 0x4    | 0x4  | Padding                                        |
| 0x8    | 0x8  | "UserData, used in runtime to distinguish between if the index and resources are memory mapped or loaded from disk", according to the [source code](https://github.com/defold/defold/blob/c8987e4f119497aaee90afd8c99f464881a8e140/com.dynamo.cr/com.dynamo.cr.bob/src/com/dynamo/bob/archive/ArchiveBuilder.java#L172). Not sure what this means |
| 0x10   | 0x4  | The number of entries in the index             |
| 0x14   | 0x4  | Starting offset of the entry list              |
| 0x16   | 0x4  | Starting offset of the hash list               |
| 0x1a   | 0x4  | The length of each hash                        |
| 0x1e   | ???  | The MD5 hash of the index file. Its length is determined by [MD5_HASH_DIGEST_BYTE_LENGTH](https://github.com/defold/defold/blob/9991d949988c4da04f08b1aed386425035cdae3c/com.dynamo.cr/com.dynamo.cr.bob/src/com/dynamo/bob/archive/ArchiveBuilder.java#L46) (0x10 at the time of writing) |

### Hash Format
These are hashes whose lengths are defined in the index header. Each hash is stored in a block of size [HASH_MAX_LENGTH](https://github.com/defold/defold/blob/9991d949988c4da04f08b1aed386425035cdae3c/com.dynamo.cr/com.dynamo.cr.bob/src/com/dynamo/bob/archive/ArchiveBuilder.java#L44), the rest of the space gets filled in with zeros. The hash algorithm used is defined by the manifest header. Hashes seem to only be used as an identifier, not to check that the files are valid.

### Entry Format
| Offset | Size | Description |
|--------|------|-------------|
| 0x0    | 0x4  | Offset of the file data in game.arcd |
| 0x4    | 0x4  | Uncompressed size of the file |
| 0x8    | 0x4  | Compressed size of the file (0xFFFFFFFF if not compressed) |
| 0xc    | 0x4  | Archive entry flags (see below) |

#### Archive Entry Flags
```
00000000 00000000 00000000 00000000
                                ||| Encrypted
                                || Compressed
                                | Live update
```

## game.dmanifest
This is simply a compiled [Google protobuf](https://developers.google.com/protocol-buffers/) file. The definition file is easy to read, so go check it out [here](https://github.com/defold/defold/blob/9991d949988c4da04f08b1aed386425035cdae3c/engine/resource/proto/liveupdate_ddf.proto).
