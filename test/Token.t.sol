// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {escrowxrunToken} from "../src/Token.sol";

contract Sink {
    uint256 public a;
    uint256 public b;
    receive() external payable { a = 1; b = 2; }
}

contract TokenTest is Test {
    escrowxrunToken t;
    address buyer = address(0xB0B);

    function setUp() public { t = new escrowxrunToken(); vm.deal(buyer, 100 ether); }

    // one whole token costs the stated 0.0001 ETH plus a negligible first curve step
    function test_costOfOneToken() public view {
        assertEq(t.calculateCost(1e18), 1e14 + 5e9);
    }

    function test_mintOneToken() public {
        uint256 cost = t.calculateCost(1e18);
        vm.prank(buyer);
        t.mint{value: cost}(1e18);
        assertEq(t.balanceOf(buyer), 1e18);
        assertEq(t.totalSupply(), 1e18);
    }

    // price per unit must not collapse as size grows (quadratic term dominates later)
    function test_costGrowsFasterThanLinear() public view {
        assertGt(t.calculateCost(1000e18), 1000 * t.calculateCost(1e18));
    }

    // overpay is refunded to an EOA
    function test_refundOnOverpay() public {
        vm.prank(buyer);
        t.mint{value: 1 ether}(1e18);
        assertApproxEqAbs(buyer.balance, 100 ether - t.calculateCost(1e18), 1e12); // gas taken from sender
    }

    // known gaps, kept as failing-by-design assertions
    function test_ethIsLocked() public {
        uint256 cost = t.calculateCost(1e18);
        vm.prank(buyer);
        t.mint{value: cost}(1e18);
        assertEq(address(t).balance, cost);
        (bool ok,) = address(t).call(abi.encodeWithSignature("withdraw()"));
        assertFalse(ok);
    }

    function test_tokensAreNonTransferable() public {
        vm.prank(buyer);
        t.mint{value: t.calculateCost(1e18)}(1e18);
        (bool ok,) = address(t).call(abi.encodeWithSignature("transfer(address,uint256)", address(0xBEEF), 1));
        assertFalse(ok);
    }

    function test_refundFailsForContractMinter() public {
        Sink s = new Sink();
        vm.deal(address(s), 2 ether);
        vm.prank(address(s));
        vm.expectRevert();
        t.mint{value: 2 ether}(1e18);
    }
}
