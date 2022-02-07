// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { Engine } from "./Engine.sol";

/// @title Utils library for fiveoutofnine (a 100% on-chain 6x6 chess engine)
/// @author fiveoutofnine
/// @dev Understand the representations of the chess pieces, board, and moves very carefully before
/// using this library:
/// ======================================Piece Representation======================================
/// Each chess piece is defined with 4 bits as follows:
///     * The first bit denotes the color (0 means black; 1 means white).
///     * The last 3 bits denote the type:
///         | Bits | # | Type   |
///         | ---- | - | ------ |
///         | 000  | 0 | Empty  |
///         | 001  | 1 | Pawn   |
///         | 010  | 2 | Bishop |
///         | 011  | 3 | Rook   |
///         | 100  | 4 | Knight |
///         | 101  | 5 | Queen  |
///         | 110  | 6 | King   |
/// ======================================Board Representation======================================
/// The board is an 8x8 representation of a 6x6 chess board. For efficiency, all information is
/// bitpacked into a single uint256. Thus, unlike typical implementations, board positions are
/// accessed via bit shifts and bit masks, as opposed to array accesses. Since each piece is 4 bits,
/// there are 64 ``indices'' to access:
///                                     63 62 61 60 59 58 57 56
///                                     55 54 53 52 51 50 49 48
///                                     47 46 45 44 43 42 41 40
///                                     39 38 37 36 35 34 33 32
///                                     31 30 29 28 27 26 25 24
///                                     23 22 21 20 19 18 17 16
///                                     15 14 13 12 11 10 09 08
///                                     07 06 05 04 03 02 01 00
/// All numbers in the figure above are in decimal representation.
/// For example, the piece at index 27 is accessed with ``(board >> (27 << 2)) & 0xF''.
///
/// The top/bottom rows and left/right columns are treated as sentinel rows/columns for efficient
/// boundary validation (see {Chess-generateMoves} and {Chess-isValid}). i.e., (63, ..., 56),
/// (07, ..., 00), (63, ..., 07), and (56, ..., 00) never contain pieces. Every bit in those rows
/// and columns should be ignored, except for the last bit. The last bit denotes whose turn it is to
/// play (0 means black's turn; 1 means white's turn). e.g. a potential starting position:
///                                Black
///                       00 00 00 00 00 00 00 00                    Black
///                       00 03 02 05 06 02 03 00                 ♜ ♝ ♛ ♚ ♝ ♜
///                       00 01 01 01 01 01 01 00                 ♟ ♟ ♟ ♟ ♟ ♟
///                       00 00 00 00 00 00 00 00     denotes
///                       00 00 00 00 00 00 00 00    the board
///                       00 09 09 09 09 09 09 00                 ♙ ♙ ♙ ♙ ♙ ♙
///                       00 11 12 13 14 12 11 00                 ♖ ♘ ♕ ♔ ♘ ♖
///                       00 00 00 00 00 00 00 01                    White
///                                White
/// All numbers in the example above are in decimal representation.
/// ======================================Move Representation=======================================
/// Each move is allocated 12 bits. The first 6 bits are the index the piece is moving from, and the
/// last 6 bits are the index the piece is moving to. Since the index representing a square is at
/// most 54, 6 bits sufficiently represents any index (0b111111 = 63 > 54). e.g. 1243 denotes a move
/// from index 19 to 27 (1243 = (19 << 6) | 27).
///
/// Since the board is represented by a uint256, consider including ``using Chess for uint256''.
library Chess {
    using Chess for uint256;
    using Chess for Chess.MovesArray;

    /// The depth, white's move, and black's move are bitpacked in that order as `metadata` for
    /// efficiency. As explained above, 12 bits sufficiently describe a move, so both white's and
    /// black's moves are allocated 12 bits each.
    struct Move {
        uint256 board;
        uint256 metadata;
    }

    /// ``moves'' are bitpacked into uint256s for efficiency. Since every move is defined by at most
    /// 12 bits, a uint256 can contain up to 21 moves via bitpacking (21 * 12 = 252 < 256).
    /// Therefore, `items` can contain up to 21 * 5 = 105 moves. 105 is a safe upper bound for the
    /// number of possible moves a given side may have during a real game, but be wary because there
    /// is no formal proof of the upper bound being less than or equal to 105.
    struct MovesArray {
        uint256 index;
        uint256[5] items;
    }

    /// @notice Takes in a board position, and applies the move `_move` to it.
    /// @dev After applying the move, the board's perspective is updated (see {rotate}). Thus,
    /// engines with symmterical search algorithms -- like negamax search -- probably work best.
    /// @param _board The board to apply the move to.
    /// @param _move The move to apply.
    /// @return The reversed board after applying `_move` to `_board`.
    function applyMove(uint256 _board, uint256 _move) internal pure returns (uint256) {
        unchecked {
            // Get piece at the from index
            uint256 piece = (_board >> ((_move >> 6) << 2)) & 0xF;
            // Replace 4 bits at the from index with 0000
            _board &= type(uint256).max ^ (0xF << ((_move >> 6) << 2));
            // Replace 4 bits at the to index with 0000
            _board &= type(uint256).max ^ (0xF << ((_move & 0x3F) << 2));
            // Place the piece at the to index
            _board |= (piece << ((_move & 0x3F) << 2));

            return _board.rotate();
        }
    }

    /// @notice Switches the perspective of the board by reversing its 4-bit subdivisions (e.g.
    /// 1100-0011 would become 0011-1100).
    /// @dev Since the last bit exchanges positions with the 4th bit, the turn identifier is updated
    /// as well.
    /// @param _board The board to reverse the perspective on.
    /// @return `_board` reversed.
    function rotate(uint256 _board) internal pure returns (uint256) {
        uint256 rotatedBoard;

        unchecked {
            for (uint256 i; i < 64; ++i) {
                rotatedBoard = (rotatedBoard << 4) | (_board & 0xF);
                _board >>= 4;
            }
        }

        return rotatedBoard;
    }

    /// @notice Generates all possible pseudolegal moves for a given position and color.
    /// @dev The last bit denotes which color to generate the moves for (see {Chess}). Also, the
    /// function errors if more than 105 moves are found (see {Chess-MovesArray}). All moves are
    /// expressed in code as shifts respective to the board's 8x8 representation (see {Chess}).
    /// @param _board The board position to generate moves for.
    /// @return Bitpacked uint256(s) containing moves.
    function generateMoves(uint256 _board) internal pure returns (uint256[5] memory) {
        Chess.MovesArray memory movesArray;
        uint256 move;
        uint256 moveTo;

        unchecked {
            // `0xDB5D33CB1BADB2BAA99A59238A179D71B69959551349138D30B289` is a mapping of indices
            // relative to the 6x6 board to indices relative to the 8x8 representation (see
            // {Chess-getAdjustedIndex}).
            for (
                uint256 index = 0xDB5D33CB1BADB2BAA99A59238A179D71B69959551349138D30B289;
                index != 0;
                index >>= 6
            ) {
                uint256 adjustedIndex = index & 0x3F;
                uint256 adjustedBoard = _board >> (adjustedIndex << 2);
                uint256 piece = adjustedBoard & 0xF;
                // Skip if square is empty or not the color of the board the function call is
                // analyzing.
                if (piece == 0 || piece >> 3 != _board & 1) continue;
                // The first bit can be discarded because the if statement above catches all
                // redundant squares.
                piece &= 7;

                if (piece == 1) { // Piece is a pawn.
                    // 1 square in front of the pawn is empty.
                    if ((adjustedBoard >> 0x20) & 0xF == 0) {
                        movesArray.append(adjustedIndex, adjustedIndex + 8);
                        // The pawn is in its starting row and 2 squares in front is empty. This
                        // must be nested because moving 2 squares would not be valid if there was
                        // an obstruction 1 square in front (i.e. pawns can not jump over pieces).
                        if (adjustedIndex >> 3 == 2 && (adjustedBoard >> 0x40) & 0xF == 0) {
                            movesArray.append(adjustedIndex, adjustedIndex + 0x10);
                        }
                    }
                    // Moving to the right diagonal by 1 captures a piece.
                    if (_board.isCapture(adjustedBoard >> 0x1C)) {
                        movesArray.append(adjustedIndex, adjustedIndex + 7); 
                    }
                    // Moving to the left diagonal by 1 captures a piece.
                    if (_board.isCapture(adjustedBoard >> 0x24)) {
                        movesArray.append(adjustedIndex, adjustedIndex + 9);
                    }
                } else if (piece > 3 && piece & 1 == 0) { // Piece is a knight or a king.
                    // Knights and kings always only have 8 positions to check relative to their
                    // current position, and the relative distances are always the same. For
                    // knights, positions to check are ±{6, 10, 15, 17}. This is bitpacked into
                    // `0x060A0F11` to reduce code redundancy. Similarly, the positions to check for
                    // kings are ±{1, 7, 8, 9}, which is `0x01070809` when bitpacked.
                    for (move = piece == 4 ? 0x060A0F11 : 0x01070809; move != 0; move >>= 8) {
                        if (_board.isValid(moveTo = adjustedIndex + (move & 0xFF))) {
                            movesArray.append(adjustedIndex, moveTo);
                        }
                        if (move <= adjustedIndex
                            && _board.isValid(moveTo = adjustedIndex - (move & 0xFF)))
                        {
                            movesArray.append(adjustedIndex, moveTo);
                        }
                    }
                } else {
                    // This else block generates moves for all sliding pieces. All of the 8 for
                    // loops terminate
                    //     * before a sliding piece makes an illegal move
                    //     * or after a sliding piece captures a piece.
                    if (piece != 2) { // Ortholinear pieces (i.e. rook and queen)
                        for (move = adjustedIndex + 1; _board.isValid(move); move += 1) {
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                        for (move = adjustedIndex - 1; _board.isValid(move); move -= 1) {
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                        for (move = adjustedIndex + 8; _board.isValid(move); move += 8) {
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                        for (move = adjustedIndex - 8; _board.isValid(move); move -= 8) {
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                    }
                    if (piece != 3) { // Diagonal pieces (i.e. bishop and queen)
                        for (move = adjustedIndex + 7; _board.isValid(move); move += 7) {
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                        for (move = adjustedIndex - 7; _board.isValid(move); move -= 7) {
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                        for (move = adjustedIndex + 9; _board.isValid(move); move += 9) {
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                        for (move = adjustedIndex - 9; _board.isValid(move); move -= 9) {
                            // Handles the edge case where a white bishop believes it can capture
                            // the ``piece'' at index 0, when it is actually the turn identifier It
                            // would mistakenly believe it is valid move via capturing a black pawn.
                            if (move == 0) break;
                            movesArray.append(adjustedIndex, move);
                            if (_board.isCapture(_board >> (move << 2))) break;
                        }
                    }
                }
            }
        }

        return movesArray.items;
    }

    /// @notice Determines whether a move is a legal move or not (includes checking whether king is
    /// checked or not after the move).
    /// @param _board The board to analyze.
    /// @param _move The move to check.
    /// @return Whether the move is legal or not.
    function isLegalMove(uint256 _board, uint256 _move) internal pure returns (bool) {
        unchecked {
            uint256 fromIndex = _move >> 6;
            uint256 toIndex = _move & 0x3F;
            if ((0x7E7E7E7E7E7E00 >> fromIndex) & 1 == 0) return false;
            if ((0x7E7E7E7E7E7E00 >> toIndex) & 1 == 0) return false;

            uint256 pieceAtFromIndex = (_board >> (fromIndex << 2)) & 0xF;
            if (pieceAtFromIndex == 0) return false;
            if (pieceAtFromIndex >> 3 != _board & 1) return false;
            pieceAtFromIndex &= 7;

            uint256 adjustedBoard = _board >> (toIndex << 2);
            uint256 indexChange = toIndex < fromIndex
                    ? fromIndex - toIndex
                    : toIndex - fromIndex;
            if (pieceAtFromIndex == 1) {
                if (toIndex <= fromIndex) return false;
                indexChange = toIndex - fromIndex;
                if ((indexChange == 7 || indexChange == 9)) {
                    if (!_board.isCapture(adjustedBoard)) return false;
                } else if (indexChange == 8) {
                    if (!isValid(_board, toIndex)) return false;
                } else if (indexChange == 0x10) {
                    if (!isValid(_board, toIndex - 8) || !isValid(_board, toIndex)) return false;
                } else {
                    return false;
                }
            } else if (pieceAtFromIndex == 4 || pieceAtFromIndex == 6) {
                if (((pieceAtFromIndex == 4 ? 0x28440 : 0x382) >> indexChange) & 1 == 0) {
                    return false;
                }
                if (!isValid(_board, toIndex)) return false;
            } else {
                bool rayFound;
                if (pieceAtFromIndex != 2) {
                    rayFound = searchRay(_board, fromIndex, toIndex, 1)
                        || searchRay(_board, fromIndex, toIndex, 8);
                }
                if (pieceAtFromIndex != 3) {
                    rayFound = rayFound
                        || searchRay(_board, fromIndex, toIndex, 7)
                        || searchRay(_board, fromIndex, toIndex, 9);
                }
                if (!rayFound) return false;
            }

            if (Engine.negaMax(_board.applyMove(_move), 1) < -1_260) return false;

            return true;
        }
    }

    /// @notice Determines whether there is a clear path along a direction vector from one index to
    /// another index on the board.
    /// @dev The board's representation essentially flattens it from 2D to 1D, so `_directionVector`
    /// should be the change in index that represents the direction vector.
    /// @param _board The board to analyze.
    /// @param _fromIndex The index of the starting piece.
    /// @param _toIndex The index of the ending piece.
    /// @param _directionVector The direction vector of the ray.
    /// @return Whether there is a clear path between `_fromIndex` and `_toIndex` or not.
    function searchRay(
        uint256 _board,
        uint256 _fromIndex,
        uint256 _toIndex,
        uint256 _directionVector
    )
        internal pure
        returns (bool)
    {
        unchecked {
            uint256 indexChange;
            uint256 rayStart;
            uint256 rayEnd;
            if (_fromIndex < _toIndex) {
                indexChange = _toIndex - _fromIndex;
                rayStart = _fromIndex + _directionVector;
                rayEnd = _toIndex;
            } else {
                indexChange = _fromIndex - _toIndex;
                rayStart = _toIndex;
                rayEnd = _fromIndex - _directionVector;
            }
            if (indexChange % _directionVector != 0) return false;

            for (
                rayStart = rayStart;
                rayStart < rayEnd;
                rayStart += _directionVector
            ) {
                if (!isValid(_board, rayStart)) return false;
                if (isCapture(_board, _board >> (rayStart << 2))) return false;
            }

            if (!isValid(_board, rayStart)) return false;

            return rayStart == rayEnd;
        }
    }

    /// @notice Determines whether a move results in a capture or not.
    /// @param _board The board prior to the potential capture.
    /// @param _indexAdjustedBoard The board bitshifted to the to index to consider.
    /// @return Whether the move is a capture or not.
    function isCapture(uint256 _board, uint256 _indexAdjustedBoard) internal pure returns (bool) {
        unchecked {
            return (_indexAdjustedBoard & 0xF) != 0 // The square is not empty.
                && (_indexAdjustedBoard & 0xF) >> 3 != _board & 1; // The piece is opposite color.
        }
    }

    /// @notice Determines whether a move is valid or not (i.e. within bounds and not capturing
    /// same colored piece).
    /// @dev As mentioned above, the board representation has 2 sentinel rows and columns for
    /// efficient boundary validation as follows:
    ///                                           0 0 0 0 0 0 0 0
    ///                                           0 1 1 1 1 1 1 0
    ///                                           0 1 1 1 1 1 1 0
    ///                                           0 1 1 1 1 1 1 0
    ///                                           0 1 1 1 1 1 1 0
    ///                                           0 1 1 1 1 1 1 0
    ///                                           0 1 1 1 1 1 1 0
    ///                                           0 0 0 0 0 0 0 0,
    /// where 1 means a piece is within the board, and 0 means the piece is out of bounds. The bits
    /// are bitpacked into a uint256 (i.e. ``0x7E7E7E7E7E7E00 = 0 << 63 | ... | 0 << 0'') for
    /// efficiency.
    ///
    /// Moves that overflow the uint256 are computed correctly because bitshifting more than bits
    /// available results in 0. However, moves that underflow the uint256 (i.e. applying the move
    /// results in a negative index) must be checked beforehand.
    /// @param _board The board on which to consider whether the move is valid.
    /// @param _toIndex The to index of the move.
    /// @return Whether the move is valid or not.
    function isValid(uint256 _board, uint256 _toIndex) internal pure returns (bool) {
        unchecked {
            return (0x7E7E7E7E7E7E00 >> _toIndex) & 1 == 1 // Move is within bounds.
                && ((_board >> (_toIndex << 2)) & 0xF == 0 // Square is empty.
                    || (((_board >> (_toIndex << 2)) & 0xF) >> 3) != _board & 1); // Piece captured.
        }
    }

    /// @notice Maps an index relative to the 6x6 board to the index relative to the 8x8
    /// representation.
    /// @dev The indices are mapped as follows:
    ///                           35 34 33 32 31 30              54 53 52 51 50 49
    ///                           29 28 27 26 25 24              46 45 44 43 42 41
    ///                           23 22 21 20 19 18    mapped    38 37 36 35 34 33
    ///                           17 16 15 14 13 12      to      30 29 28 27 26 25
    ///                           11 10 09 08 07 06              22 21 20 19 18 17
    ///                           05 04 03 02 01 00              14 13 12 11 10 09
    /// All numbers in the figure above are in decimal representation. The bits are bitpacked into a
    /// uint256 (i.e. ``0xDB5D33CB1BADB2BAA99A59238A179D71B69959551349138D30B289 = 54 << (6 * 35) |
    /// ... | 9 << (6 * 0)'') for efficiency.
    /// @param _index Index relative to the 6x6 board.
    /// @return Index relative to the 8x8 representation.
    function getAdjustedIndex(uint256 _index) internal pure returns (uint256) {
        unchecked {
            return (
                (0xDB5D33CB1BADB2BAA99A59238A179D71B69959551349138D30B289 >> (_index * 6)) & 0x3F
            );
        }
    }

    /// @notice Appends a move to a {Chess-MovesArray} object.
    /// @dev Since each uint256 fits at most 21 moves (see {Chess-MovesArray}), {Chess-append}
    /// bitpacks 21 moves per uint256 before moving on to the next uint256.
    /// @param _movesArray {Chess-MovesArray} object to append the new move to.
    /// @param _fromMoveIndex Index the piece moves from.
    /// @param _toMoveIndex Index the piece moves to.
    function append(MovesArray memory _movesArray, uint256 _fromMoveIndex, uint256 _toMoveIndex)
        internal pure
    {
        unchecked {
            uint256 currentIndex = _movesArray.index;
            uint256 currentPartition = _movesArray.items[currentIndex];

            if (currentPartition > (1 << 0xF6)) {
                _movesArray.items[++_movesArray.index] = (_fromMoveIndex << 6) | _toMoveIndex;
            } else {
                _movesArray.items[currentIndex] = (currentPartition << 0xC)
                    | (_fromMoveIndex << 6)
                    | _toMoveIndex;
            }
        }
    }
}
