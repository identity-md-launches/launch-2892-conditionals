// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Conditionals} from "src/Conditionals.sol";

/// @notice Boundary and sequence properties supplementing the original token tests.
/// forge-config: default.fuzz.runs = 1024
contract ConditionalsEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Conditionals private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new Conditionals();
        alice = makeAddr("edge holder");
        bob = makeAddr("edge recipient");
        spender = makeAddr("edge spender");
    }

    function test_OneBaseUnitCanMakeARoundTrip() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LargestFiniteAllowanceIsSpentRatherThanTreatedAsUnlimited() public {
        uint256 approved = type(uint256).max - 1;
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), approved - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), approved - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithoutOverflowOrStateChanges() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumDelegatedTransferChecksBalanceDespiteUnlimitedApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalCanBeReducedAndRevokedAfterUse() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 3);
        assertEq(token.allowance(address(this), spender), 2);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalSurvivesEmptyBalanceAndCanBeSpentAfterRefill() public {
        // The holder may approve before receiving tokens. A failed spend must not consume it.
        vm.prank(alice);
        assertTrue(token.approve(spender, 3));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 3);

        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 2));
        vm.prank(spender);
        token.transferFrom(alice, bob, 2);
        assertEq(token.allowance(alice, spender), 2);

        assertTrue(token.transfer(alice, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 2));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DelegatedSelfTransferStillNeedsBalanceAndRollsBackApproval() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfApprovalAllowsHolderToSpendButIsStillConsumed() public {
        assertTrue(token.approve(address(this), SUPPLY));
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderReverts() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroDelegatedTransferToZeroRevertsWithFiniteAndUnlimitedApproval() public {
        uint256[3] memory approvals = [uint256(0), uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            assertTrue(token.approve(spender, approvals[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_FailedDelegatedTransferPreservesApprovalAndBalances(uint256 balance, uint256 amount) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.approve(spender, amount));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidReceiverDoesNotConsumeApprovalAndValidRetryWorks(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_PartitionedSpendingCannotExceedApproval(uint256 budget, uint256 first) public {
        budget = bound(budget, 0, SUPPLY);
        first = bound(first, 0, budget);
        assertTrue(token.approve(spender, budget));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), budget - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, budget - first));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - budget);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), budget - first);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RepeatedRoundTripsRestoreBalances(uint256 amount, uint256 cycles) public {
        amount = bound(amount, 0, SUPPLY);
        cycles = bound(cycles, 1, 8);
        for (uint256 i; i < cycles; ++i) {
            assertTrue(token.transfer(alice, amount));
            // Check delivery before reversing: a silent no-op must not pass a round-trip property.
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            vm.prank(alice);
            assertTrue(token.transfer(address(this), amount));
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function testFuzz_SplittingATransferDoesNotChangeDelivery(uint256 amount, uint256 first) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        Conditionals split = new Conditionals();
        assertTrue(token.transfer(alice, amount));
        assertTrue(split.transfer(alice, first));
        assertTrue(split.transfer(alice, amount - first));
        assertEq(token.balanceOf(alice), amount);
        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(split.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(split.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectAndDelegatedDeliveryAgree(uint256 balance, uint256 amount, uint256 recipientSeed) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, 0, balance);
        address[4] memory recipients = [alice, bob, spender, address(this)];
        address recipient = recipients[recipientSeed % recipients.length];
        Conditionals delegated = new Conditionals();
        assertTrue(token.transfer(alice, balance));
        assertTrue(delegated.transfer(alice, balance));
        vm.prank(alice);
        assertTrue(token.transfer(recipient, amount));
        vm.prank(alice);
        assertTrue(delegated.approve(spender, amount));
        vm.prank(spender);
        assertTrue(delegated.transferFrom(alice, recipient, amount));

        // Include recipient == holder and recipient == spender aliasing.
        for (uint256 i; i < recipients.length; ++i) {
            assertEq(delegated.balanceOf(recipients[i]), token.balanceOf(recipients[i]));
        }
        assertEq(token.balanceOf(alice), recipient == alice ? balance : balance - amount);
        assertEq(delegated.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(delegated.totalSupply(), SUPPLY);
    }
}
