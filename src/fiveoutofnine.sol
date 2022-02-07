// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import { Chess } from "./Chess.sol";
import { Engine } from "./Engine.sol";
import { fiveoutofnineART } from "./fiveoutofnineART.sol";

/// @title fiveoutofnine NFT - the first 100% on-chain chess engine.
/// @author fiveoutofnine
/// @notice This file has few docstrings (by choice) because most of it is standard. Refer to
/// {Chess}, {Engine}, and {fiveoutofnineART} for thorough documentation.
contract fiveoutofnine is ERC721, Ownable, ReentrancyGuard {
    using Chess for uint256;
    using Strings for uint256;

    uint256 public board;
    uint256 private internalId;

    mapping(uint256 => uint256) public tokenInternalIds;
    mapping(uint256 => Chess.Move) public tokenMoves;

    uint256 public totalSupply;
    string private baseURI;

    constructor() ERC721("fiveoutofnine", unicode"♞") {
        /* honorableMints();
        board = 0x32562300110101000010010000000C0099999000BCDE0B000000001;
        internalId = (1 << 0x80) | 2;
        totalSupply = 11; */
        board = 0x500000000000000000000e000000000003000000000000000000001;
    }

    function mintMove(uint256 _move, uint256 _depth) external payable nonReentrant {
        require(_depth >= 3 && _depth <= 10);
        require((internalId >> 0x80) < 59 && uint128(internalId) < 59);

        playMove(_move, _depth);
        _safeMint(msg.sender, totalSupply++);
    }

    function playMove(uint256 _move, uint256 _depth) internal {
        unchecked {
            uint256 inMemoryBoard = board;
            require(inMemoryBoard.isLegalMove(_move));

            inMemoryBoard = inMemoryBoard.applyMove(_move);
            (uint256 bestMove, bool isWhiteCheckmated) = Engine.searchMove(inMemoryBoard, _depth);

            tokenInternalIds[totalSupply] = internalId++;
            tokenMoves[totalSupply] = Chess.Move(board, (_depth << 24) | (_move << 12) | bestMove);

            if (bestMove == 0 || uint128(internalId) >= 59) {
                resetBoard();
            } else {
                board = inMemoryBoard.applyMove(bestMove);
                if (isWhiteCheckmated) {
                    resetBoard();
                }
            }
        }
    }

    function resetBoard() internal {
        board = 0x3256230011111100000000000000000099999900BCDECB000000001;
        internalId = ((internalId >> 0x80) + 1) << 0x80;
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        return bytes(baseURI).length == 0
            ? _tokenURI(_tokenId)
            : string(abi.encodePacked(baseURI, _tokenId.toString()));
    }

    function _tokenURI(uint256 _tokenId) public view returns (string memory) {
        return fiveoutofnineART.getMetadata(tokenInternalIds[_tokenId], tokenMoves[_tokenId]);
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function honorableMints() internal {
        _safeMint(0xA85572Cd96f1643458f17340b6f0D6549Af482F5, 0);
        tokenInternalIds[0] = 0;
        tokenMoves[0] = Chess.Move(
            0x3256230011111100000000000000000099999900BCDECB000000001,
            0x851C4A2
        );

        _safeMint(0x3759328b1CE944642d36a61F06783f2865212515, 1);
        tokenInternalIds[1] = 1;
        tokenMoves[1] = Chess.Move(
            0x3256230010111100000000000190000099099900BCDECB000000001,
            0x759E51C
        );

        _safeMint(0xFD8eA0F05dB884A78B1A1C1B3767B9E5D6664764, 2);
        tokenInternalIds[2] = 2;
        tokenMoves[2] = Chess.Move(
            0x3256230010101100000100009190000009099900BCDECB000000001,
            0x64DB565
        );

        _safeMint(0x174787a207BF4eD4D8db0945602e49f42c146474, 3);
        tokenInternalIds[3] = 3;
        tokenMoves[3] = Chess.Move(
            0x3256230010100100000100009199100009009900BCDECB000000001,
            0x645A725
        );

        _safeMint(0x6dEa5dCFa64DC0bb4E5AC53A375A4377CF4eD0Ee, 4);
        tokenInternalIds[4] = 4;
        tokenMoves[4] = Chess.Move(
            0x3256230010100100000000009199100009009000BCDECB000000001,
            0x631A4DB
        );

        _safeMint(0x333601a803CAc32B7D17A38d32c9728A93b422f4, 5);
        tokenInternalIds[5] = 5;
        tokenMoves[5] = Chess.Move(
            0x3256230010000100001000009199D00009009000BC0ECB000000001,
            0x6693315
        );

        _safeMint(0x530cF036Ed4Fa58f7301a9C788C9806624ceFD19, 6);
        tokenInternalIds[6] = 6;
        tokenMoves[6] = Chess.Move(
            0x32502300100061000010000091990000090D9000BC0ECB000000001,
            0x64E1554
        );

        _safeMint(0xD6A9cB7aB95293a7D38f416Cd3A4Fe9059CCd5B2, 7);
        tokenInternalIds[7] = 7;
        tokenMoves[7] = Chess.Move(
            0x325023001006010000100D009199000009009000BC0ECB000000001,
            0x63532A5
        );

        _safeMint(0xaFDc1A3EF3992f53C10fC798d242E15E2F0DF51A, 8);
        tokenInternalIds[8] = 8;
        tokenMoves[8] = Chess.Move(
            0x305023001006010000100D0091992000090C9000B00ECB000000001,
            0x66E4000
        );

        _safeMint(0xC1A80D351232fD07EE5733b5F581E01C269068A9, 9);
        tokenInternalIds[9] = 1 << 0x80;
        tokenMoves[9] = Chess.Move(
            0x3256230011111100000000000000000099999900BCDECB000000001,
            0x646155E
        );

        _safeMint(0xF42D1c0c0165AF5625b2ecD5027c5C5554e5b039, 10);
        tokenInternalIds[10] = (1 << 0x80) | 1;
        tokenMoves[10] = Chess.Move(
            0x3256230011110100000001000000000099999000BCDECB000000001,
            0x62994DB
        );
    }
}
