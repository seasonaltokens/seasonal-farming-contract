//SPDX-License-Identifier: MIT
pragma solidity ^0.6.5;

import "../interfaces/ERC20.sol";

// Contract function calls from the OpenZeppelin library

library Address {

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returnData) = target.call{value : value}(data);
        return verifyCallResult(success, returnData, errorMessage);
    }

    function verifyCallResult(
        bool success,
        bytes memory returnData,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returnData;
        } else {
            // Look for revert reason and bubble it up if present
            if (returnData.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returnData_size := mload(returnData)
                    revert(add(32, returnData), returnData_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


// safeTransferFrom function from OpenZeppelin's SafeERC20 library

library SafeERC20 {
    using Address for address;

    function safeTransferFrom(
        ERC20Interface token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function _callOptionalReturn(ERC20Interface token, bytes memory data) private {

        bytes memory returnData = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returnData.length > 0) {
            // Return data is optional
            require(abi.decode(returnData, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}