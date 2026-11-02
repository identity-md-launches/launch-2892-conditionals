// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Conditionals} from "../src/Conditionals.sol";

/// @dev Keeps an independent ledger across arbitrary sequences, including failed operations.
contract ConditionalsHandler is Test {
    Conditionals private immutable token;
    address[4] public actors;
    address public immutable outsider;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Conditionals token_) {
        token = token_;
        actors[0] = makeAddr("actor 0");
        actors[1] = makeAddr("actor 1");
        actors[2] = makeAddr("actor 2");
        actors[3] = makeAddr("actor 3");
        outsider = makeAddr("unapproved outsider");
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    /// @dev Deliberately reaches revocation, dust, exact balance, and both uint256 limits.
    /// Uniform uint256 approvals alone almost always exceed every possible token balance.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundarySeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[5] memory amounts =
            [uint256(0), uint256(1), expectedBalance[owner], type(uint256).max - 1, type(uint256).max];
        uint256 amount = amounts[boundarySeed % amounts.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, approved < balance ? approved : balance);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    /// @dev Unlike the success-only handler, this probes just outside the current limits.
    /// Failed calls leave the ghost ledger untouched, so the invariants check full rollback.
    function transferFromBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 boundarySeed)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256[6] memory amounts = [
            uint256(0),
            uint256(1),
            balance,
            balance + 1,
            approved == type(uint256).max ? approved : approved + 1,
            type(uint256).max
        ];
        uint256 amount = amounts[boundarySeed % amounts.length];

        if (amount > approved) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else {
            vm.prank(spender);
            assertTrue(token.transferFrom(owner, to, amount));
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) {
                expectedAllowance[owner][spender] -= amount;
            }
        }
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 limit = expectedBalance[owner];
        if (delegated && expectedAllowance[owner][spender] < limit) {
            limit = expectedAllowance[owner][spender];
        }
        amount = bound(amount, 0, limit);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function unauthorizedTransferFrom(uint256 ownerSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, 1));
        vm.prank(outsider);
        token.transferFrom(owner, to, 1);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract ConditionalsInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Conditionals private token;
    ConditionalsHandler private handler;

    function setUp() public {
        token = new Conditionals();
        handler = new ConditionalsHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferTooMuch.selector;
        selectors[4] = handler.unauthorizedTransferFrom.selector;
        selectors[5] = handler.approveBoundary.selector;
        selectors[6] = handler.transferAll.selector;
        selectors[7] = handler.transferFromBoundary.selector;
        selectors[8] = handler.transferToZero.selector;
        selectors[9] = handler.approveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_BalancesMatchLedgerAndSupplyIsConserved() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(handler.outsider()), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_AllowancesMatchLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(owner, handler.outsider()), 0);
            assertEq(token.allowance(owner, address(0)), 0);
        }
    }

    function invariant_MetadataAndSupplyConstantRemainUnchanged() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    /// @dev After every random sequence, every holder must still be able to move its full balance.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            handler.transferAll(i, (i + 1) % 4);
            invariant_BalancesMatchLedgerAndSupplyIsConserved();
            invariant_AllowancesMatchLedger();
        }
    }

    /// @dev A deterministic witness that the handler reaches nonzero spends and both failure paths.
    function test_HandlerAllowanceExhaustionRollbackRevocationAndRecovery() public {
        handler.approveBoundary(0, 1, 2); // Exact full balance.
        handler.transferFromBoundary(0, 1, 2, 2); // Spend all of it.
        invariant_BalancesMatchLedgerAndSupplyIsConserved();
        invariant_AllowancesMatchLedger();
        assertEq(token.balanceOf(handler.actors(2)), SUPPLY);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 0);

        handler.approveBoundary(2, 1, 3); // Largest finite allowance.
        handler.transferFromBoundary(2, 1, 3, 3); // Balance + 1 must revert.
        handler.transferToZero(2, 1, 1, true); // Failed delivery must also roll back the debit.
        invariant_BalancesMatchLedgerAndSupplyIsConserved();
        invariant_AllowancesMatchLedger();
        assertEq(token.allowance(handler.actors(2), handler.actors(1)), type(uint256).max - 1);

        handler.approveBoundary(2, 1, 4); // Unlimited approval survives a successful spend.
        handler.transferFrom(2, 1, 3, 1);
        invariant_BalancesMatchLedgerAndSupplyIsConserved();
        invariant_AllowancesMatchLedger();
        assertEq(token.balanceOf(handler.actors(3)), 1);
        assertEq(token.allowance(handler.actors(2), handler.actors(1)), type(uint256).max);

        handler.approveBoundary(2, 1, 0); // Revoke, then try to reuse the old approval.
        handler.transferFromBoundary(2, 1, 3, 1);
        invariant_BalancesMatchLedgerAndSupplyIsConserved();
        invariant_AllowancesMatchLedger();
        afterInvariant();
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
    }
}
