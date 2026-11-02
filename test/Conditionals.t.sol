// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Conditionals} from "../src/Conditionals.sol";

/// @dev Local deployment harness; never a launch artifact.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (Conditionals) {
        return new Conditionals{salt: salt}();
    }

    function distribute(Conditionals token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

/// @dev ERC-20 delivery must not depend on a recipient accepting callbacks.
contract RejectingRecipient {
    fallback() external {
        revert("unexpected callback");
    }
}

contract ConditionalsTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    Conditionals private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new Conditionals();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Conditionals");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        Conditionals deployed = new Conditionals();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_Create2MintsToFactoryAndLaunchTransfersArriveWhole() public {
        TokenFactory factory = new TokenFactory();
        // A separate caller makes it explicit that the factory receives the mint.
        vm.prank(alice);
        Conditionals launched = factory.deploy(keccak256("Conditionals launch test"));
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool manager");
        address remainder = makeAddr("remainder recipient");
        factory.distribute(launched, distributor, SUPPLY / 10);
        factory.distribute(launched, pool, SUPPLY * 8 / 10);
        factory.distribute(launched, remainder, SUPPLY / 10);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(remainder), SUPPLY / 10);
        assertEq(launched.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, SUPPLY / 10));
        assertEq(launched.balanceOf(alice), SUPPLY / 10);
        assertEq(launched.balanceOf(distributor), 0);

        // Exercise exact delivery in both directions of the pool boundary.
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 15 ether));
        assertEq(launched.balanceOf(bob), 15 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 15 ether));
        assertEq(launched.balanceOf(pool), SUPPLY * 8 / 10);
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 12 ether);
        assertTrue(token.transfer(alice, 12 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 12 ether);
        assertEq(token.balanceOf(alice), 12 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferDoesNotChangeBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToContractDoesNotInvokeCallback() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_RevertWhenTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenEmptyAccountTransfersOneUnit() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenSelfTransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertWhenTransferToZeroEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveReplacesAndRevokesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 10 ether);
        assertTrue(token.approve(spender, 10 ether));
        assertEq(token.allowance(address(this), spender), 10 ether);

        assertTrue(token.approve(spender, 4 ether));
        assertEq(token.allowance(address(this), spender), 4 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApprovalNeedsNoCurrentBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(alice, spender), 7 ether);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenApprovingZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_AllowancesAreIsolatedByOwnerAndSpender() public {
        assertTrue(token.approve(spender, 5 ether));
        vm.prank(alice);
        assertTrue(token.approve(spender, 8 ether));
        assertTrue(token.approve(bob, 2 ether));
        assertEq(token.allowance(address(this), spender), 5 ether);
        assertEq(token.allowance(alice, spender), 8 ether);
        assertEq(token.allowance(address(this), bob), 2 ether);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_TransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 6 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.balanceOf(alice), 4 ether);
        assertEq(token.balanceOf(bob), 6 ether);
        assertEq(token.totalSupply(), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 9 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 11 ether));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 9 ether);
        assertEq(token.balanceOf(bob), 11 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 20 ether);
    }

    function test_DelegatedSelfTransferSpendsAllowanceWithoutMovingBalance() public {
        assertTrue(token.approve(spender, 9 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 4 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 5 ether);
    }

    function test_ZeroTransferFromNeedsNoAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenUnapprovedSpenderTransfers() public {
        assertTrue(token.approve(spender, 5 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 5 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_RevertWhenHolderUsesTransferFromWithoutSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_RevertWhenTransferFromExceedsAllowancePreservesState() public {
        assertTrue(token.approve(spender, 4 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 4 ether, 5 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 5 ether);
        assertEq(token.allowance(address(this), spender), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_RevertWhenTransferFromExceedsBalanceRollsBackAllowance() public {
        assertTrue(token.transfer(alice, 3 ether));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 3 ether, 4 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 4 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 3 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferFromToZeroRollsBackAllowance() public {
        assertTrue(token.approve(spender, 4 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 4 ether);
        assertEq(token.allowance(address(this), spender), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhenTransferFromZeroAddressEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), bob, 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoAdministrativeMintBurnOrUpgradeEntrypoints() public {
        assertTrue(token.transfer(alice, 10 ether));
        bytes[] memory forbiddenCalls = new bytes[](12);
        forbiddenCalls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        forbiddenCalls[1] = abi.encodeWithSignature("burn(uint256)", 1);
        forbiddenCalls[2] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        forbiddenCalls[3] = abi.encodeWithSignature("pause()");
        forbiddenCalls[4] = abi.encodeWithSignature("blacklist(address)", alice);
        forbiddenCalls[5] = abi.encodeWithSignature("freeze(address)", alice);
        forbiddenCalls[6] = abi.encodeWithSignature("seize(address)", alice);
        forbiddenCalls[7] = abi.encodeWithSignature("initialize(address)", bob);
        forbiddenCalls[8] = abi.encodeWithSignature("upgradeTo(address)", bob);
        forbiddenCalls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        forbiddenCalls[10] = abi.encodeWithSignature("owner()");
        forbiddenCalls[11] = abi.encodeWithSignature("setMinter(address)", bob);

        for (uint256 i; i < forbiddenCalls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(forbiddenCalls[i]);
            assertFalse(deployerSucceeded, "deployer reached forbidden function");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(forbiddenCalls[i]);
            assertFalse(strangerSucceeded, "stranger reached forbidden function");
        }

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_EtherPaymentsAndUnknownCallsRevert() public {
        vm.deal(address(this), 1 ether);
        (bool paid,) = address(token).call{value: 1 wei}("");
        assertFalse(paid);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertFalse(unknown);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromSpendsOnlyApprovedAmount(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhenTransferExceedsBalance(uint256 balance, uint256 excess) public {
        balance = bound(balance, 0, SUPPLY);
        excess = bound(excess, 1, type(uint256).max - balance);
        assertTrue(token.transfer(alice, balance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhenTransferFromExceedsAllowance(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_ApprovalReplacesPreviousValue(uint256 previous, uint256 replacement) public {
        assertTrue(token.approve(spender, previous));
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
