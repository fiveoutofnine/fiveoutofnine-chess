// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

/// @title Base64
/// @author Brecht Devos - <brecht@loopring.org>
/// @notice Provides a function for encoding some bytes in base64
library Base64 {
    string internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz012345678"
        "9+/";

    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        string memory table = TABLE;
        uint256 encodedLength = ((data.length + 2) / 3) << 2;
        string memory result = new string(encodedLength + 0x20);

        assembly {
            mstore(result, encodedLength)
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 0x20)
            for {} lt(dataPtr, endPtr) {}
            {
               dataPtr := add(dataPtr, 3)
               let input := mload(dataPtr)
               mstore(resultPtr, shl(0xF8, mload(add(tablePtr, and(shr(0x12, input), 0x3F)))))
               resultPtr := add(resultPtr, 1)
               mstore(resultPtr, shl(0xF8, mload(add(tablePtr, and(shr(0xC, input), 0x3F)))))
               resultPtr := add(resultPtr, 1)
               mstore(resultPtr, shl(0xF8, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
               resultPtr := add(resultPtr, 1)
               mstore(resultPtr, shl(0xF8, mload(add(tablePtr, and(input, 0x3F)))))
               resultPtr := add(resultPtr, 1)
            }
            switch mod(mload(data), 3)
            case 1 { mstore(sub(resultPtr, 2), shl(0xF0, 0x3D3D)) }
            case 2 { mstore(sub(resultPtr, 1), shl(0xF8, 0x3D)) }
        }

        return result;
    }
}
