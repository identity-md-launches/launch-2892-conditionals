// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Conditionals (COND)
/// @notice Fixed-supply ERC-20 with all tokens minted once to its immediate deployer.
/// @dev No owner, external mint/burn functions, fees, or upgrade mechanism.
contract Conditionals is ERC20 {
    /// @notice One billion COND, expressed in the token's 18-decimal base units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev In a factory launch, msg.sender is the factory and receives the entire supply.
    constructor() ERC20("Conditionals", "COND") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
