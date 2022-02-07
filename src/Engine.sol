// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import { Chess } from "./Chess.sol";

/// @title A 6x6 chess engine with negamax search
/// @author fiveoutofnine
/// @notice Docstrings below are written from the perspective of black (i.e. written as if the
/// engine is always black). However, due to negamax's symmetric nature, the engine may be used for
/// white as well.
library Engine {
    using Chess for uint256;
    using Engine for uint256;

    /// @notice Searches for the ``best'' move.
    /// @dev The ply depth must be at least 3 because game ending scenarios are determined lazily.
    /// This is because {generateMoves} generates pseudolegal moves. Consider the following:
    ///     1. In the case of white checkmates black, depth 2 is necessary:
    ///         * Depth 1: This is the move black plays after considering depth 2.
    ///         * Depth 2: Check whether white captures black's king within 1 turn for every such
    ///           move. If so, white has checkmated black.
    ///     2. In the case of black checkmates white, depth 3 is necessary:
    ///         * Depth 1: This is the move black plays after considering depths 2 and 3.
    ///         * Depth 2: Generate all pseudolegal moves for white in response to black's move.
    ///         * Depth 3: Check whether black captures white's king within 1 turn for every such
    ///         * move. If so, black has checkmated white.
    /// The minimum depth required to cover all the cases above is 3. For simplicity, stalemates
    /// are treated as checkmates.
    ///
    /// The function returns 0 if the game is over after white's move (no collision with any
    /// potentially real moves because 0 is not a valid index), and returns true if the game is over
    /// after black's move.
    /// @param _board The board position to analyze.
    /// @param _depth The ply depth to analyze to. Must be at least 3.
    /// @return The best move for the player (denoted by the last bit in `_board`).
    /// @return Whether white is checkmated or not.
    function searchMove(uint256 _board, uint256 _depth) internal pure returns (uint256, bool) {
        uint256[5] memory moves = _board.generateMoves();
        if (moves[0] == 0) return (0, false);
        // See {Engine-negaMax} for explanation on why `bestScore` is set to -4_196.
        int256 bestScore = -4_196;
        int256 currentScore;
        uint256 bestMove;

        unchecked {
            for (uint256 i; moves[i] != 0; ++i) {
                for (uint256 movePartition = moves[i]; movePartition != 0; movePartition >>= 0xC) {
                    currentScore = _board.evaluateMove(movePartition & 0xFFF)
                        + negaMax(_board.applyMove(movePartition & 0xFFF), _depth - 1);
                    if (currentScore > bestScore) {
                        bestScore = currentScore;
                        bestMove = movePartition & 0xFFF;
                    }
                }
            }
        }

        // 1_260 is equivalent to 7 queens (7 * 180 = 1260). Since a king's capture is equivalent to
        // an evaluation of 4_000, ±1_260 catches all lines that include the capture of a king.
        if (bestScore < -1_260) return (0, false);
        return (bestMove, bestScore > 1_260);
    }

    /// @notice Searches and evaluates moves using a variant of the negamax search algorithm.
    /// @dev For efficiency, the function evaluates how good moves are and sums them up, rather than
    /// evaluating entire board positions. Thus, the only pruning the algorithm performs is when a
    /// king is captured. If a king is captured, it always returns -4,000, which is the king's value
    /// (see {Chess}) because there is nothing more to consider.
    /// @param _board The board position to analyze.
    /// @param _depth The ply depth to analyze to.
    /// @return The cumulative score searched to a ply depth of `_depth`, assuming each side picks
    /// their ``best'' (as decided by {Engine-evaluateMove}) moves.
    function negaMax(uint256 _board, uint256 _depth) internal pure returns (int256) {
        // Base case for the recursion.
        if (_depth == 0) return 0;
        uint256[5] memory moves = _board.generateMoves();
        // There is no ``best'' score if there are no moves to play.
        if (moves[0] == 0) return 0;
        // `bestScore` is initially set to -4_196 because no line will result in a cumulative
        // evaluation of <-4_195. -4_195 occurs, for example. when the engine's king is captured
        // (-4000), and the player captures an engine's queen on index 35 (-181) with knight from
        // index 52 (-14).
        int256 bestScore = -4_196;
        int256 currentScore;
        uint256 bestMove;

        unchecked {
            for (uint256 i; moves[i] != 0; ++i) {
                for (uint256 movePartition = moves[i]; movePartition != 0; movePartition >>= 0xC) {
                    currentScore = _board.evaluateMove(movePartition & 0xFFF);
                    if (currentScore > bestScore) {
                        bestScore = currentScore;
                        bestMove = movePartition & 0xFFF;
                    }
                }
            }

            // If a king is captured, stop the recursive call stack and return a score of -4_000.
            // There is nothing more to consider.
            if (((_board >> ((bestMove & 0x3F) << 2)) & 7) == 6) return -4_000;
            return _board & 1 == 0
                ? bestScore + negaMax(_board.applyMove(bestMove), _depth - 1)
                : -bestScore + negaMax(_board.applyMove(bestMove), _depth - 1);
        }
    }

    /// @notice Uses piece-square tables (PSTs) to evaluate how ``good'' a move is.
    /// @dev The PSTs were selected semi-arbitrarily with chess strategies in mind (e.g. pawns are
    /// good in the center). Updating them changes the way the engine ``thinks.'' Each piece's PST
    /// is bitpacked into as few uint256s as possible for efficiency (see {Engine-getPst} and
    /// {Engine-getPstTwo}):
    ///          Pawn                Bishop               Knight                   Rook
    ///    20 20 20 20 20 20    62 64 64 64 64 62    54 56 54 54 56 58    100 100 100 100 100 100
    ///    30 30 30 30 30 30    64 66 66 66 66 64    56 60 64 64 60 56    101 102 102 102 102 101
    ///    20 22 24 24 22 20    64 67 68 68 67 64    58 64 68 68 64 58     99 100 100 100 100  99
    ///    21 20 26 26 20 21    64 68 68 68 68 64    58 65 68 68 65 58     99 100 100 100 100  99
    ///    21 30 16 16 30 21    64 67 66 66 67 64    56 60 65 65 60 56     99 100 100 100 100  99
    ///    20 20 20 20 20 20    62 64 64 64 64 62    54 56 58 58 56 54    100 100 101 101 100 100
    ///                            Queen                         King
    ///                   176 178 179 179 178 176    3994 3992 3990 3990 3992 3994
    ///                   178 180 180 180 180 178    3994 3992 3990 3990 3992 3994
    ///                   179 180 181 181 180 179    3996 3994 3992 3992 3994 3995
    ///                   179 181 181 181 180 179    3998 3996 3996 3996 3996 3998
    ///                   178 180 181 180 180 178    4001 4001 4000 4000 4001 4001
    ///                   176 178 179 179 178 176    4004 4006 4002 4002 4006 4004
    /// All entries in the figure above are in decimal representation.
    ///
    /// Each entry in the pawn's, bishop's, knight's, and rook's PSTs uses 7 bits, and each entry in
    /// the queen's and king's PSTs uses 12 bits. Additionally, each piece is valued as following:
    ///                                      | Type   | Value |
    ///                                      | ------ | ----- |
    ///                                      | Pawn   | 20    |
    ///                                      | Bishop | 66    |
    ///                                      | Knight | 64    |
    ///                                      | Rook   | 100   |
    ///                                      | Queen  | 180   |
    ///                                      | King   | 4000  |
    /// The king's value just has to be sufficiently larger than 180 * 7 = 1260 (i.e. equivalent to
    /// 7 queens) because check/checkmates are detected lazily (see {Engine-generateMoves}).
    ///
    /// The evaluation of a move is given by
    ///                Δ(PST value of the moved piece) + (PST value of any captured pieces).
    /// @param _board The board to apply the move to.
    /// @param _move The move to evaluate.
    /// @return The evaluation of the move applied to the given position.
    function evaluateMove(uint256 _board, uint256 _move) internal pure returns (int256) {
        unchecked {
            uint256 fromIndex = 6 * (_move >> 9) + ((_move >> 6) & 7) - 7;
            uint256 toIndex = 6 * ((_move & 0x3F) >> 3) + ((_move & 0x3F) & 7) - 7;
            uint256 pieceAtFromIndex = (_board >> ((_move >> 6) << 2)) & 7;
            uint256 pieceAtToIndex = (_board >> ((_move & 0x3F) << 2)) & 7;
            uint256 oldPst;
            uint256 newPst;
            uint256 captureValue;

            if (pieceAtToIndex != 0) {
                if (pieceAtToIndex < 5) { // Piece is not a queen or king
                    captureValue = (getPst(pieceAtToIndex) >> (7 * (0x23 - toIndex))) & 0x7F;
                } else if (toIndex < 0x12) { // Piece is queen or king and in the closer half
                    captureValue = (getPst(pieceAtToIndex) >> (0xC * (0x11 - toIndex))) & 0xFFF;
                } else { // Piece is queen or king and in the further half
                    captureValue = (getPstTwo(pieceAtToIndex) >> (0xC * (0x23 - toIndex))) & 0xFFF;
                }
            }
            if (pieceAtFromIndex < 5) { // Piece is not a queen or king
                oldPst = (getPst(pieceAtFromIndex) >> (7 * fromIndex)) & 0x7F;
                newPst = (getPst(pieceAtFromIndex) >> (7 * toIndex)) & 0x7F;
            } else if (fromIndex < 0x12) { // Piece is queen or king and in the closer half
                oldPst = (getPstTwo(pieceAtFromIndex) >> (0xC * fromIndex)) & 0xFFF;
                newPst = (getPstTwo(pieceAtFromIndex) >> (0xC * toIndex)) & 0xFFF;
            } else { // Piece is queen or king and in the further half
                oldPst = (getPst(pieceAtFromIndex) >> (0xC * (fromIndex - 0x12))) & 0xFFF;
                newPst = (getPst(pieceAtFromIndex) >> (0xC * (toIndex - 0x12))) & 0xFFF;
            }

            return int256(captureValue + newPst) - int256(oldPst);
        }
    }

    /// @notice Maps a given piece type to its PST (see {Engine-evaluateMove} for details on the
    /// PSTs and {Chess} for piece representation).
    /// @dev The queen's and king's PSTs do not fit in 1 uint256, so their PSTs are split into 2
    /// uint256s each. {Chess-getPst} contains the first half, and {Chess-getPstTwo} contains the
    /// second half.
    /// @param _type A piece type defined in {Chess}.
    /// @return The PST corresponding to `_type`.
    function getPst(uint256 _type) internal pure returns (uint256) {
        if (_type == 1) return 0x2850A142850F1E3C78F1E2858C182C50A943468A152A788103C54A142850A14;
        if (_type == 2) return 0x7D0204080FA042850A140810E24487020448912240810E1428701F40810203E;
        if (_type == 3) return 0xC993264C9932E6CD9B365C793264C98F1E4C993263C793264C98F264CB97264;
        if (_type == 4) return 0x6CE1B3670E9C3C8101E38750224480E9D4189120BA70F20C178E1B3874E9C36;
        if (_type == 5) return 0xB00B20B30B30B20B00B20B40B40B40B40B20B30B40B50B50B40B3;
        return 0xF9AF98F96F96F98F9AF9AF98F96F96F98F9AF9CF9AF98F98F9AF9B;
    }

    /// @notice Maps a queen or king to the second half of its PST (see {Engine-getPst}).
    /// @param _type A piece type defined in {Chess}. Must be a queen or a king (see
    /// {Engine-getPst}).
    /// @return The PST corresponding to `_type`.
    function getPstTwo(uint256 _type) internal pure returns (uint256) {
        return _type == 5
            ? 0xB30B50B50B50B40B30B20B40B50B40B40B20B00B20B30B30B20B0
            : 0xF9EF9CF9CF9CF9CF9EFA1FA1FA0FA0FA1FA1FA4FA6FA2FA2FA6FA4;
    }
}
